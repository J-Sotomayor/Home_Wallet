package com.homewallet.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.homewallet.app/device_security",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openEnrollmentSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Intent(Settings.ACTION_BIOMETRIC_ENROLL).apply {
                        putExtra(
                            Settings.EXTRA_BIOMETRIC_AUTHENTICATORS_ALLOWED,
                            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                                BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                        )
                    }
                } else {
                    Intent(Settings.ACTION_SECURITY_SETTINGS)
                }
                startActivity(intent)
                result.success(null)
            } catch (_: ActivityNotFoundException) {
                startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                result.success(null)
            } catch (error: Exception) {
                result.error("settings_unavailable", error.message, null)
            }
        }
    }
}
