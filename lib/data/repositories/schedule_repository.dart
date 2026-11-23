import '../../domain/models/schedule_models.dart';
import '../services/alarm_service.dart';
import '../services/local_schedule_storage.dart';

class ScheduleSyncResult {
  const ScheduleSyncResult({
    required this.schedules,
    this.alarmSyncWarning,
  });

  final List<SubjectSchedule> schedules;
  final String? alarmSyncWarning;
}

/// Single source of truth for offline schedules and native alarm syncing.
// shortcut: offline local storage only; add remote sync adapter here when online backend is chosen.
class ScheduleRepository {
  ScheduleRepository({
    required this._storage,
    required this._alarmService,
  });

  final ScheduleStorage _storage;
  final AlarmService _alarmService;

  Future<ScheduleSyncResult> loadAndSync() async {
    final schedules = await _storage.readAll();
    final warning = await _syncAlarmsSafely(schedules);
    return ScheduleSyncResult(
      schedules: schedules,
      alarmSyncWarning: warning,
    );
  }

  Future<ScheduleSyncResult> saveSchedule(
    List<SubjectSchedule> current,
    SubjectSchedule schedule,
  ) async {
    final next = List<SubjectSchedule>.of(current);
    final existingIndex = next.indexWhere((s) => s.id == schedule.id);
    if (existingIndex >= 0) {
      next[existingIndex] = schedule;
    } else {
      next.add(schedule);
    }
    await _storage.writeAll(next);
    final warning = await _syncAlarmsSafely(next);
    return ScheduleSyncResult(
      schedules: List<SubjectSchedule>.unmodifiable(next),
      alarmSyncWarning: warning,
    );
  }

  Future<ScheduleSyncResult> deleteSchedule(
    List<SubjectSchedule> current,
    String id,
  ) async {
    final next = current.where((s) => s.id != id).toList();
    await _storage.writeAll(next);
    final warning = await _syncAlarmsSafely(next);
    return ScheduleSyncResult(
      schedules: List<SubjectSchedule>.unmodifiable(next),
      alarmSyncWarning: warning,
    );
  }

  Future<ScheduleSyncResult> toggleReminder(
    List<SubjectSchedule> current,
    String id,
    bool enabled,
  ) async {
    final next = current
        .map((s) => s.id == id ? s.copyWith(reminderEnabled: enabled) : s)
        .toList();
    await _storage.writeAll(next);
    final warning = await _syncAlarmsSafely(next);
    return ScheduleSyncResult(
      schedules: List<SubjectSchedule>.unmodifiable(next),
      alarmSyncWarning: warning,
    );
  }

  Future<String?> resyncAlarms(List<SubjectSchedule> current) {
    return _syncAlarmsSafely(current);
  }

  Future<AlarmPermissionStatus> getPermissionStatus() =>
      _alarmService.getPermissionStatus();

  Future<bool> requestNotificationPermission() =>
      _alarmService.requestNotificationPermission();

  Future<void> openExactAlarmSettings() =>
      _alarmService.openExactAlarmSettings();

  Future<void> openDndSettings() => _alarmService.openDndSettings();

  Future<void> openBatteryOptimizationSettings() =>
      _alarmService.openBatteryOptimizationSettings();

  Future<void> triggerTestAlarm() => _alarmService.triggerTestAlarm();

  Future<void> stopActiveAlarm() => _alarmService.stopActiveAlarm();

  Future<String?> _syncAlarmsSafely(List<SubjectSchedule> schedules) async {
    try {
      await _alarmService.syncAlarms(buildAlarmPayloads(schedules));
      return null;
    } catch (e) {
      return 'Schedule saved offline, but alarm sync failed: $e';
    }
  }
}
