package com.seireminds.seireminds

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Stops active alarm vibration and dismisses the priority alarm notification
 * directly from the notification action button without opening the app.
 */
class AlarmStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val alarmId = intent?.getIntExtra(AlarmPlaybackService.EXTRA_ALARM_ID, -1) ?: -1
        AlarmPlaybackService.stopImmediately(context, alarmId)
    }
}
