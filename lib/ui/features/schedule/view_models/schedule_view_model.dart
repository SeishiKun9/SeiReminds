import 'package:flutter/foundation.dart';

import '../../../../data/repositories/schedule_repository.dart';
import '../../../../data/services/alarm_service.dart';
import '../../../../domain/models/schedule_models.dart';

class ScheduleViewModel extends ChangeNotifier {
  ScheduleViewModel({
    required this._repository,
    int? initialWeekday,
  }) : _selectedWeekday = _clampToSchoolDay(
          initialWeekday ?? DateTime.now().weekday,
        );

  final ScheduleRepository _repository;

  List<SubjectSchedule> _schedules = const <SubjectSchedule>[];
  List<SubjectSchedule> get schedules => _schedules;

  int _selectedWeekday;
  int get selectedWeekday => _selectedWeekday;

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

  int sessionCountForDay(int weekday) =>
      sessionsForWeekday(_schedules, weekday).length;

  int get totalActiveAlarmCount => buildAlarmPayloads(_schedules).length;

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

  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.loadAndSync();
      _schedules = List<SubjectSchedule>.unmodifiable(result.schedules);
      _bannerMessage = result.alarmSyncWarning;
      _permissionStatus = await _repository.getPermissionStatus();
    } catch (e) {
      _errorMessage = 'Could not load offline schedule: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
      final result = await _repository.saveSchedule(_schedules, schedule);
      _schedules = result.schedules;
      _errorMessage = null;
      _bannerMessage = result.alarmSyncWarning;
      notifyListeners();
      return true;
    } catch (e) {
      _bannerMessage = 'Failed to save schedule: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteSchedule(String id) async {
    try {
      final result = await _repository.deleteSchedule(_schedules, id);
      _schedules = result.schedules;
      _bannerMessage = result.alarmSyncWarning;
      notifyListeners();
    } catch (e) {
      _bannerMessage = 'Failed to delete schedule: $e';
      notifyListeners();
    }
  }

  Future<void> toggleReminder(String id, bool enabled) async {
    try {
      final result = await _repository.toggleReminder(_schedules, id, enabled);
      _schedules = result.schedules;
      _bannerMessage = result.alarmSyncWarning;
      notifyListeners();
    } catch (e) {
      _bannerMessage = 'Failed to update reminder: $e';
      notifyListeners();
    }
  }

  Future<void> refreshPermissions() async {
    _permissionStatus = await _repository.getPermissionStatus();
    notifyListeners();
  }

  Future<void> requestNotificationPermission() async {
    await _repository.requestNotificationPermission();
    await refreshPermissions();
    await _repository.resyncAlarms(_schedules);
  }

  Future<void> openExactAlarmSettings() async {
    await _repository.openExactAlarmSettings();
  }

  Future<void> openDndSettings() async {
    await _repository.openDndSettings();
  }

  Future<void> openBatteryOptimizationSettings() async {
    await _repository.openBatteryOptimizationSettings();
  }

  Future<void> triggerTestAlarm() async {
    await _repository.triggerTestAlarm();
  }

  Future<void> stopActiveAlarm() async {
    await _repository.stopActiveAlarm();
  }
}
