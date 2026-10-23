package com.orbitlink.remote

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.orbitlink.remote/host"
        private const val REQ_CAPTURE = 1001
        private const val REQ_NOTIFICATION = 1002
    }

    private var pendingStart: MethodChannel.Result? = null
    private var pendingStartAfterNotification = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getHostConfig" ->
                        result.success(HostConfigStore.load(this).toMap())
                    "saveHostConfig" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val current = HostConfigStore.load(this)
                        val config = current.copy(
                            id = (args["id"] as? String) ?: current.id,
                            password = (args["password"] as? String) ?: current.password,
                            name = (args["name"] as? String) ?: current.name,
                            relayUrl = (args["relayUrl"] as? String) ?: current.relayUrl,
                            allowRemote = (args["allowRemote"] as? Boolean)
                                ?: current.allowRemote,
                            stunUrl = (args["stunUrl"] as? String) ?: current.stunUrl,
                            turnUrl = (args["turnUrl"] as? String) ?: current.turnUrl,
                            turnUsername = (args["turnUsername"] as? String)
                                ?: current.turnUsername,
                            turnCredential = (args["turnCredential"] as? String)
                                ?: current.turnCredential,
                        )
                        result.success(HostConfigStore.save(this, config).toMap())
                    }
                    "startHosting" -> startHosting(result)
                    "stopHosting" -> {
                        stopService(Intent(this, HostService::class.java))
                        result.success(null)
                    }
                    "getHostStatus" -> result.success(hostStatus())
                    "isAccessibilityEnabled" ->
                        result.success(isAccessibilityEnabled())
                    "openAccessibilitySettings" -> {
                        openAccessibility()
                        result.success(null)
                    }
                    "isNotificationPermissionGranted" ->
                        result.success(notificationGranted())
                    "requestNotificationPermission" -> {
                        requestNotifications()
                        result.success(null)
                    }
                    "openBatteryOptimizationSettings" -> {
                        openBattery()
                        result.success(null)
                    }
                    "regenerateIdentity" -> {
                        if (HostService.isRunning) {
                            result.success(false)
                        } else {
                            HostConfigStore.regenerate(this)
                            result.success(true)
                        }
                    }
                    "updateAllowRemote" -> {
                        val value =
                            (call.arguments as? Map<*, *>)?.get("value") as? Boolean
                                ?: true
                        HostConfigStore.setAllowRemote(this, value)
                        HostService.instance?.setAllowRemote(value)
                        result.success(null)
                    }
                    "getDeviceName" -> result.success(Build.MODEL)
                    "loadRecentsJson" -> {
                        val file = File(filesDir, "recents.json")
                        result.success(
                            if (file.exists()) file.readText() else "",
                        )
                    }
                    "saveRecentsJson" -> {
                        val json = (call.arguments as? Map<*, *>)?.get("json")
                            as? String ?: ""
                        try {
                            File(filesDir, "recents.json").writeText(json)
                        } catch (_: Exception) {
                        }
                        result.success(null)
                    }
                    "setKeepScreenOn" -> {
                        val value =
                            (call.arguments as? Map<*, *>)?.get("value") as? Boolean
                                ?: false
                        runOnUiThread {
                            if (value) {
                                window.addFlags(
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                                )
                            } else {
                                window.clearFlags(
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                                )
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hostStatus(): Map<String, Any?> {
        val map = HostRuntime.snapshot().toMutableMap()
        map["running"] = HostService.isRunning
        map["accessibilityEnabled"] = isAccessibilityEnabled()
        map["notificationGranted"] = notificationGranted()
        return map
    }

    private fun startHosting(result: MethodChannel.Result) {
        if (HostService.isRunning) {
            result.success(true)
            return
        }
        if (pendingStart != null) {
            result.success(false)
            return
        }
        pendingStart = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !notificationGranted()
        ) {
            pendingStartAfterNotification = true
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_NOTIFICATION,
            )
            return
        }
        launchScreenCapture()
    }

    private fun launchScreenCapture() {
        val manager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            // Force the whole display; without this Android 14+ may default to
            // sharing a single app, which cannot represent the full desktop.
            manager.createScreenCaptureIntent(
                MediaProjectionConfig.createConfigForDefaultDisplay(),
            )
        } else {
            manager.createScreenCaptureIntent()
        }
        startActivityForResult(intent, REQ_CAPTURE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIFICATION && pendingStartAfterNotification) {
            pendingStartAfterNotification = false
            launchScreenCapture()
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_CAPTURE) return
        val result = pendingStart
        pendingStart = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            val intent = Intent(this, HostService::class.java).apply {
                action = HostService.ACTION_START
                putExtra(HostService.EXTRA_RESULT_CODE, resultCode)
                putExtra(HostService.EXTRA_RESULT_DATA, data)
            }
            try {
                ContextCompat.startForegroundService(this, intent)
                result?.success(true)
            } catch (_: Exception) {
                result?.success(false)
            }
        } else {
            result?.success(false)
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val manager =
            getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabled = manager.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_ALL_MASK,
        )
        return enabled.any {
            val info = it.resolveInfo?.serviceInfo ?: return@any false
            info.packageName == packageName &&
                info.name == RemoteAccessibilityService::class.java.name
        }
    }

    private fun openAccessibility() {
        try {
            startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
        }
    }

    private fun notificationGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !notificationGranted()
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_NOTIFICATION,
            )
        }
    }

    private fun openBattery() {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                )
            } catch (_: Exception) {
            }
        }
    }
}
