import '../../domain/models/canvas_token_models.dart';
import '../../domain/models/schedule_models.dart';
import '../services/alarm_service.dart';
import '../services/sqlite_database_service.dart';

class ScheduleDataSnapshot {
  const ScheduleDataSnapshot({
    required this.schedules,
    required this.events,
    required this.activeHistory,
    required this.archivedHistory,
    this.todayCanvasItems = const <CanvasDailyItem>[],
    this.lastDailyCleanupDate,
    this.lastDailyCleanupRemoved = 0,
    this.alarmSyncWarning,
  });

  final List<SubjectSchedule> schedules;
  final List<EventSchedule> events;
  final List<HistoryEntry> activeHistory;
  final List<HistoryEntry> archivedHistory;
  final List<CanvasDailyItem> todayCanvasItems;
  final String? lastDailyCleanupDate;
  final int lastDailyCleanupRemoved;
  final String? alarmSyncWarning;
}

/// Single source of truth backed by local SQLite and native Android alarms.
/// All schedule, event, history, alarm, and daily storage cleanup operations work 100% offline.
class ScheduleRepository {
  ScheduleRepository({
    required this._database,
    required this._alarmService,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SqliteScheduleDatabase _database;
  final AlarmService _alarmService;
  final DateTime Function() _clock;

  Future<ScheduleDataSnapshot> loadAllAndSync({bool skipCleanup = false}) async {
    final now = _clock();
    if (!skipCleanup) {
      await _database.runDailyStorageCleanup(now: now);
    }
    final schedules = await _database.loadSchedules();
    final events = await _database.loadEvents();
    final activeHistory = await _database.loadHistory(archivedOnly: false);
    final archivedHistory = await _database.loadHistory(archivedOnly: true);
    final todayCanvasItems = await _database.loadTodayCanvasItems(now: now);
    final cleanupMeta = await _database.getDailyCleanupMeta();
    final warning = await _syncAlarmsSafely(schedules, events);
    return ScheduleDataSnapshot(
      schedules: List<SubjectSchedule>.unmodifiable(schedules),
      events: List<EventSchedule>.unmodifiable(events),
      activeHistory: List<HistoryEntry>.unmodifiable(activeHistory),
      archivedHistory: List<HistoryEntry>.unmodifiable(archivedHistory),
      todayCanvasItems: List<CanvasDailyItem>.unmodifiable(todayCanvasItems),
      lastDailyCleanupDate: cleanupMeta.lastDate,
      lastDailyCleanupRemoved: cleanupMeta.lastRemovedCount,
      alarmSyncWarning: warning,
    );
  }

  Future<({ScheduleDataSnapshot snapshot, DailyCleanupResult cleanup})>
      runDailyStorageCleanup() async {
    final cleanup = await _database.runDailyStorageCleanup(now: _clock());
    final snapshot = await loadAllAndSync(skipCleanup: true);
    return (snapshot: snapshot, cleanup: cleanup);
  }

  /// Stores ONLY today's Canvas announcements/activities, clears yesterday's cache,
  /// and notifies each newly posted today item once (never re-notifies).
  Future<CanvasTodaySyncResult> syncTodayCanvasItems(
    List<CanvasDailyItem> fetched,
  ) async {
    final now = _clock();
    final synced = await _database.syncTodayCanvasItems(fetched, now: now);
    final notifiedIds = <String>[];

    for (final item in synced.newlyUnnotified) {
      final notifTitle = '${item.kind.label} · ${item.courseName}';
      final notifBody = item.message.isNotEmpty
          ? '${item.title}: ${item.message}'
          : item.title;
      try {
        await _alarmService.showCanvasNotification(
          id: stableCanvasNotificationId(item.id, item.postedDate),
          title: notifTitle,
          body: notifBody,
        );
        notifiedIds.add(item.id);
      } catch (_) {
        // Leave unnotified so a retry can deliver if notification channel failed transiently.
      }
    }

    if (notifiedIds.isNotEmpty) {
      await _database.markCanvasItemsNotified(
        notifiedIds,
        postedDate: synced.cleanup.dateKey,
      );
    }

    final latestToday = await _database.loadTodayCanvasItems(now: now);
    final msg = latestToday.isEmpty
        ? 'No Canvas announcements or activities posted today.'
        : notifiedIds.isEmpty
            ? '${latestToday.length} update(s) from today loaded (already notified).'
            : 'Synced ${latestToday.length} update(s) from today (${notifiedIds.length} new notification${notifiedIds.length == 1 ? '' : 's'}).';

    return CanvasTodaySyncResult(
      succeeded: true,
      message: msg,
      todayItems: List<CanvasDailyItem>.unmodifiable(latestToday),
      newlyNotifiedCount: notifiedIds.length,
      clearedStaleCount: synced.cleanup.clearedItemsCount,
    );
  }

  Future<void> clearCanvasDailyCache() => _database.clearCanvasDailyCache();

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
