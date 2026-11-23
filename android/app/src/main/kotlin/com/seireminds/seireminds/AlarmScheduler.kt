package com.seireminds.seireminds

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

data class StoredAlarm(
    val id: Int,
    val scheduleId: String,
    val weekday: Int,
    val hour: Int,
    val minute: Int,
    val title: String,
    val body: String,
    val sessionLabel: String,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("scheduleId", scheduleId)
        put("weekday", weekday)
        put("hour", hour)
        put("minute", minute)
        put("title", title)
        put("body", body)
        put("sessionLabel", sessionLabel)
    }

    companion object {
        fun fromJson(obj: JSONObject): StoredAlarm = StoredAlarm(
            id = obj.getInt("id"),
            scheduleId = obj.optString("scheduleId", ""),
            weekday = obj.getInt("weekday"),
            hour = obj.getInt("hour"),
            minute = obj.getInt("minute"),
            title = obj.getString("title"),
            body = obj.getString("body"),
            sessionLabel = obj.optString("sessionLabel", "Class"),
        )
    }
}

object AlarmScheduler {
    private const val PREFS_NAME = "seireminds_alarms_prefs"
    private const val KEY_ALARMS = "stored_alarms_json"

    fun replaceAll(context: Context, alarms: List<StoredAlarm>) {
        val existing = loadAll(context)
        existing.forEach { cancelOne(context, it.id) }
        saveAll(context, alarms)
        alarms.forEach { scheduleOne(context, it) }
    }

    fun rescheduleAll(context: Context) {
        loadAll(context).forEach { scheduleOne(context, it) }
    }

    fun findById(context: Context, id: Int): StoredAlarm? {
        return loadAll(context).firstOrNull { it.id == id }
    }

    fun loadAll(context: Context): List<StoredAlarm> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_ALARMS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    add(StoredAlarm.fromJson(array.getJSONObject(i)))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveAll(context: Context, alarms: List<StoredAlarm>) {
        val array = JSONArray()
        alarms.forEach { array.put(it.toJson()) }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ALARMS, array.toString())
            .apply()
    }

    fun scheduleOne(context: Context, alarm: StoredAlarm, nowMillis: Long = System.currentTimeMillis()) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAtMillis = computeNextTriggerMillis(
            isoWeekday = alarm.weekday,
            hour = alarm.hour,
            minute = alarm.minute,
            nowMillis = nowMillis,
        )
        val fireIntent = buildReceiverIntent(context, alarm)
        val showIntent = PendingIntent.getActivity(
            context,
            alarm.id,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val canUseExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()

        if (canUseExact) {
            // setAlarmClock wakes out of Doze even if the app has not been opened for days.
            val info = AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent)
            alarmManager.setAlarmClock(info, fireIntent)
        } else {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                fireIntent,
            )
        }
    }

    fun cancelOne(context: Context, alarmId: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pending != null) {
            alarmManager.cancel(pending)
            pending.cancel()
        }
    }

    private fun buildReceiverIntent(context: Context, alarm: StoredAlarm): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(AlarmPlaybackService.EXTRA_ALARM_ID, alarm.id)
            putExtra(AlarmPlaybackService.EXTRA_TITLE, alarm.title)
            putExtra(AlarmPlaybackService.EXTRA_BODY, alarm.body)
            putExtra(AlarmPlaybackService.EXTRA_SESSION_LABEL, alarm.sessionLabel)
        }
        return PendingIntent.getBroadcast(
            context,
            alarm.id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun computeNextTriggerMillis(
        isoWeekday: Int,
        hour: Int,
        minute: Int,
        nowMillis: Long,
    ): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val targetDay = isoWeekdayToCalendarDay(isoWeekday)
        val daysAhead = (targetDay - cal.get(Calendar.DAY_OF_WEEK) + 7) % 7
        cal.add(Calendar.DAY_OF_YEAR, daysAhead)
        // 1.5s guard prevents double-firing when rescheduling immediately on trigger.
        if (cal.timeInMillis <= nowMillis + 1500L) {
            cal.add(Calendar.DAY_OF_YEAR, 7)
        }
        return cal.timeInMillis
    }

    private fun isoWeekdayToCalendarDay(isoWeekday: Int): Int = when (isoWeekday) {
        1 -> Calendar.MONDAY
        2 -> Calendar.TUESDAY
        3 -> Calendar.WEDNESDAY
        4 -> Calendar.THURSDAY
        5 -> Calendar.FRIDAY
        6 -> Calendar.SATURDAY
        7 -> Calendar.SUNDAY
        else -> Calendar.MONDAY
    }
}
