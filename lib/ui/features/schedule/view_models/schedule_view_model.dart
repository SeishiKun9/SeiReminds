import 'package:flutter/foundation.dart';

import '../../../../data/repositories/canvas_token_repository.dart';
import '../../../../data/repositories/schedule_repository.dart';
import '../../../../data/services/alarm_service.dart';
import '../../../../domain/models/canvas_token_models.dart';
import '../../../../domain/models/schedule_models.dart';

class ScheduleViewModel extends ChangeNotifier {
  ScheduleViewModel({
    required this._repository,
    int? initialWeekday,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        _selectedWeekday = _clampToSchoolDay(
          initialWeekday ?? (clock ?? DateTime.now)().weekday,
        );

  final ScheduleRepository _repository;
  final DateTime Function() _clock;

  List<SubjectSchedule> _schedules = const <SubjectSchedule>[];
  List<SubjectSchedule> get schedules => _schedules;

  List<EventSchedule> _events = const <EventSchedule>[];
  List<EventSchedule> get events => _events;

  List<HistoryEntry> _activeHistory = const <HistoryEntry>[];
  List<HistoryEntry> get activeHistory => _activeHistory;

  List<HistoryEntry> _archivedHistory = const <HistoryEntry>[];
  List<HistoryEntry> get archivedHistory => _archivedHistory;

  bool _historyViewEnabled = true;
  bool get historyViewEnabled => _historyViewEnabled;

  // Stored temporarily in SQLite ONLY until deadline expires.
  List<CanvasDailyItem> _activeCanvasActivities = const <CanvasDailyItem>[];
  List<CanvasDailyItem> get canvasActivities => _activeCanvasActivities;

  // Live current-day announcements kept in memory ONLY (never saved to SQLite).
  List<CanvasDailyItem> _todayCanvasAnnouncements = const <CanvasDailyItem>[];
  List<CanvasDailyItem> get canvasAnnouncements => _todayCanvasAnnouncements;

  List<CanvasDailyItem> get canvasGeneralItems {
    final combined = <CanvasDailyItem>[
      ..._todayCanvasAnnouncements,
      ..._activeCanvasActivities,
    ]..sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return combined;
  }

  List<CanvasDailyItem> get canvasReminders {
    final upcoming = List<CanvasDailyItem>.of(_activeCanvasActivities)
      ..sort(
        (a, b) => a.effectiveExpiresAt.compareTo(b.effectiveExpiresAt),
      );
    return upcoming;
  }

  List<CanvasDailyItem> get todayCanvasItems => canvasGeneralItems;

  String? _lastDailyCleanupDate;
  String? get lastDailyCleanupDate => _lastDailyCleanupDate;

  int _lastDailyCleanupRemoved = 0;
  int get lastDailyCleanupRemoved => _lastDailyCleanupRemoved;

  bool _isSyncingCanvas = false;
  bool get isSyncingCanvas => _isSyncingCanvas;

  String? _canvasSyncMessage;
  String? get canvasSyncMessage => _canvasSyncMessage;

  int _selectedWeekday;
  int get selectedWeekday => _selectedWeekday;

  bool _hasInitialized = false;
  bool get hasInitialized => _hasInitialized;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _bannerMessage;
  String? get bannerMessage => _bannerMessage;

  AlarmPermissionStatus _permissionStatus =
      const AlarmPermissionStatus.unsupported();
  AlarmPermissionStatus get permissionStatus => _permissionStatus;

  List<DaySessionItem> get selectedDaySessions =>
      sessionsForWeekday(_schedules, _selectedWeekday);

  List<DaySubjectGroup> get selectedDaySubjects =>
      groupedSubjectsForWeekday(_schedules, _selectedWeekday);

  List<EventSchedule> get selectedDayEvents =>
      eventsForWeekday(_events, _selectedWeekday);

  ({DaySessionItem item, bool isInProgress, int minutesUntilStart})?
      get nextUpcomingSession =>
          findNextUpcomingSession(_schedules, _events, now: _clock());

  int subjectCountForDay(int weekday) =>
      groupedSubjectsForWeekday(_schedules, weekday).length;

  int sessionCountForDay(int weekday) =>
      sessionsForWeekday(_schedules, weekday).length;

  int eventCountForDay(int weekday) =>
      eventsForWeekday(_events, weekday).length;

  int get totalActiveAlarmCount =>
      buildAlarmPayloads(_schedules, events: _events).length;

  List<EventSchedule> conflictingEventsFor(DaySessionItem item) =>
      conflictingEventsForSession(_events, item.weekday, item.session);

  List<EventSchedule> conflictingEventsForSessionOnDay(
    int weekday,
    SessionSchedule session,
  ) =>
      conflictingEventsForSession(_events, weekday, session);

  List<DaySessionItem> affectedSessionsForDayEvent(
    EventSchedule event,
    int weekday,
  ) =>
      affectedSessionsForEventOnDay(event, _schedules, weekday);

  List<String> get knownSubjects {
    final names = _schedules.map((s) => s.subject).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  static int _clampToSchoolDay(int weekday) {
    if (weekday >= DateTime.monday && weekday <= DateTime.saturday) {
      return weekday;
    }
    return DateTime.monday;
  }

  void _applySnapshot(ScheduleDataSnapshot snapshot) {
    _schedules = snapshot.schedules;
    _events = snapshot.events;
    _activeHistory = snapshot.activeHistory;
    _archivedHistory = snapshot.archivedHistory;
    _historyViewEnabled = snapshot.historyViewEnabled;
    _activeCanvasActivities = snapshot.activeCanvasActivities;
    _lastDailyCleanupDate = snapshot.lastDailyCleanupDate;
    _lastDailyCleanupRemoved = snapshot.lastDailyCleanupRemoved;
    _bannerMessage = snapshot.alarmSyncWarning;
    _errorMessage = null;
  }

  Future<void> initialize() async {
    _hasInitialized = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final snapshot = await _repository.loadAllAndSync();
      _applySnapshot(snapshot);
      _permissionStatus = await _repository.getPermissionStatus();
    } catch (e) {
      _errorMessage = 'Could not load offline SQLite database: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Purges expired activities automatically on resume / day rollover and clears stale in-memory announcements.
  Future<void> checkDailyRolloverCleanup() async {
    if (!_hasInitialized) return;
    final todayKey = localDateKey(_clock());
    if (_lastDailyCleanupDate != todayKey) {
      _todayCanvasAnnouncements = const <CanvasDailyItem>[];
    }
    await runDailyStorageCleanup();
  }

  Future<DailyCleanupResult?> runDailyStorageCleanup() async {
    try {
      final result = await _repository.runDailyStorageCleanup();
      _applySnapshot(result.snapshot);
      notifyListeners();
      return result.cleanup;
    } catch (e) {
      _bannerMessage = 'Daily storage cleanup failed: $e';
      notifyListeners();
      return null;
    }
  }

  /// Syncs Canvas announcements (in-memory today-only) and activities
  /// (stored temporarily in SQLite ONLY until their deadline expires).
  Future<CanvasTodaySyncResult> syncTodayCanvasUpdates(
    CanvasTokenRepository canvasRepository,
  ) async {
    if (_isSyncingCanvas) {
      return CanvasTodaySyncResult(
        succeeded: false,
        message: 'Canvas sync is already in progress.',
        todayAnnouncements: _todayCanvasAnnouncements,
        activeActivities: _activeCanvasActivities,
        newlyNotifiedCount: 0,
        clearedStaleCount: 0,
      );
    }

    _isSyncingCanvas = true;
    notifyListeners();

    try {
      final fetched = await canvasRepository.fetchTodayUpdates(now: _clock());
      final result = await _repository.syncTodayCanvasItems(fetched);
      _todayCanvasAnnouncements = result.todayAnnouncements;
      _activeCanvasActivities = result.activeActivities;
      _lastDailyCleanupDate = localDateKey(_clock());
      _canvasSyncMessage = result.message;
      return result;
    } on CanvasApiException catch (e) {
      _canvasSyncMessage = e.message;
      return CanvasTodaySyncResult(
        succeeded: false,
        message: e.message,
        todayAnnouncements: _todayCanvasAnnouncements,
        activeActivities: _activeCanvasActivities,
        newlyNotifiedCount: 0,
        clearedStaleCount: 0,
      );
    } catch (_) {
      const msg =
          'Could not sync Canvas updates right now. Offline schedules remain unaffected.';
      _canvasSyncMessage = msg;
      return CanvasTodaySyncResult(
        succeeded: false,
        message: msg,
        todayAnnouncements: _todayCanvasAnnouncements,
        activeActivities: _activeCanvasActivities,
        newlyNotifiedCount: 0,
        clearedStaleCount: 0,
      );
    } finally {
      _isSyncingCanvas = false;
      notifyListeners();
    }
  }

  Future<void> clearCanvasDailyCache() async {
    await _repository.clearCanvasDailyCache();
    _todayCanvasAnnouncements = const <CanvasDailyItem>[];
    _activeCanvasActivities = const <CanvasDailyItem>[];
    _canvasSyncMessage = null;
    notifyListeners();
  }

  void selectWeekday(int weekday) {
    if (weekday < DateTime.monday || weekday > DateTime.saturday) return;
    if (_selectedWeekday == weekday) return;
    _selectedWeekday = weekday;
    notifyListeners();
  }

  void clearBanner() {
    if (_bannerMessage == null) return;
    _bannerMessage = null;
    notifyListeners();
  }

  Future<bool> saveSchedule(SubjectSchedule schedule) async {
    try {
      final isNew = !_schedules.any((s) => s.id == schedule.id);
      final snapshot = await _repository.saveSchedule(schedule, isNew: isNew);
      _applySnapshot(snapshot);
      notifyListeners();
      return true;
    } catch (e) {
      _bannerMessage = 'Failed to save schedule: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteScheduleFromScheduleScreen(String id) async {
    try {
      final snapshot = await _repository.deleteSchedule(
        id,
        confirmedFromSchedule: true,
      );
      _applySnapshot(snapshot);
      notifyListeners();
    } catch (e) {
      _bannerMessage = 'Failed to delete schedule: $e';
      notifyListeners();
    }
  }

  Future<void> toggleReminder(String id, bool enabled) async {
    try {
      final snapshot = await _repository.toggleScheduleReminder(id, enabled);
      _applySnapshot(snapshot);
      notifyListeners();
    } catch (e) {
      _bannerMessage = 'Failed to update reminder: $e';
      notifyListeners();
    }
  }

  Future<List<DaySessionItem>?> saveEvent(EventSchedule event) async {
    try {
      final isNew = !_events.any((e) => e.id == event.id);
      final affected = affectedSessionsForEvent(event, _schedules);
      final snapshot = await _repository.saveEvent(event, isNew: isNew);
      _applySnapshot(snapshot);
      notifyListeners();
      return affected;
    } catch (e) {
      _bannerMessage = 'Failed to save event: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteEvent(String id) async {
    try {
      final snapshot = await _repository.deleteEvent(id);
      _applySnapshot(snapshot);
      notifyListeners();
    } catch (e) {
      _bannerMessage = 'Failed to delete event: $e';
      notifyListeners();
    }
  }

  Future<void> toggleEventReminder(String id, bool enabled) async {
    try {
      final snapshot = await _repository.toggleEventReminder(id, enabled);
      _applySnapshot(snapshot);
      notifyListeners();
    } catch (e) {
      _bannerMessage = 'Failed to update event reminder: $e';
      notifyListeners();
    }
  }

  Future<void> setHistoryViewEnabled(bool enabled) async {
    try {
      final snapshot = await _repository.setHistoryViewEnabled(enabled);
      _applySnapshot(snapshot);
      notifyListeners();
    } catch (e) {
      _bannerMessage = 'Could not update history setting: $e';
      notifyListeners();
    }
  }

  Future<bool> clearHistory() async {
    try {
      final snapshot = await _repository.clearHistory();
      _applySnapshot(snapshot);
      notifyListeners();
      return true;
    } catch (e) {
      _bannerMessage = 'Could not clear history: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> restoreArchivedHistory() async {
    try {
      final snapshot = await _repository.restoreArchivedHistory();
      _applySnapshot(snapshot);
      notifyListeners();
      return true;
    } catch (e) {
      _bannerMessage = 'Could not restore history: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> permanentlyClearHistory() async {
    try {
      final snapshot = await _repository.permanentlyClearHistory(
        confirmedPermanent: true,
      );
      _applySnapshot(snapshot);
      notifyListeners();
      return true;
    } catch (e) {
      _bannerMessage = 'Could not permanently clear history: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshPermissions() async {
    _permissionStatus = await _repository.getPermissionStatus();
    notifyListeners();
  }

  Future<void> requestNotificationPermission() async {
    await _repository.requestNotificationPermission();
    await refreshPermissions();
    await _repository.resyncAlarms();
  }

  Future<void> openExactAlarmSettings() =>
      _repository.openExactAlarmSettings();

  Future<void> openDndSettings() => _repository.openDndSettings();

  Future<void> openBatteryOptimizationSettings() =>
      _repository.openBatteryOptimizationSettings();

  Future<void> triggerTestAlarm() => _repository.triggerTestAlarm();

  Future<void> stopActiveAlarm() => _repository.stopActiveAlarm();
}
