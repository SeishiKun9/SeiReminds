package com.seireminds.seireminds

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground service that drives silent, vibration-only alarms (NO audible sound)
 * paired with a dedicated non-foreground-service priority heads-up notification
 * so the Stop banner pops up over the homescreen and other apps on Android 10-16.
 */
class AlarmPlaybackService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopAlarmAndService()
            return START_NOT_STICKY
        }

        val alarmId = intent?.getIntExtra(EXTRA_ALARM_ID, HEADS_UP_NOTIFICATION_ID)
            ?: HEADS_UP_NOTIFICATION_ID
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "SeiReminds Class"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: "Your class is starting soon."

        ensureChannels(this)
        isAlarmActive.set(true)
        cancelPendingVibrationStart()

        // 1. Keep the foreground service alive on a low-key service channel so OEMs
        //    do not suppress heads-up banners due to FLAG_FOREGROUND_SERVICE.
        val serviceNotification = buildForegroundServiceNotification(this, alarmId, title, body)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                FOREGROUND_NOTIFICATION_ID,
                serviceNotification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, serviceNotification)
        }

        // 2. Post a fresh non-FGS IMPORTANCE_HIGH alarm notification that pops up
        //    over the homescreen and other apps with a direct Stop button.
        postHeadsUpAlarmNotification(this, alarmId, title, body)

        acquireWakeLock()

        // 3. Hand off to continuous USAGE_ALARM vibration after SystemUI processes the
        //    heads-up channel buzz so our vibrator loop never races the banner display.
        val appCtx = applicationContext
        val runnable = Runnable {
            if (isAlarmActive.get()) {
                startContinuousVibration(appCtx)
            }
        }
        pendingVibrationRunnable = runnable
        mainHandler.postDelayed(runnable, VIBRATION_HANDOFF_DELAY_MS)

        // Keep running and vibrating continuously until the user taps Stop or dismisses.
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        isAlarmActive.set(false)
        cancelPendingVibrationStart()
        cancelActiveVibration(this)
        cancelHeadsUpNotification(this)
        releaseWakeLock()
        super.onDestroy()
    }

    private fun stopAlarmAndService() {
        isAlarmActive.set(false)
        cancelPendingVibrationStart()
        cancelActiveVibration(this)
        cancelHeadsUpNotification(this)
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

    companion object {
        const val ACTION_START = "com.seireminds.seireminds.ACTION_START_ALARM"
        const val ACTION_STOP = "com.seireminds.seireminds.ACTION_STOP_ALARM"

        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_SESSION_LABEL = "session_label"

        private const val LEGACY_ACTIVE_CHANNEL_V1 = "seireminds_alarm_active_v1"
        private const val LEGACY_ACTIVE_CHANNEL_V2 = "seireminds_alarm_active_v2"
        private const val LEGACY_ACTIVE_CHANNEL_V3 = "seireminds_alarm_active_v3"
        private const val LEGACY_FALLBACK_CHANNEL_V1 = "seireminds_alarm_fallback_v1"
        private const val LEGACY_FALLBACK_CHANNEL_V2 = "seireminds_alarm_fallback_v2"
        private const val LEGACY_CANVAS_CHANNEL_V1 = "seireminds_canvas_today_v1"
        private const val LEGACY_CANVAS_CHANNEL_V2 = "seireminds_canvas_today_v2"
        private const val LEGACY_CANVAS_CHANNEL_V3 = "seireminds_canvas_today_v3"

        // Low-key service channel keeps FGS alive without fighting heads-up banners.
        private const val SERVICE_CHANNEL_ID = "seireminds_alarm_service_v1"

        // v4 active alarm channel pairs IMPORTANCE_HIGH + pure-zero silent WAV (USAGE_ALARM)
        // + real vibration pulse so AOSP & OEMs (OneUI/MIUI/ColorOS) always pop a floating banner.
        const val ACTIVE_CHANNEL_ID = "seireminds_alarm_active_v4"
        private const val FALLBACK_CHANNEL_ID = "seireminds_alarm_fallback_v3"
        // v4 Canvas notification pop-up channel bypasses DND & silent mode while remaining
        // a normal dismissible notification (never a repeating class alarm).
        const val CANVAS_TODAY_CHANNEL_ID = "seireminds_canvas_today_v4"

        private const val FOREGROUND_NOTIFICATION_ID = 4201
        private const val STOP_BROADCAST_REQUEST_CODE = 4202
        private const val HEADS_UP_NOTIFICATION_ID = 4203
        private const val MAX_WAKELOCK_MILLIS = 30 * 60 * 1000L
        private const val VIBRATION_HANDOFF_DELAY_MS = 400L

        private val HEADS_UP_VIBRATION_PULSE = longArrayOf(0, 280, 140, 280)
        private val HARD_VIBRATION_TIMINGS = longArrayOf(0, 750, 220, 750, 220, 1100, 350)
        private val HARD_VIBRATION_AMPLITUDES = intArrayOf(0, 255, 0, 255, 0, 255, 0)
        private val CANVAS_VIBRATION_TIMINGS = longArrayOf(0, 350, 180, 350)

        private val mainHandler = Handler(Looper.getMainLooper())
        private val isAlarmActive = AtomicBoolean(false)

        @Volatile
        private var pendingVibrationRunnable: Runnable? = null

        @Volatile
        private var activeVibrator: Vibrator? = null

        private fun silentSoundUri(context: Context): Uri {
            return Uri.parse(
                "${ContentResolver.SCHEME_ANDROID_RESOURCE}://${context.packageName}/raw/seireminds_silent",
            )
        }

        private fun alarmAudioAttributes(): AudioAttributes {
            return AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        }

        private fun isScreenUnlocked(context: Context): Boolean {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            return pm.isInteractive && !km.isKeyguardLocked
        }

        private fun resolveVibrator(context: Context): Vibrator {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                    .defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
        }

        private fun startContinuousVibration(context: Context) {
            val vib = resolveVibrator(context)
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
                    @Suppress("DEPRECATION")
                    vib.vibrate(effect, alarmAudioAttributes())
                } else {
                    @Suppress("DEPRECATION")
                    vib.vibrate(HARD_VIBRATION_TIMINGS, 0)
                }
            } catch (_: Exception) {
                // Keep priority notification with Stop button visible if vibrator rejects waveform.
            }
        }

        private fun vibrateCanvasNotificationOnce(context: Context) {
            // Never interrupt an active class schedule alarm with a notification buzz.
            if (isAlarmActive.get()) return
            val vib = resolveVibrator(context)
            if (!vib.hasVibrator()) return

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val effect = VibrationEffect.createWaveform(CANVAS_VIBRATION_TIMINGS, -1)
                    // Single non-repeating pulse (repeat = -1) using USAGE_ALARM so it still
                    // delivers tactile feedback in Silent Mode and DND without becoming an alarm.
                    val attrs = VibrationAttributes.Builder()
                        .setUsage(VibrationAttributes.USAGE_ALARM)
                        .build()
                    vib.vibrate(effect, attrs)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(CANVAS_VIBRATION_TIMINGS, -1)
                    @Suppress("DEPRECATION")
                    vib.vibrate(effect, alarmAudioAttributes())
                } else {
                    @Suppress("DEPRECATION")
                    vib.vibrate(CANVAS_VIBRATION_TIMINGS, -1)
                }
            } catch (_: Exception) {
                // Keep the DND-bypassing notification pop-up visible even if vibrator rejects.
            }
        }

        private fun cancelPendingVibrationStart() {
            pendingVibrationRunnable?.let { mainHandler.removeCallbacks(it) }
            pendingVibrationRunnable = null
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

        private fun cancelHeadsUpNotification(context: Context) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(HEADS_UP_NOTIFICATION_ID)
        }

        /**
         * Immediately stops vibration, stops the foreground service, and dismisses
         * both the heads-up alarm banner and service notification without opening the app.
         */
        fun stopImmediately(context: Context, alarmId: Int = -1) {
            isAlarmActive.set(false)
            cancelPendingVibrationStart()
            cancelActiveVibration(context)
            try {
                context.stopService(Intent(context, AlarmPlaybackService::class.java))
            } catch (_: Exception) {
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(HEADS_UP_NOTIFICATION_ID)
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
            nm.deleteNotificationChannel(LEGACY_ACTIVE_CHANNEL_V3)
            nm.deleteNotificationChannel(LEGACY_FALLBACK_CHANNEL_V1)
            nm.deleteNotificationChannel(LEGACY_FALLBACK_CHANNEL_V2)
            nm.deleteNotificationChannel(LEGACY_CANVAS_CHANNEL_V1)
            nm.deleteNotificationChannel(LEGACY_CANVAS_CHANNEL_V2)
            nm.deleteNotificationChannel(LEGACY_CANVAS_CHANNEL_V3)

            if (nm.getNotificationChannel(SERVICE_CHANNEL_ID) == null) {
                val serviceChannel = NotificationChannel(
                    SERVICE_CHANNEL_ID,
                    "SeiReminds Alarm Vibration Service",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Keeps active vibration running until you tap Stop."
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_SECRET
                }
                nm.createNotificationChannel(serviceChannel)
            }

            if (nm.getNotificationChannel(ACTIVE_CHANNEL_ID) == null) {
                val activeChannel = NotificationChannel(
                    ACTIVE_CHANNEL_ID,
                    "SeiReminds Class Alarm Pop-ups",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description =
                        "Priority heads-up class alarms (silent audio track, vibrate only) with a Stop button over any app or homescreen."
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    // Pure-silence WAV prevents OEMs from disabling floating banners for sound=null channels.
                    setSound(silentSoundUri(context), alarmAudioAttributes())
                    enableVibration(true)
                    vibrationPattern = HEADS_UP_VIBRATION_PULSE
                    enableLights(true)
                }
                nm.createNotificationChannel(activeChannel)
            }

            if (nm.getNotificationChannel(FALLBACK_CHANNEL_ID) == null) {
                val fallbackChannel = NotificationChannel(
                    FALLBACK_CHANNEL_ID,
                    "SeiReminds Fallback Alarm Pop-ups",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Silent vibration-only fallback heads-up notifications."
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setSound(silentSoundUri(context), alarmAudioAttributes())
                    enableVibration(true)
                    vibrationPattern = HARD_VIBRATION_TIMINGS
                    enableLights(true)
                }
                nm.createNotificationChannel(fallbackChannel)
            }

            if (nm.getNotificationChannel(CANVAS_TODAY_CHANNEL_ID) == null) {
                val canvasChannel = NotificationChannel(
                    CANVAS_TODAY_CHANNEL_ID,
                    "SeiReminds Canvas Notification Pop-ups",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description =
                        "Heads-up Canvas announcements and activity pop-ups (bypasses DND & silent mode; never triggers a class alarm)."
                    setBypassDnd(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    // Pure-silence WAV + USAGE_ALARM lets the pop-up bypass Silent/DND without ringtone audio.
                    setSound(silentSoundUri(context), alarmAudioAttributes())
                    enableVibration(true)
                    vibrationPattern = CANVAS_VIBRATION_TIMINGS
                    enableLights(true)
                }
                nm.createNotificationChannel(canvasChannel)
            }
        }

        private fun buildOpenAppIntent(context: Context, requestCode: Int): PendingIntent {
            return PendingIntent.getActivity(
                context,
                requestCode,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
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

        private fun buildForegroundServiceNotification(
            context: Context,
            alarmId: Int,
            title: String,
            body: String,
        ): Notification {
            val openAppIntent = buildOpenAppIntent(context, FOREGROUND_NOTIFICATION_ID)
            val stopBroadcastIntent = buildStopBroadcastIntent(context, alarmId)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, SERVICE_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
                    .setSound(null)
                    .setPriority(Notification.PRIORITY_LOW)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }

            return builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setVisibility(Notification.VISIBILITY_SECRET)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(openAppIntent)
                .addAction(buildStopAction(context, stopBroadcastIntent))
                .build()
        }

        private fun postHeadsUpAlarmNotification(
            context: Context,
            alarmId: Int,
            title: String,
            body: String,
        ) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Cancel any previous banner so SystemUI always pops this up as a fresh heads-up alert.
            nm.cancel(HEADS_UP_NOTIFICATION_ID)

            val openAppIntent = buildOpenAppIntent(context, HEADS_UP_NOTIFICATION_ID)
            val stopBroadcastIntent = buildStopBroadcastIntent(context, alarmId)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, ACTIVE_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
                    .setPriority(Notification.PRIORITY_MAX)
                    .setSound(silentSoundUri(context))
                    .setVibrate(HEADS_UP_VIBRATION_PULSE)
            }

            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(false)
                .setAutoCancel(false)
                .setOnlyAlertOnce(false)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)
                .setContentIntent(openAppIntent)
                // Swiping the banner away also stops vibration cleanly.
                .setDeleteIntent(stopBroadcastIntent)
                .addAction(buildStopAction(context, stopBroadcastIntent))

            // While unlocked (homescreen or another app), Android turns setFullScreenIntent(..., true)
            // into a pinned priority alarm heads-up banner without launching MainActivity.
            // When locked, omit it so the notification sits cleanly on the lock screen with Stop.
            if (isScreenUnlocked(context)) {
                builder.setFullScreenIntent(openAppIntent, true)
            }

            nm.notify(HEADS_UP_NOTIFICATION_ID, builder.build())
        }

        fun postFallbackAlarmNotification(
            context: Context,
            alarmId: Int,
            title: String,
            body: String,
        ) {
            ensureChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val openAppIntent = buildOpenAppIntent(context, alarmId)
            val stopBroadcastIntent = buildStopBroadcastIntent(context, alarmId)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, FALLBACK_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
                    .setPriority(Notification.PRIORITY_MAX)
                    .setSound(silentSoundUri(context))
                    .setVibrate(HARD_VIBRATION_TIMINGS)
            }

            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setAutoCancel(false)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)
                .setContentIntent(openAppIntent)
                .setDeleteIntent(stopBroadcastIntent)
                .addAction(buildStopAction(context, stopBroadcastIntent))

            if (isScreenUnlocked(context)) {
                builder.setFullScreenIntent(openAppIntent, true)
            }

            nm.notify(alarmId, builder.build())
        }

        fun postTodayCanvasNotification(
            context: Context,
            notificationId: Int,
            title: String,
            body: String,
        ) {
            ensureChannels(context)
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val openAppIntent = buildOpenAppIntent(context, notificationId)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CANVAS_TODAY_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
                    .setPriority(Notification.PRIORITY_HIGH)
                    .setSound(silentSoundUri(context))
                    .setVibrate(CANVAS_VIBRATION_TIMINGS)
            }

            val notification = builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                // Explicitly CATEGORY_REMINDER (never CATEGORY_ALARM) so Canvas stays a pop-up notification.
                .setCategory(Notification.CATEGORY_REMINDER)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(false)
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)
                .setContentIntent(openAppIntent)
                .build()

            nm.notify(notificationId, notification)
            vibrateCanvasNotificationOnce(context)
        }
    }
}
