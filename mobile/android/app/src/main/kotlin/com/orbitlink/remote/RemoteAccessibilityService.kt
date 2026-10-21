package com.orbitlink.remote

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject
import kotlin.math.hypot

/**
 * No-root input injection for the controlled Android device.
 *
 * Touch / gesture input uses AccessibilityService.dispatchGesture. Text is
 * appended to the focused editable node with ACTION_SET_TEXT. Global actions
 * map to back / home / recents. Requires the user to enable this service in
 * Android Settings; the host still streams video if it is disabled.
 */
class RemoteAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "OrbitLinkA11y"

        @Volatile
        var instance: RemoteAccessibilityService? = null
            private set
    }

    private val main = Handler(Looper.getMainLooper())
    private var lastX = 0.5f
    private var lastY = 0.5f
    private var mouseDown = false
    private var mouseButton = "left"
    private var mouseDownAt = 0L
    private var mouseDownX = 0.5f
    private var mouseDownY = 0.5f
    private var points = mutableListOf<Pair<Float, Float>>()
    private var lastPointAt = 0L
    private var touchActive = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    fun handleInput(input: JSONObject) {
        val copy = try {
            JSONObject(input.toString())
        } catch (_: Exception) {
            return
        }
        main.post {
            try {
                process(copy)
            } catch (e: Exception) {
                Log.e(TAG, "input failed", e)
            }
        }
    }

    private fun process(input: JSONObject) {
        when (input.optString("kind")) {
            "mouse" -> handleMouse(input)
            "touch" -> handleTouch(input)
            "key" -> handleKey(input)
            "text" -> appendText(input.optString("text"))
            "global" -> performGlobal(input.optString("action"))
        }
    }

    private fun handleMouse(input: JSONObject) {
        val nx = input.optDouble("x", lastX.toDouble()).toFloat()
        val ny = input.optDouble("y", lastY.toDouble()).toFloat()
        when (input.optString("action")) {
            "move" -> {
                lastX = nx.coerceIn(0f, 1f)
                lastY = ny.coerceIn(0f, 1f)
                if (mouseDown) addPoint(lastX, lastY)
            }
            "down" -> {
                lastX = nx.coerceIn(0f, 1f)
                lastY = ny.coerceIn(0f, 1f)
                mouseDown = true
                mouseButton = input.optString("button", "left")
                mouseDownAt = System.currentTimeMillis()
                mouseDownX = lastX
                mouseDownY = lastY
                points = mutableListOf()
                addPoint(lastX, lastY, force = true)
            }
            "up" -> {
                if (!mouseDown) return
                mouseDown = false
                addPoint(lastX, lastY, force = true)
                val duration = System.currentTimeMillis() - mouseDownAt
                val start = toPixels(mouseDownX, mouseDownY)
                val end = toPixels(lastX, lastY)
                val distance = hypot(
                    (end.first - start.first).toDouble(),
                    (end.second - start.second).toDouble(),
                )
                when {
                    mouseButton == "right" || duration > 550 -> {
                        if (distance < dp(24)) {
                            dispatchLongPress(lastX, lastY)
                        } else {
                            dispatchPath(points, 320)
                        }
                    }
                    distance > dp(12) && points.size > 1 -> dispatchPath(points, 260)
                    else -> dispatchTap(lastX, lastY)
                }
                points = mutableListOf()
            }
            "wheel" -> {
                val delta = input.optDouble("delta", 0.0)
                if (delta != 0.0) scrollAt(lastX, lastY, delta > 0)
            }
        }
    }

    private fun handleTouch(input: JSONObject) {
        val nx = input.optDouble("x", lastX.toDouble()).toFloat().coerceIn(0f, 1f)
        val ny = input.optDouble("y", lastY.toDouble()).toFloat().coerceIn(0f, 1f)
        lastX = nx
        lastY = ny
        when (input.optString("action")) {
            "down" -> {
                touchActive = true
                points = mutableListOf()
                addPoint(nx, ny, force = true)
            }
            "move" -> if (touchActive) addPoint(nx, ny)
            "up" -> {
                if (!touchActive) return
                touchActive = false
                addPoint(nx, ny, force = true)
                val start = toPixels(points.firstOrNull()?.first ?: nx,
                    points.firstOrNull()?.second ?: ny)
                val end = toPixels(nx, ny)
                val distance = hypot(
                    (end.first - start.first).toDouble(),
                    (end.second - start.second).toDouble(),
                )
                if (points.size <= 1 || distance < dp(12)) {
                    dispatchTap(nx, ny)
                } else {
                    dispatchPath(points, 260)
                }
                points = mutableListOf()
            }
        }
    }

    private fun handleKey(input: JSONObject) {
        if (input.optString("action") != "down") return
        when (input.optInt("vk", -1)) {
            0x08 -> backspace()
            0x0D -> pressEnter()
            0x1B -> performGlobal("back")
        }
    }

    private fun addPoint(nx: Float, ny: Float, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastPointAt < 16) return
        lastPointAt = now
        val (x, y) = toPixels(nx, ny)
        points.add(x to y)
        if (points.size > 64) points.removeAt(1)
    }

    private fun dispatchTap(nx: Float, ny: Float) {
        val (x, y) = toPixels(nx, ny)
        dispatchPath(listOf(x to y), 50)
    }

    private fun dispatchLongPress(nx: Float, ny: Float) {
        val (x, y) = toPixels(nx, ny)
        dispatchPath(listOf(x to y), 650)
    }

    private fun dispatchPath(points: List<Pair<Float, Float>>, durationMs: Long) {
        if (points.isEmpty()) return
        val path = Path()
        path.moveTo(points.first().first, points.first().second)
        for (i in 1 until points.size) {
            path.lineTo(points[i].first, points[i].second)
        }
        val stroke = GestureDescription.StrokeDescription(
            path,
            0,
            durationMs.coerceAtLeast(1),
        )
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    private fun scrollAt(nx: Float, ny: Float, up: Boolean) {
        val (x, y) = toPixels(nx, ny)
        val startY = if (up) y - dp(160) else y + dp(160)
        val endY = if (up) y + dp(160) else y - dp(160)
        dispatchPath(listOf(x to startY, x to endY), 260)
    }

    private fun appendText(text: String) {
        if (text.isEmpty()) return
        val focused = focusedNode() ?: return
        val existing = focused.text?.toString() ?: ""
        setText(focused, existing + text)
    }

    private fun backspace() {
        val focused = focusedNode() ?: return
        val existing = focused.text?.toString() ?: return
        if (existing.isEmpty()) return
        setText(focused, existing.dropLast(1))
    }

    private fun pressEnter() {
        val focused = focusedNode() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            focused.performAction(
                AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id,
            )
        }
    }

    private fun setText(node: AccessibilityNodeInfo, value: String) {
        val args = Bundle()
        args.putCharSequence(
            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
            value,
        )
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun focusedNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: root.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
    }

    private fun performGlobal(action: String) {
        when (action) {
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "notifications" -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
        }
    }

    private fun toPixels(nx: Float, ny: Float): Pair<Float, Float> {
        val dm = resources.displayMetrics
        val x = nx.coerceIn(0f, 1f) * (dm.widthPixels - 1).coerceAtLeast(1)
        val y = ny.coerceIn(0f, 1f) * (dm.heightPixels - 1).coerceAtLeast(1)
        return x to y
    }

    private fun dp(value: Int): Float = value * resources.displayMetrics.density
}
