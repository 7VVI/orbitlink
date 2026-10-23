package com.orbitlink.remote

import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.Display
import android.view.WindowManager
import org.json.JSONObject
import org.webrtc.AddIceObserver
import org.webrtc.CapturerObserver
import org.webrtc.DataChannel
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.IceCandidate
import org.webrtc.IceCandidateErrorEvent
import org.webrtc.Logging
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RTCStatsReport
import org.webrtc.RtpParameters
import org.webrtc.RtpSender
import org.webrtc.ScreenCapturerAndroid
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoFrame
import org.webrtc.VideoSource
import org.webrtc.VideoTrack
import java.nio.ByteBuffer
import java.util.ArrayDeque
import kotlin.math.min
import kotlin.math.roundToInt

/** One capture per user grant; only peers/channels are replaced between sessions. Main-thread API. */
class RtcScreenHost(
    private val context: Context,
    private val config: HostConfig,
    private val listener: Listener,
) {
    interface Listener {
        fun onSignal(sessionId: String, signal: JSONObject): Boolean
        fun onMessage(sessionId: String, message: JSONObject)
        fun onConnected(sessionId: String)
        fun onFailure(sessionId: String, message: String)
        fun onCaptureStopped()
    }

    companion object {
        private const val TAG = "OrbitLinkRtc"
        private const val MAX_SIDE = 1920
        private const val MAX_ICE = 256
        private const val MAX_MESSAGE_BYTES = 1024 * 1024
        private const val CONNECT_TIMEOUT_MS = 30_000L
        private const val RECONNECT_TIMEOUT_MS = 15_000L
        private const val CONNECTION_ERROR = "远程连接失败，请检查网络或 TURN 配置后重试"
    }

    private class Session(val id: String) {
        var peer: PeerConnection? = null
        var channel: DataChannel? = null
        var sender: RtpSender? = null
        var offerSent = false
        var remoteDescriptionSet = false
        var settingRemoteDescription = false
        var pendingAnswer: SessionDescription? = null
        val remoteIce = ArrayDeque<IceCandidate>()
        val localIce = ArrayDeque<IceCandidate>()
        var addingIce = false
        var peerConnected = false
        var channelOpen = false
        var ready = false
        var timeout: Runnable? = null
        var stats: Runnable? = null
        var statsId: String? = null
        var lastFrames = 0L
        var lastStatsUs = 0.0
    }

    private val main = Handler(Looper.getMainLooper())
    private val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private var egl: EglBase? = null
    private var factory: PeerConnectionFactory? = null
    private var textureHelper: SurfaceTextureHelper? = null
    private var source: VideoSource? = null
    private var track: VideoTrack? = null
    private var capturer: ScreenCapturerAndroid? = null
    private var captureInitialized = false
    private var captureStarted = false
    private var displayListenerRegistered = false
    private var startAttempted = false
    private var disposed = false
    private var current: Session? = null
    private var width = 0
    private var height = 0
    private var quality = "高清"
    private var fps = 30
    @Volatile private var forwardFrames = false
    @Volatile private var frameIntervalNs = 1_000_000_000L / 30
    // Accessed only on the texture thread.
    private var lastFrameNs = 0L

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = Unit
        override fun onDisplayRemoved(displayId: Int) = Unit
        override fun onDisplayChanged(displayId: Int) {
            if (displayId == Display.DEFAULT_DISPLAY) updateCaptureFormat()
        }
    }

    fun startCapture(resultData: Intent) {
        check(!startAttempted && !disposed)
        startAttempted = true
        // Do not emit native SDP, candidate addresses or ICE server credentials into logcat.
        PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context)
            .setEnableInternalTracer(false)
            .setInjectableLogger({ _, _, _ -> }, Logging.Severity.LS_NONE)
            .createInitializationOptions())
        val sharedEgl = EglBase.create().also { egl = it }
        val peerFactory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(sharedEgl.eglBaseContext, true, true))
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(sharedEgl.eglBaseContext))
            .createPeerConnectionFactory().also { factory = it }
        val videoSource = peerFactory.createVideoSource(true).also { source = it }
        track = peerFactory.createVideoTrack("orbitlink-screen", videoSource).apply { setEnabled(false) }
        val helper = checkNotNull(SurfaceTextureHelper.create("OrbitLinkRtcCapture", sharedEgl.eglBaseContext))
            .also { textureHelper = it }
        val screenCapturer = ScreenCapturerAndroid(resultData, object : MediaProjection.Callback() {
            override fun onStop() {
                forwardFrames = false
                main.post { if (!disposed) listener.onCaptureStopped() }
            }

            override fun onCapturedContentResize(width: Int, height: Int) {
                main.post {
                    if (!disposed && captureStarted && width > 0 && height > 0) {
                        resizeCapture(width, height)
                    }
                }
            }
        }).also { capturer = it }
        val observer = videoSource.capturerObserver
        screenCapturer.initialize(helper, context, object : CapturerObserver {
            override fun onCapturerStarted(success: Boolean) {
                observer.onCapturerStarted(success)
                if (!success) main.post { if (!disposed) listener.onCaptureStopped() }
            }

            override fun onCapturerStopped() {
                observer.onCapturerStopped()
            }

            override fun onFrameCaptured(frame: VideoFrame) {
                // An idle projection stays alive on Android 14, but no frames reach the encoder.
                if (!forwardFrames) return
                val now = System.nanoTime()
                if (now - lastFrameNs < frameIntervalNs) return
                lastFrameNs = now
                observer.onFrameCaptured(frame)
            }
        })
        captureInitialized = true
        val size = screenSize()
        val scaled = scaledSize(size.first, size.second)
        width = scaled.first
        height = scaled.second
        videoSource.adaptOutputFormat(width, height, fps)
        // This is the ONLY startCapture call for this grant. It obtains MediaProjection itself.
        screenCapturer.startCapture(width, height, fps)
        captureStarted = true
        displayManager.registerDisplayListener(displayListener, main)
        displayListenerRegistered = true
    }

    fun startSession(sessionId: String) {
        check(!disposed && captureStarted && current == null)
        val session = Session(sessionId)
        current = session
        resetStats()
        try {
            val rtcConfig = PeerConnection.RTCConfiguration(iceServers()).apply {
                sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
                iceTransportsType = PeerConnection.IceTransportsType.ALL
                bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            }
            val peer = checkNotNull(factory?.createPeerConnection(rtcConfig, peerObserver(session)))
            session.peer = peer
            session.sender = checkNotNull(peer.addTrack(checkNotNull(track), listOf("orbitlink-screen")))
            val channel = checkNotNull(peer.createDataChannel("orbitlink-input", DataChannel.Init().apply {
                ordered = true
                maxRetransmits = -1
                maxRetransmitTimeMs = -1
            }))
            session.channel = channel
            channel.registerObserver(channelObserver(session))
            armTimeout(session, CONNECT_TIMEOUT_MS)
            peer.createOffer(sdpObserver(session, "create_offer", onCreated = { offer ->
                peer.setLocalDescription(sdpObserver(session, "set_local", onSet = {
                    if (configureSender(session)) {
                        if (sendSignal(session, JSONObject().put("action", "rtc_offer")
                                .put("type", "offer").put("sdp", offer.description))) {
                            session.offerSent = true
                            while (isCurrent(session) && session.localIce.isNotEmpty()) {
                                sendCandidate(session, session.localIce.removeFirst())
                            }
                            applyAnswer(session)
                        }
                    }
                }), offer)
            }), MediaConstraints())
        } catch (_: Exception) {
            fail(session, "start_peer")
        }
    }

    fun handleSignal(message: JSONObject) {
        val session = current ?: return
        if (disposed || message.optString("t") != "control" ||
            message.optString("session") != session.id) return
        try {
            when (message.optString("action")) {
                "rtc_answer" -> {
                    val sdp = message.optString("sdp")
                    if (message.optString("type") != "answer" || sdp.isBlank() ||
                        sdp.length > MAX_MESSAGE_BYTES || session.remoteDescriptionSet ||
                        session.settingRemoteDescription || session.pendingAnswer != null) {
                        fail(session, "invalid_answer")
                        return
                    }
                    session.pendingAnswer = SessionDescription(SessionDescription.Type.ANSWER, sdp)
                    applyAnswer(session)
                }
                "rtc_candidate" -> {
                    val json = message.optJSONObject("candidate")
                        ?: throw IllegalArgumentException("Invalid candidate envelope")
                    val candidate = json.optString("candidate")
                    if (candidate.isEmpty()) return // End-of-candidates marker.
                    val index = json.optInt("sdpMLineIndex", -1)
                    val mid = if (json.isNull("sdpMid")) null else json.optString("sdpMid")
                    if (candidate.length > 8192 || (index < 0 && mid.isNullOrEmpty()) ||
                        session.remoteIce.size >= MAX_ICE) {
                        fail(session, "invalid_candidate")
                        return
                    }
                    session.remoteIce.addLast(IceCandidate(mid, index, candidate))
                    drainRemoteIce(session)
                }
                "rtc_offer" -> fail(session, "unexpected_offer") // Host is always the offerer.
            }
        } catch (_: Exception) {
            fail(session, "remote_signal")
        }
    }

    private fun applyAnswer(session: Session) {
        if (!isCurrent(session) || !session.offerSent || session.settingRemoteDescription) return
        val answer = session.pendingAnswer ?: return
        session.pendingAnswer = null
        session.settingRemoteDescription = true
        session.peer?.setRemoteDescription(sdpObserver(session, "set_remote", onSet = {
            session.settingRemoteDescription = false
            session.remoteDescriptionSet = true
            if (configureSender(session)) drainRemoteIce(session)
        }), answer)
    }

    private fun drainRemoteIce(session: Session) {
        if (!isCurrent(session) || !session.remoteDescriptionSet || session.addingIce ||
            session.remoteIce.isEmpty()) return
        session.addingIce = true
        session.peer?.addIceCandidate(session.remoteIce.removeFirst(), object : AddIceObserver {
            override fun onAddSuccess() = post(session, "add_ice") {
                session.addingIce = false
                drainRemoteIce(session)
            }
            override fun onAddFailure(error: String) = post(session, "add_ice") {
                fail(session, "add_ice")
            }
        })
    }

    private fun sdpObserver(
        session: Session,
        stage: String,
        onCreated: (SessionDescription) -> Unit = {},
        onSet: () -> Unit = {},
    ) = object : SdpObserver {
        override fun onCreateSuccess(sdp: SessionDescription) = post(session, stage) { onCreated(sdp) }
        override fun onSetSuccess() = post(session, stage) { onSet() }
        override fun onCreateFailure(error: String) = post(session, stage) { fail(session, stage) }
        override fun onSetFailure(error: String) = post(session, stage) { fail(session, stage) }
    }

    private fun peerObserver(session: Session) = object : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState) = Unit
        override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) = Unit
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) = Unit
        override fun onAddStream(stream: MediaStream) = Unit
        override fun onRemoveStream(stream: MediaStream) = Unit
        override fun onRenegotiationNeeded() = Unit // A fresh peer negotiates exactly once.
        override fun onDataChannel(channel: DataChannel) {
            // Never accept an additional, controller-created input channel.
            main.post { release("unexpected_channel") { channel.close(); channel.dispose() } }
        }
        override fun onIceCandidateError(event: IceCandidateErrorEvent) {
            // One server/address can fail while another pair succeeds. The timeout remains armed.
            Log.w(TAG, "An ICE server request failed; trying other candidate pairs")
        }
        override fun onIceCandidate(candidate: IceCandidate) = post(session, "local_ice") {
            if (session.offerSent) {
                sendCandidate(session, candidate)
            } else if (session.localIce.size < MAX_ICE) {
                session.localIce.addLast(candidate)
            } else {
                fail(session, "local_ice_overflow")
            }
        }
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) =
            post(session, "ice_state") {
                when (state) {
                    PeerConnection.IceConnectionState.FAILED,
                    PeerConnection.IceConnectionState.CLOSED -> fail(session, "ice_failed")
                    PeerConnection.IceConnectionState.DISCONNECTED -> connectionInterrupted(session)
                    else -> Unit
                }
            }
        override fun onConnectionChange(state: PeerConnection.PeerConnectionState) =
            post(session, "peer_state") {
                when (state) {
                    PeerConnection.PeerConnectionState.CONNECTED -> {
                        session.peerConnected = true
                        checkReady(session)
                    }
                    PeerConnection.PeerConnectionState.DISCONNECTED -> connectionInterrupted(session)
                    PeerConnection.PeerConnectionState.FAILED,
                    PeerConnection.PeerConnectionState.CLOSED -> fail(session, "peer_failed")
                    else -> Unit
                }
            }
    }

    private fun channelObserver(session: Session) = object : DataChannel.Observer {
        override fun onBufferedAmountChange(previousAmount: Long) = Unit
        override fun onStateChange() = post(session, "channel_state") {
            when (session.channel?.state()) {
                DataChannel.State.OPEN -> {
                    session.channelOpen = true
                    checkReady(session)
                }
                DataChannel.State.CLOSING, DataChannel.State.CLOSED -> fail(session, "channel_closed")
                else -> Unit
            }
        }
        override fun onMessage(buffer: DataChannel.Buffer) {
            if (buffer.binary || buffer.data.remaining() > MAX_MESSAGE_BYTES) {
                post(session, "channel_message") { fail(session, "invalid_message") }
                return
            }
            // Native buffer lifetime ends when this callback returns; copy before posting.
            val bytes = ByteArray(buffer.data.remaining())
            buffer.data.duplicate().get(bytes)
            post(session, "channel_message") {
                if (session.ready) listener.onMessage(session.id, JSONObject(String(bytes, Charsets.UTF_8)))
            }
        }
    }

    fun sendData(sessionId: String, message: JSONObject): Boolean {
        val session = current ?: return false
        if (session.id != sessionId || !session.ready || disposed) return false
        return try {
            val channel = session.channel ?: return false
            if (channel.state() != DataChannel.State.OPEN || channel.bufferedAmount() > MAX_MESSAGE_BYTES) return false
            channel.send(DataChannel.Buffer(ByteBuffer.wrap(message.toString().toByteArray(Charsets.UTF_8)), false))
        } catch (_: Exception) {
            fail(session, "channel_send")
            false
        }
    }

    private fun sendCandidate(session: Session, candidate: IceCandidate) {
        sendSignal(session, JSONObject().put("action", "rtc_candidate").put("candidate", JSONObject()
            .put("candidate", candidate.sdp).put("sdpMid", candidate.sdpMid ?: JSONObject.NULL)
            .put("sdpMLineIndex", candidate.sdpMLineIndex)))
    }

    private fun sendSignal(session: Session, message: JSONObject): Boolean {
        if (!isCurrent(session)) return false
        message.put("t", "control").put("session", session.id)
        if (listener.onSignal(session.id, message)) return true
        fail(session, "signaling_send")
        return false
    }

    private fun iceServers(): List<PeerConnection.IceServer> = buildList {
        val stun = config.stunUrl.trim()
        if (stun.isNotEmpty()) {
            require(stun.startsWith("stun:") || stun.startsWith("stuns:"))
            add(PeerConnection.IceServer.builder(stun).createIceServer())
        }
        val turn = config.turnUrl.trim()
        if (turn.isNotEmpty()) {
            // Preserve standard turn:...?transport=udp/tcp and turns: TLS URLs.
            require(turn.startsWith("turn:") || turn.startsWith("turns:"))
            add(PeerConnection.IceServer.builder(turn).setUsername(config.turnUsername)
                .setPassword(config.turnCredential).createIceServer())
        }
    }

    fun setQuality(mode: String) {
        quality = mode
        current?.let { configureSender(it) }
    }

    fun setFps(value: Int) {
        fps = value.coerceIn(5, 30)
        frameIntervalNs = 1_000_000_000L / fps
        if (!disposed && captureStarted) {
            try {
                source?.adaptOutputFormat(width, height, fps)
                capturer?.changeCaptureFormat(width, height, fps)
            } catch (_: Exception) {
                captureFailed()
                return
            }
        }
        current?.let { configureSender(it) }
    }

    private fun configureSender(session: Session): Boolean {
        if (!isCurrent(session)) return false
        return try {
            val sender = checkNotNull(session.sender)
            val parameters = sender.parameters
            // Before setLocalDescription encodings may not yet be populated; apply again after SDP.
            if (parameters.encodings.isEmpty() && !session.offerSent) return true
            check(parameters.encodings.isNotEmpty())
            parameters.degradationPreference = RtpParameters.DegradationPreference.MAINTAIN_RESOLUTION
            val bitrate = (if (quality == "流畅") 8_000_000 else 40_000_000) * (fps / 30.0)
            parameters.encodings.forEach {
                it.active = true
                it.scaleResolutionDownBy = 1.0
                it.maxFramerate = fps
                it.maxBitrateBps = bitrate.roundToInt()
            }
            check(sender.setParameters(parameters))
            true
        } catch (_: Exception) {
            fail(session, "sender_parameters")
            false
        }
    }

    private fun checkReady(session: Session) {
        if (!isCurrent(session) || !session.peerConnected || !session.channelOpen || session.ready) return
        session.ready = true
        session.timeout?.let { main.removeCallbacks(it) }
        session.timeout = null
        track?.setEnabled(true)
        forwardFrames = true
        textureHelper?.forceFrame()
        startStats(session)
        listener.onConnected(session.id)
    }

    private fun connectionInterrupted(session: Session) {
        session.peerConnected = false
        session.ready = false
        forwardFrames = false
        track?.setEnabled(false)
        HostRuntime.fps = 0
        if (session.timeout == null) armTimeout(session, RECONNECT_TIMEOUT_MS)
    }

    private fun armTimeout(session: Session, delayMs: Long) {
        session.timeout?.let { main.removeCallbacks(it) }
        val timeout = Runnable {
            if (isCurrent(session)) fail(session, "connection_timeout", "远程连接超时，请检查网络或 TURN 配置后重试")
        }
        session.timeout = timeout
        main.postDelayed(timeout, delayMs)
    }

    fun updateCaptureFormat() {
        if (disposed || !captureStarted) return
        try {
            val size = screenSize()
            resizeCapture(size.first, size.second)
        } catch (_: Exception) {
            captureFailed()
        }
    }

    private fun resizeCapture(screenWidth: Int, screenHeight: Int) {
        val size = scaledSize(screenWidth, screenHeight)
        if (size.first == width && size.second == height) return
        try {
            // SDK 125.6422.03 resizes the existing VirtualDisplay on Android 12+, including 14.
            capturer?.changeCaptureFormat(size.first, size.second, fps)
            source?.adaptOutputFormat(size.first, size.second, fps)
            width = size.first
            height = size.second
        } catch (_: Exception) {
            captureFailed()
        }
    }

    private fun screenSize(): Pair<Int, Int> {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.maximumWindowMetrics.bounds
            bounds.width() to bounds.height()
        } else {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(metrics)
            metrics.widthPixels to metrics.heightPixels
        }
    }

    private fun scaledSize(w: Int, h: Int): Pair<Int, Int> {
        val scale = min(1.0, MAX_SIDE.toDouble() / maxOf(w, h).coerceAtLeast(2))
        return ((w * scale).roundToInt() / 2 * 2).coerceAtLeast(2) to
            ((h * scale).roundToInt() / 2 * 2).coerceAtLeast(2)
    }

    private fun startStats(session: Session) {
        session.stats?.let { main.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                if (!isCurrent(session)) return
                try {
                    session.peer?.getStats { report -> post(session, "stats") {
                        if (session.ready) updateStats(session, report)
                    } }
                    main.postDelayed(this, 1000)
                } catch (_: Exception) {
                    fail(session, "stats")
                }
            }
        }
        session.stats = runnable
        main.postDelayed(runnable, 1000)
    }

    private fun updateStats(session: Session, report: RTCStatsReport) {
        val stat = report.statsMap.values.firstOrNull {
            it.type == "outbound-rtp" && (it.members["kind"] == "video" || it.members["mediaType"] == "video")
        } ?: return
        val values = stat.members
        val frames = (values["framesEncoded"] as? Number)?.toLong() ?: 0L
        val elapsed = (stat.timestampUs - session.lastStatsUs) / 1_000_000
        val measuredFps = (values["framesPerSecond"] as? Number)?.toDouble()
            ?: if (session.statsId == stat.id && elapsed > 0) {
                (frames - session.lastFrames).coerceAtLeast(0) / elapsed
            } else 0.0
        HostRuntime.fps = measuredFps.roundToInt().coerceAtLeast(0)
        (values["frameWidth"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { HostRuntime.width = it }
        (values["frameHeight"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { HostRuntime.height = it }
        session.statsId = stat.id
        session.lastFrames = frames
        session.lastStatsUs = stat.timestampUs
        // Controller statistics come from its own RTC receiver; never send legacy WS stats.
    }

    fun endSession(sessionId: String) {
        val session = current ?: return
        if (session.id != sessionId) return
        current = null // Invalidate callbacks before close/dispose can enqueue more of them.
        forwardFrames = false
        release("disable_track") { track?.setEnabled(false) }
        session.timeout?.let { main.removeCallbacks(it) }
        session.stats?.let { main.removeCallbacks(it) }
        session.localIce.clear()
        session.remoteIce.clear()
        release("channel_observer") { session.channel?.unregisterObserver() }
        release("channel_close") { session.channel?.close() }
        release("channel_dispose") { session.channel?.dispose() }
        session.channel = null
        release("peer_dispose") { session.peer?.dispose() }
        session.peer = null
        session.sender = null // PeerConnection owns the RtpSender wrapper.
        resetStats()
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        forwardFrames = false
        current?.let { endSession(it.id) }
        if (displayListenerRegistered) displayManager.unregisterDisplayListener(displayListener)
        displayListenerRegistered = false
        // stopCapture also releases a partially-created projection after a start failure.
        if (captureInitialized) release("stop_capture") { capturer?.stopCapture() }
        release("dispose_capture") { capturer?.dispose() }
        capturer = null
        captureStarted = false
        captureInitialized = false
        release("dispose_track") { track?.dispose() }
        track = null
        release("dispose_source") { source?.dispose() }
        source = null
        release("dispose_texture") { textureHelper?.dispose() }
        textureHelper = null
        release("dispose_factory") { factory?.dispose() }
        factory = null
        release("dispose_egl") { egl?.release() }
        egl = null
        resetStats()
    }

    private fun resetStats() {
        HostRuntime.fps = 0
        HostRuntime.width = 0
        HostRuntime.height = 0
    }

    private fun isCurrent(session: Session): Boolean = !disposed && current === session

    private fun post(session: Session, stage: String, block: () -> Unit) {
        main.post {
            if (isCurrent(session)) {
                try { block() } catch (_: Exception) { fail(session, stage) }
            }
        }
    }

    private fun fail(session: Session, stage: String, message: String = CONNECTION_ERROR) {
        if (!isCurrent(session)) return
        Log.w(TAG, "RTC operation failed: $stage") // stage is internal, never a native error/SDP.
        endSession(session.id)
        listener.onFailure(session.id, message)
    }

    private fun captureFailed() {
        forwardFrames = false
        Log.w(TAG, "Screen capture failed")
        listener.onCaptureStopped()
    }

    private fun release(stage: String, block: () -> Unit) {
        try { block() } catch (_: Exception) { Log.w(TAG, "RTC cleanup failed: $stage") }
    }
}
