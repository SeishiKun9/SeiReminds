package com.seireminds.seireminds

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "seireminds:alarm_receiver_wakelock",
        )
        wakeLock.acquire(10_000L)

        try {
            val alarmId = intent.getIntExtra(AlarmPlaybackService.EXTRA_ALARM_ID, -1)
            val title = intent.getStringExtra(AlarmPlaybackService.EXTRA_TITLE) ?: "SeiReminds Class"
            val body = intent.getStringExtra(AlarmPlaybackService.EXTRA_BODY) ?: "Your class is starting soon."
            val sessionLabel = intent.getStringExtra(AlarmPlaybackService.EXTRA_SESSION_LABEL) ?: "Class"

            // Immediately queue next week's occurrence so reminders keep repeating while unused.
            if (alarmId > 0) {
                AlarmScheduler.findById(context, alarmId)?.let { stored ->
                    AlarmScheduler.scheduleOne(context, stored)
                }
            }

            val serviceIntent = Intent(context, AlarmPlaybackService::class.java).apply {
                action = AlarmPlaybackService.ACTION_START
                putExtra(AlarmPlaybackService.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmPlaybackService.EXTRA_TITLE, title)
                putExtra(AlarmPlaybackService.EXTRA_BODY, body)
                putExtra(AlarmPlaybackService.EXTRA_SESSION_LABEL, sessionLabel)
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (_: Exception) {
                AlarmPlaybackService.postFallbackAlarmNotification(
                    context = context,
                    alarmId = if (alarmId > 0) alarmId else 999,
                    title = title,
                    body = body,
                )
            }
        } finally {
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
        }
    }
}
