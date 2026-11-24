package com.seireminds.seireminds

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotifPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmPlaybackService.ensureChannels(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncAlarms" -> {
                        try {
                            val rawList = call.argument<List<Map<String, Any>>>("alarms").orEmpty()
                            val parsed = rawList.map { map ->
                                StoredAlarm(
                                    id = (map["id"] as Number).toInt(),
                                    scheduleId = map["scheduleId"] as? String ?: "",
                                    weekday = (map["weekday"] as Number).toInt(),
                                    hour = (map["hour"] as Number).toInt(),
                                    minute = (map["minute"] as Number).toInt(),
                                    title = map["title"] as? String ?: "SeiReminds Class",
                                    body = map["body"] as? String ?: "",
                                    sessionLabel = map["sessionLabel"] as? String ?: "Class",
                                )
                            }
                            AlarmScheduler.replaceAll(this, parsed)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SYNC_ALARMS_FAILED", e.message, null)
                        }
                    }

                    "triggerTestAlarm" -> {
                        val intent = Intent(this, AlarmPlaybackService::class.java).apply {
                            action = AlarmPlaybackService.ACTION_START
                            putExtra(AlarmPlaybackService.EXTRA_ALARM_ID, 999)
                            putExtra(AlarmPlaybackService.EXTRA_TITLE, "SeiReminds Class Reminder · Sec A")
                            putExtra(
                                AlarmPlaybackService.EXTRA_BODY,
                                "Your lecture class is starting in 10 minutes. Tap Stop on this notification to stop vibrating without opening the app.",
                            )
                            putExtra(AlarmPlaybackService.EXTRA_SESSION_LABEL, "Test")
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                        } catch (_: Exception) {
                            AlarmPlaybackService.postFallbackAlarmNotification(
                                context = this,
                                alarmId = 999,
                                title = "SeiReminds Class Reminder · Sec A",
                                body = "Your lecture class is starting in 10 minutes. Tap Stop to dismiss.",
                            )
                        }
                        result.success(null)
                    }

                    "showCanvasNotification" -> {
                        val id = (call.argument<Number>("id") ?: 5000).toInt()
                        val title = call.argument<String>("title") ?: "Canvas Update"
                        val body = call.argument<String>("body") ?: ""
                        AlarmPlaybackService.postTodayCanvasNotification(
                            context = this,
                            notificationId = id,
                            title = title,
                            body = body,
                        )
                        result.success(null)
                    }

                    "stopActiveAlarm" -> {
                        AlarmPlaybackService.stopImmediately(this, 999)
                        result.success(null)
                    }

                    "getPermissionStatus" -> {
                        result.success(collectPermissionStatus())
                    }

                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            result.success(nm.areNotificationsEnabled())
                        } else if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else {
                            pendingNotifPermissionResult?.success(false)
                            pendingNotifPermissionResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_POST_NOTIFICATIONS,
                            )
                        }
                    }

                    "openExactAlarmSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            launchSettingsWithFallback(
                                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                    data = Uri.parse("package:$packageName")
                                },
                            )
                        }
                        result.success(null)
                    }

                    "openFullScreenIntentSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            launchSettingsWithFallback(
                                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                    data = Uri.parse("package:$packageName")
                                },
                            )
                        } else {
                            openAlarmChannelSettings()
                        }
                        result.success(null)
                    }

                    "openAlarmChannelSettings" -> {
                        openAlarmChannelSettings()
                        result.success(null)
                    }

                    "openDndSettings" -> {
                        launchSettingsWithFallback(
                            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS),
                        )
                        result.success(null)
                    }

                    "openBatteryOptimizationSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                },
                            )
                        } catch (_: Exception) {
                            launchSettingsWithFallback(
                                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                            )
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotifPermissionResult?.success(granted)
            pendingNotifPermissionResult = null
        }
    }

    private fun openAlarmChannelSettings() {
        AlarmPlaybackService.ensureChannels(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                startActivity(
                    Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        putExtra(Settings.EXTRA_CHANNEL_ID, AlarmPlaybackService.ACTIVE_CHANNEL_ID)
                    },
                )
                return
            } catch (_: Exception) {
            }
            launchSettingsWithFallback(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                },
            )
            return
        }
        launchSettingsWithFallback(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            },
        )
    }

    private fun launchSettingsWithFallback(intent: Intent) {
        try {
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    },
                )
            } catch (_: Exception) {
            }
        }
    }

    private fun collectPermissionStatus(): Map<String, Boolean> {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager

        val notificationsGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED && nm.areNotificationsEnabled()
        } else {
            nm.areNotificationsEnabled()
        }

        val exactAlarmsAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.canScheduleExactAlarms()
        } else {
            true
        }

        val fullScreenIntentAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            nm.canUseFullScreenIntent()
        } else {
            true
        }

        return mapOf(
            "notificationsGranted" to notificationsGranted,
            "exactAlarmsAllowed" to exactAlarmsAllowed,
            "fullScreenIntentAllowed" to fullScreenIntentAllowed,
            "dndAccessGranted" to nm.isNotificationPolicyAccessGranted,
            "ignoringBatteryOptimizations" to pm.isIgnoringBatteryOptimizations(packageName),
        )
    }

    companion object {
        private const val CHANNEL_NAME = "com.seireminds/alarms"
        private const val REQ_POST_NOTIFICATIONS = 1001
    }
}
