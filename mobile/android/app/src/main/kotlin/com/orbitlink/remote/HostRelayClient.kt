package com.orbitlink.remote

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.Buffer
import org.json.JSONObject
import java.net.Proxy
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/**
 * Android host side of the relay protocol.
 *
 * It mirrors app/lib/engine/host_engine.dart: register a 9 digit id, accept a
 * password-checked session, stream JPEG frames and forward input.
 */
class HostRelayClient(
    private val config: HostConfig,
    private val listener: Listener,
) {
    companion object {
        private const val TAG = "OrbitLinkRelay"
    }
    interface Listener {
        fun onRelayState(state: String, detail: String?)
        fun onSessionStart(controllerName: String)
        fun onSessionEnd()
        fun onInput(input: JSONObject)
        fun onClipboard(text: String)
        fun onQuality(mode: String)
        fun onFps(fps: Int)
    }

    @Volatile private var allowRemote: Boolean = config.allowRemote
    @Volatile private var stopped = false
    @Volatile private var noReconnect = false
    @Volatile private var activeSessionId: String? = null
    @Volatile private var statsFrames = 0
    @Volatile private var statsBytes = 0
    @Volatile private var frameWidth = 0
    @Volatile private var frameHeight = 0

    private var client: OkHttpClient? = null
    private var webSocket: WebSocket? = null
    private var generation = 0
    private var seq = 0
    private var statsSince = System.currentTimeMillis()
    private val main = Handler(Looper.getMainLooper())
    private var reconnectRunnable: Runnable? = null
    private var statsRunnable: Runnable? = null

    fun start() {
        if (stopped) return
        listener.onRelayState("connecting", null)
        val httpUrl = when {
            config.relayUrl.startsWith("wss://") ->
                "https://" + config.relayUrl.removePrefix("wss://")
            config.relayUrl.startsWith("ws://") ->
                "http://" + config.relayUrl.removePrefix("ws://")
            else -> config.relayUrl
        }
        try {
            val ok = client ?: OkHttpClient.Builder()
                .proxy(Proxy.NO_PROXY)
                .pingInterval(20, TimeUnit.SECONDS)
                .connectTimeout(8, TimeUnit.SECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .build()
                .also { client = it }
            val request = Request.Builder().url(httpUrl).build()
            val gen = ++generation
            Log.i(TAG, "connecting to $httpUrl (gen=$gen)")
            webSocket = ok.newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    if (stopped || gen != generation) {
                        Log.w(TAG, "stale onOpen gen=$gen current=$generation")
                        webSocket.close(1000, "stale")
                        return
                    }
                    val hello = JSONObject().apply {
                        put("t", "hello")
                        put("role", "host")
                        put("id", config.id)
                        put("password", config.password)
                        put("name", config.name)
                        put("allowRemote", allowRemote)
                        put("meta", JSONObject().apply {
                            put("platform", "android")
                            put("model", Build.MODEL)
                        })
                    }
                    Log.i(TAG, "ws open, sending hello id=${config.id}")
                    val ok = webSocket.send(hello.toString())
                    Log.i(TAG, "hello queued=$ok")
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (gen != generation || stopped) return
                    Log.d(TAG, "recv ${text.take(200)}")
                    handleMessage(text)
                }

                override fun onClosed(
                    webSocket: WebSocket,
                    code: Int,
                    reason: String,
                ) {
                    Log.i(TAG, "ws closed code=$code reason=$reason gen=$gen")
                    if (gen == generation) onDisconnected("中继连接已断开")
                }

                override fun onFailure(
                    webSocket: WebSocket,
                    t: Throwable,
                    response: Response?,
                ) {
                    Log.e(TAG, "ws failure gen=$gen", t)
                    if (gen == generation) {
                        onDisconnected(t.message ?: "中继连接失败")
                    }
                }
            })
        } catch (e: Exception) {
            listener.onRelayState("error", "中继地址无效：${e.message}")
            scheduleReconnect()
        }
    }

    fun setAllowRemote(value: Boolean) {
        allowRemote = value
    }

    fun sendFrame(jpeg: ByteArray, width: Int, height: Int) {
        val session = activeSessionId ?: return
        val socket = webSocket ?: return
        if (session.isEmpty()) return
        frameWidth = width
        frameHeight = height
        val header = ByteBuffer.allocate(17).order(ByteOrder.LITTLE_ENDIAN)
        header.put(1)
        header.putInt(seq++)
        header.putShort(width.toShort())
        header.putShort(height.toShort())
        header.putLong(System.currentTimeMillis())
        val buffer = Buffer()
        buffer.write(header.array())
        buffer.write(jpeg)
        if (socket.send(buffer.readByteString())) {
            statsFrames++
            statsBytes += jpeg.size + 17
        }
    }

    fun close() {
        stopped = true
        noReconnect = true
        generation++
        reconnectRunnable?.let { main.removeCallbacks(it) }
        statsRunnable?.let { main.removeCallbacks(it) }
        reconnectRunnable = null
        statsRunnable = null
        activeSessionId = null
        try {
            webSocket?.close(1000, "host_stopped")
        } catch (_: Exception) {
        }
        webSocket = null
        try {
            client?.dispatcher?.executorService?.shutdown()
            client?.connectionPool?.evictAll()
        } catch (_: Exception) {
        }
        client = null
    }

    private fun handleMessage(text: String) {
        val message = try {
            JSONObject(text)
        } catch (_: Exception) {
            return
        }
        when (message.optString("t")) {
            "hello_ok" -> listener.onRelayState("online", null)
            "incoming" -> handleIncoming(message)
            "session_start" -> {
                activeSessionId = message.optString("session")
                val peer = message.optString("peer", "远程用户")
                listener.onSessionStart(peer)
                startStats()
            }
            "input" -> listener.onInput(message)
            "clipboard" -> listener.onClipboard(message.optString("text"))
            "control" -> handleControl(message)
            "end" -> finishSession()
            "kicked" -> {
                noReconnect = true
                listener.onRelayState("error", "该识别码已在其他实例登录")
                try {
                    webSocket?.close(1000, "kicked")
                } catch (_: Exception) {
                }
            }
            "error" -> listener.onRelayState(
                "error",
                message.optString("reason", "中继返回错误"),
            )
        }
    }

    private fun handleIncoming(message: JSONObject) {
        val session = message.optString("session")
        if (session.isEmpty()) return
        if (!allowRemote) {
            sendJson(JSONObject().apply {
                put("t", "reject")
                put("session", session)
                put("reason", "host_refuses")
            })
            return
        }
        if (activeSessionId != null) {
            sendJson(JSONObject().apply {
                put("t", "reject")
                put("session", session)
                put("reason", "host_busy")
            })
            return
        }
        sendJson(JSONObject().apply {
            put("t", "accept")
            put("session", session)
        })
    }

    private fun handleControl(message: JSONObject) {
        when (message.optString("action")) {
            "ping" -> sendJson(JSONObject().apply {
                put("t", "control")
                put("action", "pong")
                put("ts", message.optLong("ts"))
            })
            "quality" -> listener.onQuality(message.optString("mode", "高清"))
            "fps" -> listener.onFps(message.optInt("value", 10))
        }
    }

    private fun finishSession() {
        if (activeSessionId == null) return
        activeSessionId = null
        stopStats()
        listener.onSessionEnd()
    }

    private fun onDisconnected(detail: String) {
        if (stopped) return
        val wasActive = activeSessionId != null
        activeSessionId = null
        stopStats()
        if (wasActive) listener.onSessionEnd()
        listener.onRelayState("error", detail)
        scheduleReconnect()
    }

    private fun scheduleReconnect() {
        if (stopped || noReconnect) return
        reconnectRunnable?.let { main.removeCallbacks(it) }
        val runnable = Runnable {
            reconnectRunnable = null
            if (!stopped && !noReconnect) start()
        }
        reconnectRunnable = runnable
        main.postDelayed(runnable, 3000)
    }

    private fun startStats() {
        stopStats()
        statsFrames = 0
        statsBytes = 0
        statsSince = System.currentTimeMillis()
        val runnable = object : Runnable {
            override fun run() {
                if (stopped || activeSessionId == null) return
                val elapsed =
                    ((System.currentTimeMillis() - statsSince) / 1000.0)
                        .coerceAtLeast(0.2)
                val fps = (statsFrames / elapsed).roundToInt()
                val kbps =
                    (statsBytes * 8 / 1000.0 / elapsed).roundToInt()
                HostRuntime.fps = fps
                HostRuntime.width = frameWidth
                HostRuntime.height = frameHeight
                sendJson(JSONObject().apply {
                    put("t", "stats")
                    put("fps", fps)
                    put("kbps", kbps)
                    put("width", frameWidth)
                    put("height", frameHeight)
                })
                statsFrames = 0
                statsBytes = 0
                statsSince = System.currentTimeMillis()
                statsRunnable = this
                main.postDelayed(this, 1000)
            }
        }
        statsRunnable = runnable
        main.postDelayed(runnable, 1000)
    }

    private fun stopStats() {
        statsRunnable?.let { main.removeCallbacks(it) }
        statsRunnable = null
    }

    private fun sendJson(message: JSONObject) {
        try {
            val socket = webSocket
            if (socket == null) {
                Log.w(TAG, "send skipped (no socket): ${message.optString("t")}")
                return
            }
            val ok = socket.send(message.toString())
            if (!ok) Log.w(TAG, "send rejected: ${message.optString("t")}")
        } catch (e: Exception) {
            Log.e(TAG, "send failed: ${message.optString("t")}", e)
        }
    }
}
