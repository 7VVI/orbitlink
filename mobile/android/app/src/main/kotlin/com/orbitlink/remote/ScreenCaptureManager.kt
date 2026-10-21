package com.orbitlink.remote

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * MediaProjection + ImageReader capture, scaled down and encoded to JPEG on a
 * private HandlerThread. One instance lives for the whole host service; the
 * virtual display is created only while a controller is connected.
 */
class ScreenCaptureManager(
    private val context: Context,
    private val projection: MediaProjection,
    private val onFrame: (ByteArray, Int, Int) -> Unit,
) {
    companion object {
        private const val TAG = "OrbitLinkCapture"
    }

    private var reader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null

    @Volatile private var quality = 70
    @Volatile private var minFrameIntervalMs = 100L
    @Volatile private var lastFrameAt = 0L
    @Volatile private var width = 0
    @Volatile private var height = 0
    @Volatile private var maxLongSide = 1280
    @Volatile private var fps = 20
    @Volatile private var running = false
    @Volatile private var started = false
    @Volatile private var paused = false

    val captureWidth: Int get() = width
    val captureHeight: Int get() = height

    val isStarted: Boolean get() = started

    fun start(maxLongSide: Int = 1280, quality: Int = 70, fps: Int = 10) {
        // Android 14+ tokens are single-use: never create a second
        // VirtualDisplay on the same MediaProjection instance.
        if (started) {
            this.quality = quality
            setFps(fps)
            resume()
            return
        }
        stop()
        this.maxLongSide = maxLongSide
        this.quality = quality
        this.fps = fps
        minFrameIntervalMs = (1000L / fps.coerceIn(5, 30)).coerceAtLeast(33L)
        val metrics = realScreenSize()
        val maxSide = maxOf(metrics.first, metrics.second).coerceAtLeast(2)
        val scale = min(1.0, maxLongSide.toDouble() / maxSide.toDouble())
        width = ((metrics.first * scale).roundToInt() / 2 * 2).coerceAtLeast(2)
        height = ((metrics.second * scale).roundToInt() / 2 * 2).coerceAtLeast(2)
        try {
            val thread = HandlerThread("orbitlink-capture").also { it.start() }
            this.thread = thread
            val handler = Handler(thread.looper)
            this.handler = handler
            val reader = ImageReader.newInstance(
                width,
                height,
                PixelFormat.RGBA_8888,
                2,
            )
            this.reader = reader
            reader.setOnImageAvailableListener({ r ->
                val image = try {
                    r.acquireLatestImage()
                } catch (_: Exception) {
                    null
                } ?: return@setOnImageAvailableListener
                try {
                    if (!running || paused) return@setOnImageAvailableListener
                    val now = System.currentTimeMillis()
                    if (now - lastFrameAt < minFrameIntervalMs) {
                        return@setOnImageAvailableListener
                    }
                    lastFrameAt = now
                    val plane = image.planes[0]
                    val buffer = plane.buffer
                    buffer.rewind()
                    val rowStride = plane.rowStride
                    val pixelStride = plane.pixelStride
                    val rowPadding = rowStride - pixelStride * width
                    val paddedWidth = width + rowPadding / pixelStride
                    val bitmap = Bitmap.createBitmap(
                        paddedWidth,
                        height,
                        Bitmap.Config.ARGB_8888,
                    )
                    bitmap.copyPixelsFromBuffer(buffer)
                    val cropped = if (paddedWidth == width) {
                        bitmap
                    } else {
                        Bitmap.createBitmap(bitmap, 0, 0, width, height)
                    }
                    val out = ByteArrayOutputStream()
                    cropped.compress(Bitmap.CompressFormat.JPEG, quality, out)
                    val bytes = out.toByteArray()
                    out.close()
                    if (cropped !== bitmap) cropped.recycle()
                    bitmap.recycle()
                    if (running) onFrame(bytes, width, height)
                } catch (e: Exception) {
                    Log.e(TAG, "capture frame failed", e)
                } finally {
                    try {
                        image.close()
                    } catch (_: Exception) {
                    }
                }
            }, handler)
            running = true
            started = true
            paused = false
            virtualDisplay = projection.createVirtualDisplay(
                "OrbitLinkCapture",
                width,
                height,
                context.resources.displayMetrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                handler,
            )
            if (virtualDisplay == null) {
                Log.e(TAG, "createVirtualDisplay returned null")
                stop()
            }
        } catch (e: Exception) {
            Log.e(TAG, "start capture failed", e)
            stop()
        }
    }

    fun pause() {
        paused = true
    }

    fun resume() {
        paused = false
        lastFrameAt = 0L
    }

    fun stop() {
        running = false
        started = false
        paused = false
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {
        }
        virtualDisplay = null
        try {
            reader?.close()
        } catch (_: Exception) {
        }
        reader = null
        thread?.quitSafely()
        thread = null
        handler = null
    }

    fun setQuality(value: Int) {
        quality = value.coerceIn(30, 95)
    }

    fun setFps(value: Int) {
        fps = value.coerceIn(5, 30)
        minFrameIntervalMs = (1000L / fps).coerceAtLeast(33L)
    }

    /**
     * The resolution is fixed for the lifetime of a MediaProjection token on
     * Android 14+. Quality changes only adjust the JPEG quality.
     */
    fun setMaxLongSide(value: Int) {
        val next = value.coerceIn(640, 1920)
        if (started) {
            Log.i(TAG, "resolution stays ${maxLongSide}px; requested ${next}px")
            return
        }
        maxLongSide = next
    }

    private fun realScreenSize(): Pair<Int, Int> {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            bounds.width() to bounds.height()
        } else {
            val dm = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(dm)
            dm.widthPixels to dm.heightPixels
        }
    }
}
