import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/schedule_models.dart';

class AlarmPermissionStatus {
  const AlarmPermissionStatus({
    required this.isAndroidSupported,
    required this.notificationsGranted,
    required this.exactAlarmsAllowed,
    required this.dndAccessGranted,
    required this.ignoringBatteryOptimizations,
  });

  const AlarmPermissionStatus.unsupported()
      : isAndroidSupported = false,
        notificationsGranted = false,
        exactAlarmsAllowed = false,
        dndAccessGranted = false,
        ignoringBatteryOptimizations = false;

  final bool isAndroidSupported;
  final bool notificationsGranted;
  final bool exactAlarmsAllowed;
  final bool dndAccessGranted;
  final bool ignoringBatteryOptimizations;

  bool get needsAttention =>
      isAndroidSupported &&
      (!notificationsGranted ||
          !exactAlarmsAllowed ||
          !ignoringBatteryOptimizations);
}

abstract class AlarmService {
  Future<void> syncAlarms(List<ScheduledAlarmPayload> alarms);
  Future<void> showCanvasNotification({
    required int id,
    required String title,
    required String body,
  });
  Future<void> triggerTestAlarm();
  Future<void> stopActiveAlarm();
  Future<AlarmPermissionStatus> getPermissionStatus();
  Future<bool> requestNotificationPermission();
  Future<void> openExactAlarmSettings();
  Future<void> openDndSettings();
  Future<void> openBatteryOptimizationSettings();
}

class MethodChannelAlarmService implements AlarmService {
  MethodChannelAlarmService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.seireminds/alarms');

  final MethodChannel _channel;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> syncAlarms(List<ScheduledAlarmPayload> alarms) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>(
        'syncAlarms',
        <String, Object>{
          'alarms': alarms.map((a) => a.toMap()).toList(),
        },
      );
    } on MissingPluginException {
      // Non-Android / widget test environment without native channel registered.
    }
  }

  @override
  Future<void> showCanvasNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>(
        'showCanvasNotification',
        <String, Object>{
          'id': id,
          'title': title,
          'body': body,
        },
      );
    } on MissingPluginException {
      // Non-Android / widget test environment without native channel registered.
    }
  }

  @override
  Future<void> triggerTestAlarm() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('triggerTestAlarm');
  }

  @override
  Future<void> stopActiveAlarm() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopActiveAlarm');
    } on MissingPluginException {
      // Ignore outside Android runtime.
    }
  }

  @override
  Future<AlarmPermissionStatus> getPermissionStatus() async {
    if (!_isAndroid) return const AlarmPermissionStatus.unsupported();
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getPermissionStatus',
      );
      if (result == null) return const AlarmPermissionStatus.unsupported();
      return AlarmPermissionStatus(
        isAndroidSupported: true,
        notificationsGranted: result['notificationsGranted'] == true,
        exactAlarmsAllowed: result['exactAlarmsAllowed'] == true,
        dndAccessGranted: result['dndAccessGranted'] == true,
        ignoringBatteryOptimizations:
            result['ignoringBatteryOptimizations'] == true,
      );
    } on MissingPluginException {
      return const AlarmPermissionStatus.unsupported();
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    if (!_isAndroid) return false;
    final granted = await _channel.invokeMethod<bool>(
      'requestNotificationPermission',
    );
    return granted ?? false;
  }

  @override
  Future<void> openExactAlarmSettings() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('openExactAlarmSettings');
  }

  @override
  Future<void> openDndSettings() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('openDndSettings');
  }

  @override
  Future<void> openBatteryOptimizationSettings() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }
}
