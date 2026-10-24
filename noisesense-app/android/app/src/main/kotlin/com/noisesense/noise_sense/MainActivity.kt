package com.noisesense.noise_sense

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Dart measurement code to [MeasurementService].
 *
 * The channel carries three calls from Dart (begin, end, and a notification
 * permission request) and one back to it (stopRequested, when the user taps
 * Stop in the notification). Platform channels are the documented Flutter
 * mechanism for platform features no plugin covers; keeping this to a few
 * lines means the native surface stays small enough to review in full.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        MeasurementService.onStopRequested = {
            runOnUiThread { channel.invokeMethod("stopRequested", null) }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "begin" -> {
                    try {
                        val intent = Intent(this, MeasurementService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        // Most likely a background-start restriction or a missing permission on Android 14.
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "end" -> {
                    stopService(Intent(this, MeasurementService::class.java))
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    // Android 13+ asks before showing notifications.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2001)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        MeasurementService.onStopRequested = null
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "com.noisesense/measurement_service"
    }
}
