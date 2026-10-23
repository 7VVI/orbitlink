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
import org.json.JSONObject
import java.net.Proxy
import java.util.concurrent.TimeUnit

/** Password-checked pairing and RTC signaling only; media and input use WebRTC. */
class HostRelayClient(
    private val config: HostConfig,
    private val listener: Listener,
) {
    companion object {
        private const val TAG = "OrbitLinkRelay"
    }

    interface Listener {
        fun onRelayState(state: String, detail: String?)
        fun onSessionStart(controllerName: String, sessionId: String, rtc: Boolean)
        fun onSessionEnd(sessionId: String)
        fun onRtcSignal(message: JSONObject)
        fun onInput(input: JSONObject)
        fun onClipboard(text: String)
        fun onQuality(mode: String)
        fun onFps(fps: Int)
    }

    // All protocol state and listener calls are serialized on the service's main thread.
    private val main = Handler(Looper.getMainLooper())
    private var allowRemote = config.allowRemote
    private var stopped = false
    private var noReconnect = false
    private var activeSessionId: String? = null
    private var pendingSessionId: String? = null
    private var client: OkHttpClient? = null
    private var webSocket: WebSocket? = null
    private var generation = 0
    private var reconnectRunnable: Runnable? = null

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
        val gen = ++generation
        try {
            val ok = client ?: OkHttpClient.Builder()
                .proxy(Proxy.NO_PROXY)
                .pingInterval(20, TimeUnit.SECONDS)
                .connectTimeout(8, TimeUnit.SECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .build()
                .also { client = it }
            webSocket = ok.newWebSocket(
                Request.Builder().url(httpUrl).build(),
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        main.post {
                            if (stopped || gen != generation) {
                                webSocket.close(1000, "stale")
                                return@post
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
                                    put("rtc", true)
                                })
                            }
                            if (!sendJson(hello)) onDisconnected("中继连接失败")
                        }
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        main.post {
                            if (!stopped && gen == generation) handleMessage(text)
                        }
                    }

                    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                        main.post {
                            if (!stopped && gen == generation) onDisconnected("中继连接已断开")
                        }
                    }

                    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                        webSocket.close(1000, "closing")
                    }

                    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                        // Exceptions/relay messages can contain URLs, credentials or SDP.
                        Log.w(TAG, "Relay transport failed")
                        main.post {
                            if (!stopped && gen == generation) onDisconnected("中继连接失败")
                        }
                    }
                },
            )
        } catch (_: Exception) {
            onDisconnected("无法连接中继，请检查服务器地址和网络")
        }
    }

    fun isSessionAllowed(sessionId: String): Boolean =
        !stopped && allowRemote && sessionId.isNotEmpty() && activeSessionId == sessionId

    fun setAllowRemote(value: Boolean) {
        allowRemote = value
        if (!value) {
            activeSessionId?.let { endSession(it, "host_refuses") }
            pendingSessionId?.let {
                pendingSessionId = null
                if (!sendJson(JSONObject().put("t", "reject").put("session", it)
                        .put("reason", "host_refuses"))) {
                    onDisconnected("中继连接失败")
                }
            }
        }
    }

    fun sendRtcSignal(sessionId: String, signal: JSONObject): Boolean {
        if (!isSessionAllowed(sessionId)) return false
        if (signal.has("session") && signal.optString("session") != sessionId) return false
        if (signal.optString("action") !in setOf("rtc_offer", "rtc_answer", "rtc_candidate")) {
            return false
        }
        signal.put("t", "control").put("session", sessionId)
        return sendJson(signal)
    }

    /** Always release relay pairing, including when a DataChannel closes or ICE fails. */
    fun endSession(sessionId: String, reason: String = "host_ended") {
        if (activeSessionId != sessionId) return
        val sent = sendJson(JSONObject().put("t", "end").put("session", sessionId)
            .put("reason", reason))
        finishSession(sessionId)
        // A closed signaling socket cannot deliver end; disconnect to release server state.
        if (!sent) onDisconnected("中继连接已断开")
    }

    /** The channel itself is bound to sessionId; an explicit, mismatched envelope is rejected. */
    fun handleDataChannelMessage(
        sessionId: String,
        message: JSONObject,
        reply: (JSONObject) -> Boolean,
    ) {
        if (!isSessionAllowed(sessionId)) return
        if (message.has("session") && message.optString("session") != sessionId) return
        when (message.optString("t")) {
            "input" -> listener.onInput(message)
            "clipboard" -> listener.onClipboard(message.optString("text"))
            "control" -> when (message.optString("action")) {
                "ping" -> {
                    val pong = JSONObject().put("t", "control").put("action", "pong")
                        .put("session", sessionId).put("ts", message.optLong("ts"))
                    if (!reply(pong)) endSession(sessionId, "rtc_failed")
                }
                "quality" -> listener.onQuality(message.optString("mode", "高清"))
                "fps" -> listener.onFps(message.optInt("value", 30).coerceIn(5, 30))
            }
            "end" -> endSession(sessionId, "controller_ended")
        }
    }

    fun close() {
        if (stopped) return
        noReconnect = true
        activeSessionId?.let { endSession(it, "host_stopped") }
        pendingSessionId?.let {
            sendJson(JSONObject().put("t", "reject").put("session", it).put("reason", "host_stopped"))
        }
        pendingSessionId = null
        stopped = true
        generation++
        reconnectRunnable?.let { main.removeCallbacks(it) }
        reconnectRunnable = null
        webSocket?.close(1000, "host_stopped")
        webSocket = null
        client?.dispatcher?.executorService?.shutdown()
        client?.connectionPool?.evictAll()
        client = null
    }

    private fun handleMessage(text: String) {
        val message = try {
            JSONObject(text)
        } catch (_: Exception) {
            Log.w(TAG, "Invalid relay message")
            return
        }
        when (message.optString("t")) {
            "hello_ok" -> listener.onRelayState("online", null)
            "incoming" -> handleIncoming(message)
            "session_start" -> {
                val session = message.optString("session")
                // Only the incoming request we accepted (password verified by relay) may start.
                if (session.isEmpty() || session != pendingSessionId || activeSessionId != null) return
                pendingSessionId = null
                activeSessionId = session
                if (!allowRemote) {
                    endSession(session, "host_refuses")
                    return
                }
                listener.onSessionStart(message.optString("peer", "远程用户"), session,
                    message.optBoolean("rtc", false))
            }
            "control" -> {
                val session = message.optString("session")
                if (isSessionAllowed(session) &&
                    message.optString("action") in setOf("rtc_offer", "rtc_answer", "rtc_candidate")) {
                    listener.onRtcSignal(message)
                }
                // No legacy WebSocket input/clipboard/control fallback in RTC sessions.
            }
            "end" -> {
                val session = message.optString("session")
                if (pendingSessionId == session) pendingSessionId = null
                finishSession(session)
            }
            "kicked" -> {
                noReconnect = true
                onDisconnected("该识别码已在其他实例登录")
            }
            "error" -> {
                val session = message.optString("session")
                if (pendingSessionId == session) pendingSessionId = null
                listener.onRelayState("error", "中继请求失败，请检查连接设置后重试")
            }
        }
    }

    private fun handleIncoming(message: JSONObject) {
        val session = message.optString("session")
        if (session.isEmpty()) return
        val reason = when {
            !allowRemote -> "host_refuses"
            activeSessionId != null || pendingSessionId != null -> "host_busy"
            else -> null
        }
        if (reason != null) {
            if (!sendJson(JSONObject().put("t", "reject").put("session", session).put("reason", reason))) {
                onDisconnected("中继连接失败")
            }
            return
        }
        pendingSessionId = session
        if (!sendJson(JSONObject().put("t", "accept").put("session", session))) {
            onDisconnected("中继连接失败")
        }
    }

    private fun finishSession(sessionId: String) {
        if (activeSessionId != sessionId) return
        activeSessionId = null
        listener.onSessionEnd(sessionId)
    }

    private fun onDisconnected(detail: String) {
        if (stopped) return
        generation++
        val socket = webSocket
        webSocket = null
        socket?.cancel()
        pendingSessionId = null
        activeSessionId?.let { finishSession(it) }
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

    private fun sendJson(message: JSONObject): Boolean = try {
        webSocket?.send(message.toString()) == true
    } catch (_: Exception) {
        Log.w(TAG, "Relay send failed")
        false
    }
}
