import '../../domain/models/schedule_models.dart';
import '../services/alarm_service.dart';
import '../services/sqlite_database_service.dart';

class ScheduleDataSnapshot {
  const ScheduleDataSnapshot({
    required this.schedules,
    required this.events,
    required this.activeHistory,
    required this.archivedHistory,
    this.alarmSyncWarning,
  });

  final List<SubjectSchedule> schedules;
  final List<EventSchedule> events;
  final List<HistoryEntry> activeHistory;
  final List<HistoryEntry> archivedHistory;
  final String? alarmSyncWarning;
}

/// Single source of truth backed by local SQLite and native Android alarms.
// shortcut: offline SQLite only; add remote sync adapter here when online backend is chosen.
class ScheduleRepository {
  ScheduleRepository({
    required this._database,
    required this._alarmService,
  });

  final SqliteScheduleDatabase _database;
  final AlarmService _alarmService;

  Future<ScheduleDataSnapshot> loadAllAndSync() async {
    final schedules = await _database.loadSchedules();
    final events = await _database.loadEvents();
    final activeHistory = await _database.loadHistory(archivedOnly: false);
    final archivedHistory = await _database.loadHistory(archivedOnly: true);
    final warning = await _syncAlarmsSafely(schedules, events);
    return ScheduleDataSnapshot(
      schedules: List<SubjectSchedule>.unmodifiable(schedules),
      events: List<EventSchedule>.unmodifiable(events),
      activeHistory: List<HistoryEntry>.unmodifiable(activeHistory),
      archivedHistory: List<HistoryEntry>.unmodifiable(archivedHistory),
      alarmSyncWarning: warning,
    );
  }

  Future<ScheduleDataSnapshot> saveSchedule(
    SubjectSchedule schedule, {
    required bool isNew,
  }) async {
    await _database.upsertSchedule(schedule, isNew: isNew);
    return loadAllAndSync();
  }

  Future<ScheduleDataSnapshot> deleteSchedule(
    String id, {
    required bool confirmedFromSchedule,
  }) async {
    await _database.deleteSchedule(
      id,
      confirmedFromSchedule: confirmedFromSchedule,
    );
    return loadAllAndSync();
  }

  Future<ScheduleDataSnapshot> toggleScheduleReminder(
    String id,
    bool enabled,
  ) async {
    await _database.toggleScheduleReminder(id, enabled);
    return loadAllAndSync();
  }

  Future<ScheduleDataSnapshot> saveEvent(
    EventSchedule event, {
    required bool isNew,
  }) async {
    final schedules = await _database.loadSchedules();
    final affected = affectedSessionsForEvent(event, schedules);
    await _database.upsertEvent(
      event,
      isNew: isNew,
      affectedSessions: affected,
    );
    return loadAllAndSync();
  }

  Future<ScheduleDataSnapshot> deleteEvent(String id) async {
    await _database.deleteEvent(id);
    return loadAllAndSync();
  }

  Future<ScheduleDataSnapshot> toggleEventReminder(
    String id,
    bool enabled,
  ) async {
    await _database.toggleEventReminder(id, enabled);
    return loadAllAndSync();
  }

  Future<ScheduleDataSnapshot> clearHistory() async {
    await _database.clearHistory();
    return loadAllAndSync();
  }

  Future<ScheduleDataSnapshot> restoreArchivedHistory() async {
    await _database.restoreArchivedHistory();
    return loadAllAndSync();
  }

  Future<ScheduleDataSnapshot> permanentlyClearHistory({
    required bool confirmedPermanent,
  }) async {
    await _database.permanentlyClearHistory(
      confirmedPermanent: confirmedPermanent,
    );
    return loadAllAndSync();
  }

  Future<String?> resyncAlarms() async {
    final schedules = await _database.loadSchedules();
    final events = await _database.loadEvents();
    return _syncAlarmsSafely(schedules, events);
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

  Future<void> close() => _database.close();

  Future<String?> _syncAlarmsSafely(
    List<SubjectSchedule> schedules,
    List<EventSchedule> events,
  ) async {
    try {
      await _alarmService.syncAlarms(
        buildAlarmPayloads(schedules, events: events),
      );
      return null;
    } catch (e) {
      return 'Saved in SQLite, but alarm sync failed: $e';
    }
  }
}
