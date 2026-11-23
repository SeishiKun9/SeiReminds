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
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

class AlarmPlaybackService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStopRunnable = Runnable { stopSelf() }

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
        startAlarmAudio()
        startHardVibration()

        handler.removeCallbacks(autoStopRunnable)
        handler.postDelayed(autoStopRunnable, AUTO_STOP_MILLIS)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStopRunnable)
        stopAudioAndVibration()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun stopAlarmAndService() {
        handler.removeCallbacks(autoStopRunnable)
        stopAudioAndVibration()
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "seireminds:alarm_playback_wakelock",
        ).apply {
            acquire(AUTO_STOP_MILLIS + 5_000L)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun startAlarmAudio() {
        stopAudioOnly()
        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return

        try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(this@AlarmPlaybackService, alarmUri)
                // USAGE_ALARM routes through the Alarm stream, bypassing phone Silent/Vibrate mode.
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Exception) {
            stopAudioOnly()
        }
    }

    private fun startHardVibration() {
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
                // USAGE_ALARM lets vibration fire hard even while phone is in Silent mode.
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
            // Keep alarm audio and notification running if hardware vibrator rejects waveform.
        }
    }

    private fun stopAudioOnly() {
        mediaPlayer?.let { player ->
            try {
                if (player.isPlaying) player.stop()
            } catch (_: Exception) {
            }
            try {
                player.release()
            } catch (_: Exception) {
            }
        }
        mediaPlayer = null
    }

    private fun stopAudioAndVibration() {
        stopAudioOnly()
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

        private const val ACTIVE_CHANNEL_ID = "seireminds_alarm_active_v1"
        private const val FALLBACK_CHANNEL_ID = "seireminds_alarm_fallback_v1"
        private const val CANVAS_TODAY_CHANNEL_ID = "seireminds_canvas_today_v1"
        private const val FOREGROUND_NOTIFICATION_ID = 4201
        private const val AUTO_STOP_MILLIS = 60_000L

        private val HARD_VIBRATION_TIMINGS = longArrayOf(0, 750, 220, 750, 220, 1100, 350)
        private val HARD_VIBRATION_AMPLITUDES = intArrayOf(0, 255, 0, 255, 0, 255, 0)

        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (nm.getNotificationChannel(ACTIVE_CHANNEL_ID) == null) {
                val activeChannel = NotificationChannel(
                    ACTIVE_CHANNEL_ID,
                    "SeiReminds Active Alarms",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "High-priority class alarms that bypass silent mode and vibrate hard."
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    // Audio and max-amplitude vibration are driven directly by AlarmPlaybackService.
                    setSound(null, null)
                    enableVibration(false)
                }
                nm.createNotificationChannel(activeChannel)
            }

            if (nm.getNotificationChannel(FALLBACK_CHANNEL_ID) == null) {
                val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                val fallbackChannel = NotificationChannel(
                    FALLBACK_CHANNEL_ID,
                    "SeiReminds Fallback Alarms",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Fallback alarm notifications if background service is restricted."
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    enableVibration(true)
                    vibrationPattern = HARD_VIBRATION_TIMINGS
                    setSound(
                        alarmUri,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                }
                nm.createNotificationChannel(fallbackChannel)
            }

            if (nm.getNotificationChannel(CANVAS_TODAY_CHANNEL_ID) == null) {
                val canvasChannel = NotificationChannel(
                    CANVAS_TODAY_CHANNEL_ID,
                    "SeiReminds Canvas Updates",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Notifications for Canvas announcements and activities posted today."
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
                Notification.Builder(context)
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
                .setDeleteIntent(stopIntent)
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
