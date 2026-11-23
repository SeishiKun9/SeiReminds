package com.seireminds.seireminds

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Foreground service that drives silent, vibration-only alarms (NO audio)
 * continuously until the user explicitly presses Stop so it never disturbs class.
 */
class AlarmPlaybackService : Service() {
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopAlarmAndService()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "SeiReminds Class"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: "Your class reminder is active."

        ensureChannels(this)
        val notification = buildActiveNotification(this, title, body)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                FOREGROUND_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
        startContinuousVibration()

        // Keep running and vibrating continuously until the user presses Stop.
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        stopVibration()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun stopAlarmAndService() {
        stopVibration()
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        // shortcut: 30-min wakelock cap prevents runaway battery drain if phone is unattended; vibration loops until Stop.
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "seireminds:alarm_playback_wakelock",
        ).apply {
            acquire(MAX_WAKELOCK_MILLIS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun startContinuousVibration() {
        val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        vibrator = vib
        if (!vib.hasVibrator()) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val effect = if (vib.hasAmplitudeControl()) {
                    VibrationEffect.createWaveform(
                        HARD_VIBRATION_TIMINGS,
                        HARD_VIBRATION_AMPLITUDES,
                        0,
                    )
                } else {
                    VibrationEffect.createWaveform(HARD_VIBRATION_TIMINGS, 0)
                }
                // USAGE_ALARM lets vibration run even while phone is in Silent mode (zero audio).
                val attrs = VibrationAttributes.Builder()
                    .setUsage(VibrationAttributes.USAGE_ALARM)
                    .build()
                vib.vibrate(effect, attrs)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = if (vib.hasAmplitudeControl()) {
                    VibrationEffect.createWaveform(
                        HARD_VIBRATION_TIMINGS,
                        HARD_VIBRATION_AMPLITUDES,
                        0,
                    )
                } else {
                    VibrationEffect.createWaveform(HARD_VIBRATION_TIMINGS, 0)
                }
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                @Suppress("DEPRECATION")
                vib.vibrate(effect, attrs)
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(HARD_VIBRATION_TIMINGS, 0)
            }
        } catch (_: Exception) {
            // Keep notification with Stop button visible if hardware vibrator rejects waveform.
        }
    }

    private fun stopVibration() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null
    }

    companion object {
        const val ACTION_START = "com.seireminds.seireminds.ACTION_START_ALARM"
        const val ACTION_STOP = "com.seireminds.seireminds.ACTION_STOP_ALARM"

        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_SESSION_LABEL = "session_label"

        // Versioned v2 channels ensure existing installs immediately switch to silent (no-audio) channels.
        private const val LEGACY_ACTIVE_CHANNEL_ID = "seireminds_alarm_active_v1"
        private const val LEGACY_FALLBACK_CHANNEL_ID = "seireminds_alarm_fallback_v1"
        private const val LEGACY_CANVAS_CHANNEL_ID = "seireminds_canvas_today_v1"

        private const val ACTIVE_CHANNEL_ID = "seireminds_alarm_active_v2"
        private const val FALLBACK_CHANNEL_ID = "seireminds_alarm_fallback_v2"
        private const val CANVAS_TODAY_CHANNEL_ID = "seireminds_canvas_today_v2"
        private const val FOREGROUND_NOTIFICATION_ID = 4201
        private const val MAX_WAKELOCK_MILLIS = 30 * 60 * 1000L

        private val HARD_VIBRATION_TIMINGS = longArrayOf(0, 750, 220, 750, 220, 1100, 350)
        private val HARD_VIBRATION_AMPLITUDES = intArrayOf(0, 255, 0, 255, 0, 255, 0)
        private val CANVAS_VIBRATION_TIMINGS = longArrayOf(0, 350, 180, 350)

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Remove legacy v1 channels that may have cached audio settings on Android.
            nm.deleteNotificationChannel(LEGACY_ACTIVE_CHANNEL_ID)
            nm.deleteNotificationChannel(LEGACY_FALLBACK_CHANNEL_ID)
            nm.deleteNotificationChannel(LEGACY_CANVAS_CHANNEL_ID)

            if (nm.getNotificationChannel(ACTIVE_CHANNEL_ID) == null) {
                val activeChannel = NotificationChannel(
                    ACTIVE_CHANNEL_ID,
                    "SeiReminds Vibration Alarms",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Silent vibration-only class alarms (no audio) that vibrate until you press Stop."
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    // Zero audio; continuous vibration is driven directly by AlarmPlaybackService until Stop.
                    setSound(null, null)
                    enableVibration(false)
                }
                nm.createNotificationChannel(activeChannel)
            }

            if (nm.getNotificationChannel(FALLBACK_CHANNEL_ID) == null) {
                val fallbackChannel = NotificationChannel(
                    FALLBACK_CHANNEL_ID,
                    "SeiReminds Fallback Vibration Alarms",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Silent vibration-only fallback notifications (no audio)."
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setSound(null, null)
                    enableVibration(true)
                    vibrationPattern = HARD_VIBRATION_TIMINGS
                }
                nm.createNotificationChannel(fallbackChannel)
            }

            if (nm.getNotificationChannel(CANVAS_TODAY_CHANNEL_ID) == null) {
                val canvasChannel = NotificationChannel(
                    CANVAS_TODAY_CHANNEL_ID,
                    "SeiReminds Canvas Updates (Vibrate Only)",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Silent vibration-only notifications for Canvas announcements and activities posted today."
                    setSound(null, null)
                    enableVibration(true)
                    vibrationPattern = CANVAS_VIBRATION_TIMINGS
                }
                nm.createNotificationChannel(canvasChannel)
            }
        }

        private fun buildActiveNotification(
            context: Context,
            title: String,
            body: String,
        ): Notification {
            val openAppIntent = PendingIntent.getActivity(
                context,
                FOREGROUND_NOTIFICATION_ID,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val stopIntent = PendingIntent.getService(
                context,
                FOREGROUND_NOTIFICATION_ID + 1,
                Intent(context, AlarmPlaybackService::class.java).apply {
                    action = ACTION_STOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, ACTIVE_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setSound(null)
            }

            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(openAppIntent)
                .setFullScreenIntent(openAppIntent, true)

            val stopAction = Notification.Action.Builder(
                null,
                "Stop Alarm",
                stopIntent,
            ).build()
            builder.addAction(stopAction)

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                builder.setPriority(Notification.PRIORITY_MAX)
            }
            return builder.build()
        }

        fun postFallbackAlarmNotification(
            context: Context,
            alarmId: Int,
            title: String,
            body: String,
        ) {
            ensureChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val openAppIntent = PendingIntent.getActivity(
                context,
                alarmId,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, FALLBACK_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
                    .setSound(null)
                    .setVibrate(HARD_VIBRATION_TIMINGS)
            }

            val notification = builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setContentIntent(openAppIntent)
                .setFullScreenIntent(openAppIntent, true)
                .build()

            nm.notify(alarmId, notification)
        }

        fun postTodayCanvasNotification(
            context: Context,
            notificationId: Int,
            title: String,
            body: String,
        ) {
            ensureChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val openAppIntent = PendingIntent.getActivity(
                context,
                notificationId,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CANVAS_TODAY_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
                    .setSound(null)
                    .setVibrate(CANVAS_VIBRATION_TIMINGS)
            }

            val notification = builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(openAppIntent)
                .build()

            nm.notify(notificationId, notification)
        }
    }
}
