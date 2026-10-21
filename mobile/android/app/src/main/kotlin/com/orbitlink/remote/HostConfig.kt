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
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "password" to password,
        "name" to name,
        "relayUrl" to relayUrl,
        "allowRemote" to allowRemote,
    )
}

object HostConfigStore {
    private const val PREFS = "orbitlink_host"
    private const val DEFAULT_RELAY = "ws://10.0.2.2:7080/ws"
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
        editor.apply()
        return HostConfig(
            id = id,
            password = password,
            name = prefs.getString("name", defaultName()) ?: defaultName(),
            relayUrl = prefs.getString("relayUrl", DEFAULT_RELAY) ?: DEFAULT_RELAY,
            allowRemote = prefs.getBoolean("allowRemote", true),
        )
    }

    fun save(context: Context, config: HostConfig): HostConfig {
        val sanitized = config.copy(
            id = config.id.filter { it.isDigit() }.take(9).ifEmpty { generateId() },
            password = config.password.ifBlank { generatePassword() },
            relayUrl = config.relayUrl.trim().ifBlank { DEFAULT_RELAY },
        )
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("id", sanitized.id)
            .putString("password", sanitized.password)
            .putString("name", sanitized.name)
            .putString("relayUrl", sanitized.relayUrl)
            .putBoolean("allowRemote", sanitized.allowRemote)
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
