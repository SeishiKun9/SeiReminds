package com.seireminds.seireminds

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
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
 * with a priority heads-up notification whose Stop button cancels vibration
 * directly via AlarmStopReceiver without opening the app.
 */
class AlarmPlaybackService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopAlarmAndService()
            return START_NOT_STICKY
        }

        val alarmId = intent?.getIntExtra(EXTRA_ALARM_ID, FOREGROUND_NOTIFICATION_ID)
            ?: FOREGROUND_NOTIFICATION_ID
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "SeiReminds Class"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: "Your class is starting soon."

        ensureChannels(this)
        val notification = buildActiveNotification(this, alarmId, title, body)
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

        // Keep running and vibrating continuously until the user taps Stop.
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        cancelActiveVibration(this)
        releaseWakeLock()
        super.onDestroy()
    }

    private fun stopAlarmAndService() {
        cancelActiveVibration(this)
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
        val vib = resolveVibrator(this)
        activeVibrator = vib
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
            // Keep priority notification with Stop button visible if vibrator rejects waveform.
        }
    }

    companion object {
        const val ACTION_START = "com.seireminds.seireminds.ACTION_START_ALARM"
        const val ACTION_STOP = "com.seireminds.seireminds.ACTION_STOP_ALARM"

        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_SESSION_LABEL = "session_label"

        private const val LEGACY_ACTIVE_CHANNEL_V1 = "seireminds_alarm_active_v1"
        private const val LEGACY_ACTIVE_CHANNEL_V2 = "seireminds_alarm_active_v2"
        private const val LEGACY_FALLBACK_CHANNEL_V1 = "seireminds_alarm_fallback_v1"
        private const val LEGACY_CANVAS_CHANNEL_V1 = "seireminds_canvas_today_v1"

        // v3 active channel enables a 1ms silent pulse + IMPORTANCE_HIGH so Android SystemUI
        // always pops up a priority heads-up notification with the Stop button (zero audio).
        private const val ACTIVE_CHANNEL_ID = "seireminds_alarm_active_v3"
        private const val FALLBACK_CHANNEL_ID = "seireminds_alarm_fallback_v2"
        private const val CANVAS_TODAY_CHANNEL_ID = "seireminds_canvas_today_v2"
        private const val FOREGROUND_NOTIFICATION_ID = 4201
        private const val STOP_BROADCAST_REQUEST_CODE = 4202
        private const val MAX_WAKELOCK_MILLIS = 30 * 60 * 1000L

        private val HEADS_UP_SILENT_PULSE = longArrayOf(0, 1)
        private val HARD_VIBRATION_TIMINGS = longArrayOf(0, 750, 220, 750, 220, 1100, 350)
        private val HARD_VIBRATION_AMPLITUDES = intArrayOf(0, 255, 0, 255, 0, 255, 0)
        private val CANVAS_VIBRATION_TIMINGS = longArrayOf(0, 350, 180, 350)

        @Volatile
        private var activeVibrator: Vibrator? = null

        private fun resolveVibrator(context: Context): Vibrator {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                    .defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
        }

        fun cancelActiveVibration(context: Context) {
            try {
                activeVibrator?.cancel()
            } catch (_: Exception) {
            }
            activeVibrator = null
            try {
                resolveVibrator(context).cancel()
            } catch (_: Exception) {
            }
        }

        /**
         * Immediately stops vibration, stops the foreground service, and dismisses
         * the alarm notification without launching any Activity.
         */
        fun stopImmediately(context: Context, alarmId: Int = -1) {
            cancelActiveVibration(context)
            try {
                context.stopService(Intent(context, AlarmPlaybackService::class.java))
            } catch (_: Exception) {
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(FOREGROUND_NOTIFICATION_ID)
            if (alarmId > 0) {
                nm.cancel(alarmId)
            }
        }

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            nm.deleteNotificationChannel(LEGACY_ACTIVE_CHANNEL_V1)
            nm.deleteNotificationChannel(LEGACY_ACTIVE_CHANNEL_V2)
            nm.deleteNotificationChannel(LEGACY_FALLBACK_CHANNEL_V1)
            nm.deleteNotificationChannel(LEGACY_CANVAS_CHANNEL_V1)

            if (nm.getNotificationChannel(ACTIVE_CHANNEL_ID) == null) {
                val activeChannel = NotificationChannel(
                    ACTIVE_CHANNEL_ID,
                    "SeiReminds Priority Vibration Alarms",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description =
                        "Priority heads-up class alarms (no audio) with a Stop button on the notification."
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setSound(null, null)
                    enableVibration(true)
                    vibrationPattern = HEADS_UP_SILENT_PULSE
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
                    description =
                        "Silent vibration-only notifications for Canvas announcements and activities."
                    setSound(null, null)
                    enableVibration(true)
                    vibrationPattern = CANVAS_VIBRATION_TIMINGS
                }
                nm.createNotificationChannel(canvasChannel)
            }
        }

        private fun buildStopBroadcastIntent(context: Context, alarmId: Int): PendingIntent {
            val stopIntent = Intent(context, AlarmStopReceiver::class.java).apply {
                action = ACTION_STOP
                putExtra(EXTRA_ALARM_ID, alarmId)
            }
            return PendingIntent.getBroadcast(
                context,
                STOP_BROADCAST_REQUEST_CODE,
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun buildStopAction(context: Context, stopPendingIntent: PendingIntent): Notification.Action {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Notification.Action.Builder(
                    Icon.createWithResource(context, android.R.drawable.ic_menu_close_clear_cancel),
                    "Stop",
                    stopPendingIntent,
                ).build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopPendingIntent,
                ).build()
            }
        }

        private fun buildActiveNotification(
            context: Context,
            alarmId: Int,
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

            // Direct broadcast PendingIntent stops vibration without opening the app.
            val stopBroadcastIntent = buildStopBroadcastIntent(context, alarmId)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, ACTIVE_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setSound(null)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
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
                .setOnlyAlertOnce(false)
                .setContentIntent(openAppIntent)
                .addAction(buildStopAction(context, stopBroadcastIntent))

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
            val stopBroadcastIntent = buildStopBroadcastIntent(context, alarmId)

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
                .addAction(buildStopAction(context, stopBroadcastIntent))
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
