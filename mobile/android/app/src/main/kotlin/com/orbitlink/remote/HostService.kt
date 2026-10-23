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
import android.content.res.Configuration
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
    private var relay: HostRelayClient? = null
    private var rtcHost: RtcScreenHost? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var activeSessionId: String? = null
    private var cleaningUp = false

    // HostRelayClient and RtcScreenHost dispatch all callbacks on the main thread.
    private val relayListener = object : HostRelayClient.Listener {
        override fun onRelayState(state: String, detail: String?) {
            if (cleaningUp) return
            HostRuntime.relay = state
            HostRuntime.detail = detail
            if (activeSessionId == null) {
                updateNotification(when (state) {
                    "online" -> "信令在线，等待控制端连接"
                    "connecting" -> "正在连接信令服务器…"
                    else -> detail ?: "信令连接失败，正在重试"
                })
            }
        }

        override fun onSessionStart(controllerName: String, sessionId: String, rtc: Boolean) {
            if (cleaningUp || relay?.isSessionAllowed(sessionId) != true) return
            activeSessionId = sessionId
            if (!rtc) {
                relay?.endSession(sessionId, "rtc_required")
                showConnectionFailure("控制端不支持 WebRTC，请更新控制端后重试")
                return
            }
            HostRuntime.sessionActive = true
            HostRuntime.controllerName = controllerName
            HostRuntime.detail = null
            updateNotification("正在与 $controllerName 建立安全连接…")
            try {
                checkNotNull(rtcHost).apply {
                    setQuality("高清")
                    setFps(30)
                    startSession(sessionId)
                }
            } catch (_: Exception) {
                relay?.endSession(sessionId, "rtc_failed")
                showConnectionFailure("远程连接失败，请检查网络或 TURN 配置后重试")
            }
        }

        override fun onSessionEnd(sessionId: String) {
            if (activeSessionId != sessionId) return
            activeSessionId = null
            rtcHost?.endSession(sessionId)
            HostRuntime.sessionActive = false
            HostRuntime.controllerName = null
            if (!cleaningUp) updateNotification("等待远程控制")
        }

        override fun onRtcSignal(message: JSONObject) {
            if (cleaningUp || message.optString("session") != activeSessionId) return
            rtcHost?.handleSignal(message)
        }

        override fun onInput(input: JSONObject) {
            if (canAcceptInput()) RemoteAccessibilityService.instance?.handleInput(input)
        }

        override fun onClipboard(text: String) {
            if (!canAcceptInput()) return
            try {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("星轨远控", text))
            } catch (_: Exception) {
                Log.w(TAG, "Clipboard write failed")
            }
        }

        override fun onQuality(mode: String) {
            if (canAcceptInput()) rtcHost?.setQuality(mode)
        }

        override fun onFps(value: Int) {
            if (canAcceptInput()) rtcHost?.setFps(value)
        }
    }

    private val rtcListener = object : RtcScreenHost.Listener {
        override fun onSignal(sessionId: String, signal: JSONObject): Boolean =
            !cleaningUp && activeSessionId == sessionId && relay?.sendRtcSignal(sessionId, signal) == true

        override fun onMessage(sessionId: String, message: JSONObject) {
            if (cleaningUp || activeSessionId != sessionId) return
            relay?.handleDataChannelMessage(sessionId, message) { pong ->
                rtcHost?.sendData(sessionId, pong) == true
            }
        }

        override fun onConnected(sessionId: String) {
            if (cleaningUp || activeSessionId != sessionId) return
            updateNotification("${HostRuntime.controllerName ?: "远程用户"} 正在控制本机")
        }

        override fun onFailure(sessionId: String, message: String) {
            if (cleaningUp || activeSessionId != sessionId) return
            relay?.endSession(sessionId, "rtc_failed")
            showConnectionFailure(message)
        }

        override fun onCaptureStopped() {
            if (!cleaningUp) finishService()
        }
    }

    private fun canAcceptInput(): Boolean = !cleaningUp &&
        activeSessionId?.let { relay?.isSessionAllowed(it) } == true

    private fun showConnectionFailure(message: String) {
        if (cleaningUp) return
        HostRuntime.detail = message
        updateNotification(message)
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
        val config = HostConfigStore.load(this)
        try {
            // Pass the already-authorized Intent directly. ScreenCapturerAndroid alone
            // obtains MediaProjection and creates the single shared VirtualDisplay.
            val host = RtcScreenHost(this, config, rtcListener)
            rtcHost = host // Retain partial initialization for cleanup if native startup fails.
            host.startCapture(data)
            acquireWakeLock()
            isRunning = true
            instance = this
            HostRuntime.relay = "connecting"
            HostRuntime.detail = null
            HostRuntime.sessionActive = false
            val client = HostRelayClient(config, relayListener)
            relay = client
            client.start()
        } catch (_: Exception) {
            fail("无法启动屏幕共享，请重新授权后重试")
        }
    }

    private fun fail(message: String) {
        Log.e(TAG, message)
        cleanup()
        HostRuntime.relay = "error"
        HostRuntime.detail = message
        stopForegroundCompat()
        stopSelf()
    }

    fun setAllowRemote(value: Boolean) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            relay?.setAllowRemote(value)
        } else {
            main.post { if (!cleaningUp) relay?.setAllowRemote(value) }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        rtcHost?.updateCaptureFormat()
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
        // Notify relay before closing signaling, even for notification/system-projection stop.
        try {
            relay?.close()
        } catch (_: Exception) {
            Log.w(TAG, "Relay cleanup failed")
        }
        relay = null
        activeSessionId = null
        try {
            rtcHost?.dispose()
        } catch (_: Exception) {
            Log.w(TAG, "RTC cleanup failed")
        }
        rtcHost = null
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
