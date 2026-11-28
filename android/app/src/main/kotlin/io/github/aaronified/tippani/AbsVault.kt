package io.github.aaronified.tippani

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// Where the Audiobookshelf sign-in is kept: one encrypted entry per Tippani account.
///
/// The key lives in the Android Keystore and never leaves it; only the encrypted text is stored. It is
/// native on purpose. Audiobookshelf's refresh token rotates, so exactly one side may refresh it, and the
/// player service must be able to do that with the app closed and no Dart engine running (Android Auto).
/// Dart asks this vault for the current tokens and gives it the new ones; it never keeps its own copy.
///
/// Nothing here logs a value. [account] is a short id the app chooses, not a credential.
class AbsVault private constructor(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    @Synchronized
    fun get(account: String): String? {
        val stored = prefs.getString(name(account), null) ?: return null
        return try {
            val raw = Base64.decode(stored, Base64.NO_WRAP)
            val iv = raw.copyOfRange(0, IV_BYTES)
            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, iv))
            String(cipher.doFinal(raw, IV_BYTES, raw.size - IV_BYTES), Charsets.UTF_8)
        } catch (e: Exception) {
            // The key was lost (a restore onto another phone, a cleared lock screen): the entry is
            // unreadable, so forget it and let the person sign in again.
            prefs.edit().remove(name(account)).apply()
            null
        }
    }

    @Synchronized
    fun put(account: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        prefs.edit().putString(name(account), Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
    }

    @Synchronized
    fun clear(account: String) {
        prefs.edit().remove(name(account)).apply()
    }

    private fun name(account: String) = "abs.$account"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    companion object {
        private const val FILE = "abs_vault"
        private const val ALIAS = "tippani_abs_vault"
        private const val TRANSFORM = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12
        private const val TAG_BITS = 128

        @Volatile
        private var instance: AbsVault? = null

        fun of(context: Context): AbsVault =
            instance ?: synchronized(this) {
                instance ?: AbsVault(context.applicationContext).also { instance = it }
            }

        const val CHANNEL = "io.github.aaronified.tippani/abs_vault"

        /// The Dart half is lib/listen/abs/abs_token_store.dart.
        fun register(messenger: BinaryMessenger, context: Context) {
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                try {
                    val vault = of(context)
                    val account = call.argument<String>("account")
                    if (account.isNullOrBlank()) {
                        result.error("bad_args", "account is required", null)
                        return@setMethodCallHandler
                    }
                    when (call.method) {
                        "get" -> result.success(vault.get(account))
                        "put" -> {
                            vault.put(account, call.argument<String>("value") ?: "")
                            result.success(true)
                        }
                        "clear" -> {
                            vault.clear(account)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // The message is the exception class only: a value must never end up in a log.
                    result.error("vault_failed", e.javaClass.simpleName, null)
                }
            }
        }
    }
}
