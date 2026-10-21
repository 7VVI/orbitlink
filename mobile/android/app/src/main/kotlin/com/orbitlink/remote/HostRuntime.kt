package com.orbitlink.remote

object HostRuntime {
    @Volatile var relay: String = "offline"
    @Volatile var detail: String? = null
    @Volatile var sessionActive: Boolean = false
    @Volatile var controllerName: String? = null
    @Volatile var width: Int = 0
    @Volatile var height: Int = 0
    @Volatile var fps: Int = 0

    fun snapshot(): Map<String, Any?> = mapOf(
        "running" to HostService.isRunning,
        "relay" to relay,
        "detail" to detail,
        "sessionActive" to sessionActive,
        "controllerName" to controllerName,
        "width" to width,
        "height" to height,
        "fps" to fps,
    )

    fun reset() {
        relay = "offline"
        detail = null
        sessionActive = false
        controllerName = null
        width = 0
        height = 0
        fps = 0
    }
}
