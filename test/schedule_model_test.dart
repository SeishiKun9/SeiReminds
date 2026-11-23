import 'package:flutter_test/flutter_test.dart';
import 'package:seireminds/data/repositories/schedule_repository.dart';
import 'package:seireminds/data/services/alarm_service.dart';
import 'package:seireminds/data/services/local_schedule_storage.dart';
import 'package:seireminds/domain/models/schedule_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAlarmService implements AlarmService {
  List<ScheduledAlarmPayload> lastSynced = const <ScheduledAlarmPayload>[];
  bool shouldFailSync = false;

  @override
  Future<void> syncAlarms(List<ScheduledAlarmPayload> alarms) async {
    if (shouldFailSync) {
      throw Exception('AlarmManager unavailable');
    }
    lastSynced = List<ScheduledAlarmPayload>.of(alarms);
  }

  @override
  Future<AlarmPermissionStatus> getPermissionStatus() async =>
      const AlarmPermissionStatus.unsupported();

  @override
  Future<void> openBatteryOptimizationSettings() async {}

  @override
  Future<void> openDndSettings() async {}

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> stopActiveAlarm() async {}

  @override
  Future<void> triggerTestAlarm() async {}
}

void main() {
  group('Section A-Z validation', () {
    test('accepts single ASCII letters and normalizes uppercase', () {
      expect(validateSectionLetter('a'), isNull);
      expect(validateSectionLetter('Z'), isNull);
      expect(validateSectionLetter(' m '), isNull);
      expect(normalizeSectionLetter('b'), 'B');
    });

    test('rejects empty, multi-letter, and non-letter values', () {
      expect(validateSectionLetter(''), isNotNull);
      expect(validateSectionLetter('   '), isNotNull);
      expect(validateSectionLetter('AB'), contains('1 letter'));
      expect(validateSectionLetter('1'), contains('A to Z'));
      expect(validateSectionLetter('@'), contains('A to Z'));
      expect(() => normalizeSectionLetter('AB'), throwsFormatException);
    });
  });

  group('Session and SubjectSchedule validation & JSON', () {
    test('rejects invalid days and timeOut <= timeIn', () {
      final noDays = SessionSchedule(
        type: SessionType.lecture,
        days: const <int>[],
        timeIn: const ScheduleTime(hour: 8, minute: 0),
        timeOut: const ScheduleTime(hour: 9, minute: 0),
      );
      expect(noDays.validate(), isNotNull);

      final sunday = SessionSchedule(
        type: SessionType.lecture,
        days: const <int>[DateTime.sunday],
        timeIn: const ScheduleTime(hour: 8, minute: 0),
        timeOut: const ScheduleTime(hour: 9, minute: 0),
      );
      expect(sunday.validate(), isNotNull);

      final badTime = SessionSchedule(
        type: SessionType.laboratory,
        days: const <int>[DateTime.monday],
        timeIn: const ScheduleTime(hour: 10, minute: 0),
        timeOut: const ScheduleTime(hour: 10, minute: 0),
      );
      expect(badTime.validate(), contains('after Time In'));
    });

    test('round-trips Online Time + Lecture + Laboratory JSON cleanly', () {
      final original = SubjectSchedule(
        id: 'subj-1',
        subject: 'Computer Architecture',
        section: 'c',
        reminderMinutesBefore: 15,
        reminderEnabled: true,
        sessions: <SessionType, SessionSchedule>{
          SessionType.onlineTime: SessionSchedule(
            type: SessionType.onlineTime,
            days: const <int>[DateTime.saturday],
            timeIn: const ScheduleTime(hour: 8, minute: 0),
            timeOut: const ScheduleTime(hour: 9, minute: 30),
          ),
          SessionType.lecture: SessionSchedule(
            type: SessionType.lecture,
            days: const <int>[DateTime.monday, DateTime.wednesday],
            timeIn: const ScheduleTime(hour: 10, minute: 0),
            timeOut: const ScheduleTime(hour: 11, minute: 30),
          ),
          SessionType.laboratory: SessionSchedule(
            type: SessionType.laboratory,
            days: const <int>[DateTime.friday],
            timeIn: const ScheduleTime(hour: 13, minute: 0),
            timeOut: const ScheduleTime(hour: 16, minute: 0),
          ),
        },
      );

      final restored = SubjectSchedule.fromJson(original.toJson());
      expect(restored.id, 'subj-1');
      expect(restored.subject, 'Computer Architecture');
      expect(restored.section, 'C');
      expect(restored.sessions.length, 3);
      expect(
        restored.sessions[SessionType.lecture]!.days,
        <int>[DateTime.monday, DateTime.wednesday],
      );
      expect(
        restored.sessions[SessionType.laboratory]!.timeOut,
        const ScheduleTime(hour: 16, minute: 0),
      );
      expect(restored.reminderMinutesBefore, 15);
    });
  });

  group('Alarm trigger calculation', () {
    test('handles same-day lead time, zero lead time, and midnight wrap', () {
      final normal = computeAlarmTrigger(
        weekday: DateTime.wednesday,
        timeIn: const ScheduleTime(hour: 8, minute: 0),
        minutesBefore: 10,
      );
      expect(normal, (weekday: DateTime.wednesday, hour: 7, minute: 50));

      final exact = computeAlarmTrigger(
        weekday: DateTime.friday,
        timeIn: const ScheduleTime(hour: 14, minute: 30),
        minutesBefore: 0,
      );
      expect(exact, (weekday: DateTime.friday, hour: 14, minute: 30));

      final wrappedToSunday = computeAlarmTrigger(
        weekday: DateTime.monday,
        timeIn: const ScheduleTime(hour: 0, minute: 5),
        minutesBefore: 10,
      );
      expect(wrappedToSunday, (weekday: DateTime.sunday, hour: 23, minute: 55));

      final wrappedToMonday = computeAlarmTrigger(
        weekday: DateTime.tuesday,
        timeIn: const ScheduleTime(hour: 0, minute: 0),
        minutesBefore: 15,
      );
      expect(wrappedToMonday, (weekday: DateTime.monday, hour: 23, minute: 45));
    });

    test('builds unique alarms only for reminder-enabled schedules', () {
      final active = SubjectSchedule(
        id: 'a1',
        subject: 'Physics',
        section: 'A',
        reminderMinutesBefore: 10,
        sessions: <SessionType, SessionSchedule>{
          SessionType.lecture: SessionSchedule(
            type: SessionType.lecture,
            days: const <int>[DateTime.monday, DateTime.thursday],
            timeIn: const ScheduleTime(hour: 9, minute: 0),
            timeOut: const ScheduleTime(hour: 10, minute: 30),
          ),
          SessionType.laboratory: SessionSchedule(
            type: SessionType.laboratory,
            days: const <int>[DateTime.saturday],
            timeIn: const ScheduleTime(hour: 13, minute: 0),
            timeOut: const ScheduleTime(hour: 15, minute: 0),
          ),
        },
      );
      final muted = active.copyWith(id: 'a2', reminderEnabled: false);

      final payloads = buildAlarmPayloads(<SubjectSchedule>[active, muted]);
      expect(payloads.length, 3);
      expect(payloads.map((p) => p.id).toSet().length, 3);
      expect(payloads.every((p) => p.id >= 1000), isTrue);
    });
  });

  group('Offline storage & repository', () {
    test('persists schedules offline and surfaces alarm sync warnings safely', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final storage = SharedPreferencesScheduleStorage(prefs: prefs);
      final alarmService = _FakeAlarmService();
      final repo = ScheduleRepository(
        storage: storage,
        alarmService: alarmService,
      );

      final schedule = SubjectSchedule(
        id: 'offline-1',
        subject: 'Calculus 1',
        section: 'A',
        sessions: <SessionType, SessionSchedule>{
          SessionType.onlineTime: SessionSchedule(
            type: SessionType.onlineTime,
            days: const <int>[DateTime.monday],
            timeIn: const ScheduleTime(hour: 8, minute: 0),
            timeOut: const ScheduleTime(hour: 9, minute: 0),
          ),
        },
      );

      final saved = await repo.saveSchedule(const <SubjectSchedule>[], schedule);
      expect(saved.schedules.length, 1);
      expect(saved.alarmSyncWarning, isNull);
      expect(alarmService.lastSynced.length, 1);

      // Reload from disk.
      final reloaded = await repo.loadAndSync();
      expect(reloaded.schedules.length, 1);
      expect(reloaded.schedules.first.subject, 'Calculus 1');

      // Alarm failure does not discard offline save.
      alarmService.shouldFailSync = true;
      final updated = await repo.toggleReminder(reloaded.schedules, 'offline-1', false);
      expect(updated.schedules.first.reminderEnabled, isFalse);
      expect(updated.alarmSyncWarning, contains('saved offline'));
    });

    test('throws StorageFormatException on corrupt stored JSON', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPreferencesScheduleStorage.storageKey: '{not valid json',
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = SharedPreferencesScheduleStorage(prefs: prefs);
      expect(storage.readAll(), throwsA(isA<StorageFormatException>()));
    });
  });
}
