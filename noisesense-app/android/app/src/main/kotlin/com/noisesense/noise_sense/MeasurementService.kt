package com.noisesense.noise_sense

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps NoiseSense in the foreground state while it measures.
 *
 * This service does no audio work. Capture and analysis stay in Dart, in the
 * same process. What the service changes is how Android treats that process:
 * since Android 9, an app with no visible activity and no foreground service
 * is handed silence by the microphone instead of audio. A running foreground
 * service lifts that restriction, at the price of a permanent notification.
 *
 * That notification is treated as a feature rather than a cost. An app that
 * listens while the screen is off should say so where the user can always see
 * it, and offer a way to stop from the same place.
 *
 * Version differences handled here:
 *  - Android 10 (API 29), the S9+'s version: a foreground service of any type
 *    keeps microphone access.
 *  - Android 11+ (API 30): the service must declare the `microphone` type and
 *    be started while the app is visible. The Dart side only starts it from
 *    the Start button, which satisfies that.
 *  - Android 14+ (API 34): the type also needs FOREGROUND_SERVICE_MICROPHONE
 *    in the manifest, and RECORD_AUDIO must already be granted, otherwise
 *    startForeground throws. Dart asks for the microphone first for that reason.
 */
class MeasurementService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // Stop pressed in the notification.
            onStopRequested?.invoke()
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Not sticky: a restarted service would have no Dart capture behind it.
        return START_NOT_STICKY
    }

    /**
     * Swiping the app away from recents destroys the Flutter engine and with
     * it the capture, so the service stops as well, rather than leaving a
     * "measuring" notification that is no longer true.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        onStopRequested?.invoke()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Low importance: shown, but without sound or vibration.
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Measurement",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while NoiseSense is measuring sound levels."
                },
            )
        }

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, MeasurementService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("NoiseSense is measuring")
            .setContentText("Sound levels only. Nothing is recorded or stored.")
            .setContentIntent(openApp)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(null, "Stop", stop).build(),
            )
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.noisesense.noise_sense.STOP_MEASURING"
        private const val CHANNEL_ID = "measurement"
        private const val NOTIFICATION_ID = 1001

        /** Set by MainActivity to forward a stop from the notification to Dart. */
        var onStopRequested: (() -> Unit)? = null
    }
}
