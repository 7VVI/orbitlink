package com.orbitlink.remote

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

class HostService : Service() {
    companion object {
        private const val TAG = "OrbitLinkHost"
        const val ACTION_START = "com.orbitlink.remote.action.START_HOST"
        const val ACTION_STOP = "com.orbitlink.remote.action.STOP_HOST"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        private const val CHANNEL_ID = "orbitlink_host"
        private const val NOTIFICATION_ID = 7101

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var instance: HostService? = null
            private set
    }

    private val main = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var relay: HostRelayClient? = null
    private var capture: ScreenCaptureManager? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var config: HostConfig? = null
    private var qualityMode = "高清"
    private var fps = 20
    private var sessionActive = false
    private var cleaningUp = false

    private val relayListener = object : HostRelayClient.Listener {
        override fun onRelayState(state: String, detail: String?) {
            main.post {
                HostRuntime.relay = state
                HostRuntime.detail = detail
                if (!sessionActive) {
                    updateNotification(
                        when (state) {
                            "online" -> "中继在线，等待控制端连接"
                            "connecting" -> "正在连接中继服务器…"
                            else -> detail ?: "中继连接失败，正在重试"
                        },
                    )
                }
            }
        }

        override fun onSessionStart(controllerName: String) {
            main.post {
                sessionActive = true
                HostRuntime.sessionActive = true
                HostRuntime.controllerName = controllerName
                val preset = qualityPreset(qualityMode)
                capture?.setQuality(preset.second)
                capture?.setFps(fps)
                capture?.resume()
                updateNotification("$controllerName 正在控制本机")
            }
        }

        override fun onSessionEnd() {
            main.post {
                sessionActive = false
                HostRuntime.sessionActive = false
                HostRuntime.controllerName = null
                capture?.pause()
                updateNotification("等待远程控制")
            }
        }

        override fun onInput(input: JSONObject) {
            RemoteAccessibilityService.instance?.handleInput(input)
        }

        override fun onClipboard(text: String) {
            try {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("星轨远控", text))
            } catch (e: Exception) {
                Log.w(TAG, "clipboard write failed", e)
            }
        }

        override fun onQuality(mode: String) {
            main.post {
                qualityMode = mode
                val preset = qualityPreset(mode)
                capture?.setQuality(preset.second)
                capture?.setMaxLongSide(preset.first)
            }
        }

        override fun onFps(value: Int) {
            fps = value.coerceIn(5, 30)
            main.post { capture?.setFps(fps) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> finishService()
            ACTION_START -> if (!isRunning) startHosting(intent)
            else -> if (!isRunning) stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startHosting(intent: Intent) {
        val notification = buildNotification("正在启动被控服务…")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed", e)
            stopSelf()
            return
        }
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            fail("未获得屏幕共享授权")
            return
        }
        config = HostConfigStore.load(this)
        val manager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val mediaProjection = try {
            manager.getMediaProjection(resultCode, data)
        } catch (e: Exception) {
            Log.e(TAG, "getMediaProjection failed", e)
            null
        }
        if (mediaProjection == null) {
            fail("无法创建屏幕采集会话")
            return
        }
        projection = mediaProjection
        mediaProjection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                main.post { finishService() }
            }
        }, main)
        acquireWakeLock()
        capture = ScreenCaptureManager(this, mediaProjection) { jpeg, width, height ->
            relay?.sendFrame(jpeg, width, height)
            HostRuntime.width = width
            HostRuntime.height = height
        }.also {
            // Create the single VirtualDisplay immediately; pause encoding until
            // a controller connects. Android 14+ does not allow a second one.
            val preset = qualityPreset(qualityMode)
            it.start(preset.first, preset.second, fps)
            it.pause()
        }
        relay = HostRelayClient(config!!, relayListener).also { it.start() }
        isRunning = true
        instance = this
        HostRuntime.relay = "connecting"
        HostRuntime.detail = null
        HostRuntime.sessionActive = false
        updateNotification("正在连接中继服务器…")
    }

    private fun fail(message: String) {
        Log.e(TAG, message)
        HostRuntime.relay = "error"
        HostRuntime.detail = message
        cleanup()
        stopForegroundCompat()
        stopSelf()
    }

    fun setAllowRemote(value: Boolean) {
        relay?.setAllowRemote(value)
    }

    private fun qualityPreset(mode: String): Pair<Int, Int> = when (mode) {
        "流畅" -> 960 to 62
        "超清" -> 1600 to 90
        else -> 1280 to 80
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "OrbitLink:HostSession",
            ).apply {
                setReferenceCounted(false)
                acquire(4 * 60 * 60 * 1000L)
            }
        } catch (_: Exception) {
        }
    }

    private fun finishService() {
        cleanup()
        stopForegroundCompat()
        stopSelf()
    }

    private fun cleanup() {
        if (cleaningUp) return
        cleaningUp = true
        sessionActive = false
        HostRuntime.sessionActive = false
        HostRuntime.controllerName = null
        try {
            capture?.stop()
        } catch (_: Exception) {
        }
        capture = null
        try {
            relay?.close()
        } catch (_: Exception) {
        }
        relay = null
        try {
            projection?.stop()
        } catch (_: Exception) {
        }
        projection = null
        try {
            wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        isRunning = false
        instance = null
        stopStatsState()
    }

    private fun stopStatsState() {
        HostRuntime.fps = 0
        HostRuntime.width = 0
        HostRuntime.height = 0
        HostRuntime.relay = "offline"
        HostRuntime.sessionActive = false
        HostRuntime.controllerName = null
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "被控端状态",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "显示远程协助是否正在控制本机"
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, HostService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_orbitlink)
            .setContentTitle("星轨远控 · 被控端")
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE,
            )
            .addAction(0, "停止被控", stopIntent)
            .build()
    }

    private fun updateNotification(text: String) {
        try {
            val manager = NotificationManagerCompat.from(this)
            manager.notify(NOTIFICATION_ID, buildNotification(text))
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }
}
