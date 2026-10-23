package com.orbitlink.remote

import android.content.Context
import android.os.Build
import java.security.SecureRandom

data class HostConfig(
    val id: String,
    val password: String,
    val name: String,
    val relayUrl: String,
    val allowRemote: Boolean,
    val stunUrl: String = "stun:stun.l.google.com:19302",
    val turnUrl: String = "",
    val turnUsername: String = "",
    val turnCredential: String = "",
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "password" to password,
        "name" to name,
        "relayUrl" to relayUrl,
        "allowRemote" to allowRemote,
        "stunUrl" to stunUrl,
        "turnUrl" to turnUrl,
        "turnUsername" to turnUsername,
        "turnCredential" to turnCredential,
    )

    // Never include credentials or user-provided URLs in diagnostic output.
    override fun toString(): String = "HostConfig(<redacted>)"
}

object HostConfigStore {
    private const val PREFS = "orbitlink_host"
    private const val DEFAULT_RELAY = "ws://10.0.2.2:7080/ws"
    private const val DEFAULT_STUN = "stun:stun.l.google.com:19302"
    private val random = SecureRandom()
    private const val PASSWORD_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"

    fun load(context: Context): HostConfig {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        var id = prefs.getString("id", null)
        var password = prefs.getString("password", null)
        val editor = prefs.edit()
        if (id == null || !Regex("^\\d{9}$").matches(id)) {
            id = generateId()
            editor.putString("id", id)
        }
        if (password.isNullOrEmpty()) {
            password = generatePassword()
            editor.putString("password", password)
        }
        if (!prefs.contains("name")) {
            editor.putString("name", defaultName())
        }
        if (!prefs.contains("relayUrl")) {
            editor.putString("relayUrl", DEFAULT_RELAY)
        }
        if (!prefs.contains("allowRemote")) {
            editor.putBoolean("allowRemote", true)
        }
        if (!prefs.contains("stunUrl")) {
            editor.putString("stunUrl", DEFAULT_STUN)
        }
        for (key in listOf("turnUrl", "turnUsername", "turnCredential")) {
            if (!prefs.contains(key)) editor.putString(key, "")
        }
        editor.apply()
        return HostConfig(
            id = id,
            password = password,
            name = prefs.getString("name", defaultName()) ?: defaultName(),
            relayUrl = prefs.getString("relayUrl", DEFAULT_RELAY) ?: DEFAULT_RELAY,
            allowRemote = prefs.getBoolean("allowRemote", true),
            stunUrl = prefs.getString("stunUrl", DEFAULT_STUN) ?: DEFAULT_STUN,
            turnUrl = prefs.getString("turnUrl", "") ?: "",
            turnUsername = prefs.getString("turnUsername", "") ?: "",
            turnCredential = prefs.getString("turnCredential", "") ?: "",
        )
    }

    fun save(context: Context, config: HostConfig): HostConfig {
        val sanitized = config.copy(
            id = config.id.filter { it.isDigit() }.take(9).ifEmpty { generateId() },
            password = config.password.ifBlank { generatePassword() },
            relayUrl = config.relayUrl.trim().ifBlank { DEFAULT_RELAY },
            stunUrl = config.stunUrl.trim(),
            turnUrl = config.turnUrl.trim(),
            turnUsername = config.turnUsername.trim(),
            // TURN credentials are opaque; do not trim or log them.
        )
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("id", sanitized.id)
            .putString("password", sanitized.password)
            .putString("name", sanitized.name)
            .putString("relayUrl", sanitized.relayUrl)
            .putBoolean("allowRemote", sanitized.allowRemote)
            .putString("stunUrl", sanitized.stunUrl)
            .putString("turnUrl", sanitized.turnUrl)
            .putString("turnUsername", sanitized.turnUsername)
            .putString("turnCredential", sanitized.turnCredential)
            .apply()
        return sanitized
    }

    fun regenerate(context: Context): HostConfig {
        val current = load(context)
        return save(
            context,
            current.copy(
                id = generateId(),
                password = generatePassword(),
            ),
        )
    }

    fun setAllowRemote(context: Context, value: Boolean): HostConfig {
        val current = load(context)
        return save(context, current.copy(allowRemote = value))
    }

    private fun generateId(): String {
        val first = 1 + random.nextInt(9)
        val rest = (0 until 8).joinToString("") { random.nextInt(10).toString() }
        return "$first$rest"
    }

    private fun generatePassword(): String =
        (0 until 6).map { PASSWORD_ALPHABET[random.nextInt(PASSWORD_ALPHABET.length)] }
            .joinToString("")

    private fun defaultName(): String = "${Build.MODEL} (Android)"
}
