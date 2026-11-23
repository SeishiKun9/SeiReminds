import 'package:flutter_test/flutter_test.dart';
import 'package:seireminds/data/repositories/schedule_repository.dart';
import 'package:seireminds/data/services/alarm_service.dart';
import 'package:seireminds/data/services/sqlite_database_service.dart';
import 'package:seireminds/domain/models/schedule_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

SqliteScheduleDatabase _createInMemoryDb() {
  return SqliteScheduleDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

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
      expect(restored.section, 'C');
      expect(restored.sessions.length, 3);
      expect(restored.reminderMinutesBefore, 15);
    });
  });

  group('EventSchedule validation & class cancellation overlap', () {
    test('enforces Monday-Friday days and Morning / Afternoon / Both bounds', () {
      expect(
        EventSchedule.validateFields(
          title: 'Sports Fest',
          days: const <int>[DateTime.saturday],
          period: EventPeriod.morning,
          timeIn: const ScheduleTime(hour: 8, minute: 0),
          timeOut: const ScheduleTime(hour: 12, minute: 0),
        ),
        contains('Monday to Friday'),
      );

      expect(
        EventSchedule.validateFields(
          title: 'Assembly',
          days: const <int>[DateTime.monday],
          period: EventPeriod.morning,
          timeIn: const ScheduleTime(hour: 9, minute: 0),
          timeOut: const ScheduleTime(hour: 13, minute: 0),
        ),
        contains('12:00 PM'),
      );

      expect(
        EventSchedule.validateFields(
          title: 'Seminar',
          days: const <int>[DateTime.tuesday],
          period: EventPeriod.afternoon,
          timeIn: const ScheduleTime(hour: 11, minute: 0),
          timeOut: const ScheduleTime(hour: 15, minute: 0),
        ),
        contains('12:00 PM'),
      );

      expect(
        EventSchedule.validateFields(
          title: 'Whole Day Fair',
          days: const <int>[DateTime.wednesday],
          period: EventPeriod.both,
          timeIn: const ScheduleTime(hour: 8, minute: 0),
          timeOut: const ScheduleTime(hour: 11, minute: 30),
        ),
        contains('after 12:00 PM'),
      );

      expect(
        EventSchedule.validateFields(
          title: 'Whole Day Fair',
          days: const <int>[DateTime.monday, DateTime.friday],
          period: EventPeriod.both,
          timeIn: const ScheduleTime(hour: 8, minute: 0),
          timeOut: const ScheduleTime(hour: 17, minute: 0),
        ),
        isNull,
      );
    });

    test('suppresses overlapping class alarm and announces cancellation via event alarm', () {
      final schedule = SubjectSchedule(
        id: 'calc-1',
        subject: 'Calculus 1',
        section: 'A',
        reminderMinutesBefore: 10,
        sessions: <SessionType, SessionSchedule>{
          SessionType.lecture: SessionSchedule(
            type: SessionType.lecture,
            days: const <int>[DateTime.monday, DateTime.wednesday],
            timeIn: const ScheduleTime(hour: 9, minute: 0),
            timeOut: const ScheduleTime(hour: 10, minute: 30),
          ),
          SessionType.laboratory: SessionSchedule(
            type: SessionType.laboratory,
            days: const <int>[DateTime.monday],
            timeIn: const ScheduleTime(hour: 12, minute: 0),
            timeOut: const ScheduleTime(hour: 14, minute: 0),
          ),
        },
      );

      // Morning event 8:00 AM - 12:00 PM hits Monday Lecture (9:00-10:30),
      // does NOT hit back-to-back Monday Lab (12:00-2:00) or Wednesday Lecture.
      final event = EventSchedule(
        id: 'evt-1',
        title: 'Foundation Day',
        days: const <int>[DateTime.monday],
        period: EventPeriod.morning,
        timeIn: const ScheduleTime(hour: 8, minute: 0),
        timeOut: const ScheduleTime(hour: 12, minute: 0),
      );

      final payloads = buildAlarmPayloads(
        <SubjectSchedule>[schedule],
        events: <EventSchedule>[event],
      );

      // Expected 3 alarms: Wed Lecture + Mon Lab + Mon Event cancellation announcement.
      expect(payloads.length, 3);
      final eventAlarms = payloads.where((p) => p.sessionLabel == 'Event').toList();
      expect(eventAlarms.length, 1);
      expect(eventAlarms.first.title, contains('Classes Canceled'));
      expect(eventAlarms.first.body, contains('Calculus 1 (Sec A · Lecture)'));

      // Monday Lecture alarm suppressed; Wednesday Lecture remains.
      final lectureAlarms =
          payloads.where((p) => p.sessionLabel == 'Lecture').toList();
      expect(lectureAlarms.length, 1);
      expect(lectureAlarms.first.weekday, DateTime.wednesday);
    });
  });

  group('Alarm trigger calculation', () {
    test('handles same-day lead time, zero lead time, and midnight wrap', () {
      expect(
        computeAlarmTrigger(
          weekday: DateTime.wednesday,
          timeIn: const ScheduleTime(hour: 8, minute: 0),
          minutesBefore: 10,
        ),
        (weekday: DateTime.wednesday, hour: 7, minute: 50),
      );

      expect(
        computeAlarmTrigger(
          weekday: DateTime.monday,
          timeIn: const ScheduleTime(hour: 0, minute: 5),
          minutesBefore: 10,
        ),
        (weekday: DateTime.sunday, hour: 23, minute: 55),
      );
    });
  });

  group('SQLite persistence, History preservation & Schedule Protection', () {
    test('soft clear preserves history, permanent clear keeps schedules, and deletion guard works', () async {
      final db = _createInMemoryDb();
      final alarmService = _FakeAlarmService();
      final repo = ScheduleRepository(
        database: db,
        alarmService: alarmService,
      );

      try {
        final schedule = SubjectSchedule(
          id: 'sched-1',
          subject: 'Operating Systems',
          section: 'D',
          sessions: <SessionType, SessionSchedule>{
            SessionType.lecture: SessionSchedule(
              type: SessionType.lecture,
              days: const <int>[DateTime.tuesday],
              timeIn: const ScheduleTime(hour: 10, minute: 0),
              timeOut: const ScheduleTime(hour: 11, minute: 30),
            ),
          },
        );

        final afterSave = await repo.saveSchedule(schedule, isNew: true);
        expect(afterSave.schedules.length, 1);
        expect(afterSave.activeHistory.length, 1);
        expect(afterSave.archivedHistory, isEmpty);

        // Soft clear hides visible history without deleting SQLite data or schedules.
        final afterSoftClear = await repo.clearHistory();
        expect(afterSoftClear.activeHistory, isEmpty);
        expect(afterSoftClear.archivedHistory.length, 1);
        expect(afterSoftClear.schedules.length, 1);
        expect(afterSoftClear.schedules.first.subject, 'Operating Systems');

        // Restoring brings preserved history back.
        final afterRestore = await repo.restoreArchivedHistory();
        expect(afterRestore.activeHistory.length, 1);
        expect(afterRestore.archivedHistory, isEmpty);

        // Unconfirmed permanent clear is blocked by ScheduleProtectionException.
        await expectLater(
          repo.permanentlyClearHistory(confirmedPermanent: false),
          throwsA(isA<ScheduleProtectionException>()),
        );

        // Confirmed permanent clear removes ONLY history; schedules stay intact.
        final afterPermClear = await repo.permanentlyClearHistory(
          confirmedPermanent: true,
        );
        expect(afterPermClear.activeHistory, isEmpty);
        expect(afterPermClear.archivedHistory, isEmpty);
        expect(afterPermClear.schedules.length, 1);
        expect(afterPermClear.schedules.first.id, 'sched-1');

        // Unconfirmed schedule deletion is blocked by ScheduleProtectionException.
        await expectLater(
          repo.deleteSchedule('sched-1', confirmedFromSchedule: false),
          throwsA(isA<ScheduleProtectionException>()),
        );

        // Confirmed deletion from schedule removes the class and logs history.
        final afterRemove = await repo.deleteSchedule(
          'sched-1',
          confirmedFromSchedule: true,
        );
        expect(afterRemove.schedules, isEmpty);
        expect(afterRemove.activeHistory.length, 1);
        expect(afterRemove.activeHistory.first.action, 'schedule_deleted');
      } finally {
        await repo.close();
      }
    });

    test('saves in SQLite even if alarm sync fails', () async {
      final db = _createInMemoryDb();
      final alarmService = _FakeAlarmService()..shouldFailSync = true;
      final repo = ScheduleRepository(
        database: db,
        alarmService: alarmService,
      );

      try {
        final schedule = SubjectSchedule(
          id: 'sched-offline',
          subject: 'Physics',
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
        final res = await repo.saveSchedule(schedule, isNew: true);
        expect(res.schedules.length, 1);
        expect(res.alarmSyncWarning, contains('Saved in SQLite'));
      } finally {
        await repo.close();
      }
    });
  });
}
