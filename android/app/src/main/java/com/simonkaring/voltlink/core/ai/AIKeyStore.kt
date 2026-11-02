package com.simonkaring.voltlink.core.ai

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stores the AI provider key encrypted under a non-exportable Android Keystore key.
 *
 * The Android counterpart of the iOS Keychain item: the ciphertext lives in app-private
 * preferences, the AES key never leaves the Keystore, and the entry is scoped to this device.
 */
class AIKeyStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Last read/write failure, surfaced in Settings instead of failing silently. */
    var errorMessage: String? = null
        private set

    fun read(): String {
        val stored = prefs.getString(KEY, null) ?: return ""
        if (stored.isEmpty()) return ""
        return try {
            decrypt(stored)
        } catch (e: Exception) {
            errorMessage = "Could not read the API key: ${e.message ?: e.javaClass.simpleName}"
            ""
        }
    }

    fun save(key: String) {
        val trimmed = key.trim()
        errorMessage = null
        try {
            if (trimmed.isEmpty()) prefs.edit().remove(KEY).apply() else prefs.edit().putString(KEY, encrypt(trimmed)).apply()
        } catch (e: Exception) {
            errorMessage = "Could not save the API key: ${e.message ?: e.javaClass.simpleName}"
        }
    }

    private fun encrypt(plainText: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val payload = cipher.iv + cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    private fun decrypt(encoded: String): String {
        val payload = Base64.decode(encoded, Base64.NO_WRAP)
        val iv = payload.copyOfRange(0, IV_BYTES)
        val body = payload.copyOfRange(IV_BYTES, payload.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(body), Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val PREFS = "voltlink_secrets"
        const val KEY = "ai_api_key"
        const val ALIAS = "voltlink-ai-key"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
    }
}
