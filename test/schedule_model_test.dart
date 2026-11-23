import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  group('EventSchedule Whole Day, Evening Time In & cancellation overlap', () {
    test(
      'enforces Mon-Fri days, Morning/Afternoon/Whole Day slots, and optional Evening Time In',
      () {
        expect(
          EventSchedule.validateFields(
            title: 'Sports Fest',
            days: const <int>[DateTime.saturday],
            period: EventPeriod.morning,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
          ),
          contains('Monday to Friday'),
        );

        expect(
          EventSchedule.validateFields(
            title: 'Assembly',
            days: const <int>[DateTime.monday],
            period: EventPeriod.morning,
            morningTimeIn: const ScheduleTime(hour: 9, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 13, minute: 0),
          ),
          contains('12:00 PM'),
        );

        expect(
          EventSchedule.validateFields(
            title: 'Seminar',
            days: const <int>[DateTime.tuesday],
            period: EventPeriod.afternoon,
            afternoonTimeIn: const ScheduleTime(hour: 11, minute: 0),
            afternoonTimeOut: const ScheduleTime(hour: 15, minute: 0),
          ),
          contains('12:00 PM'),
        );

        // Whole Day requires BOTH morning and afternoon Time In/Out.
        expect(
          EventSchedule.validateFields(
            title: 'Foundation Day',
            days: const <int>[DateTime.wednesday],
            period: EventPeriod.wholeDay,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
          ),
          contains('Afternoon Time In and Time Out'),
        );

        // Evening Time In must be 5:00 PM+ and not before Afternoon Time Out.
        expect(
          EventSchedule.validateFields(
            title: 'Foundation Day',
            days: const <int>[DateTime.wednesday],
            period: EventPeriod.wholeDay,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
            afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
            afternoonTimeOut: const ScheduleTime(hour: 17, minute: 0),
            eveningTimeIn: const ScheduleTime(hour: 16, minute: 30),
          ),
          contains('5:00 PM'),
        );

        expect(
          EventSchedule.validateFields(
            title: 'Foundation Day',
            days: const <int>[DateTime.wednesday],
            period: EventPeriod.wholeDay,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
            afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
            afternoonTimeOut: const ScheduleTime(hour: 18, minute: 30),
            eveningTimeIn: const ScheduleTime(hour: 18, minute: 0),
          ),
          contains('before Afternoon Time Out'),
        );

        // Valid Whole Day with Morning In/Out + Afternoon In/Out + Optional Evening Time In.
        expect(
          EventSchedule.validateFields(
            title: 'Foundation Day',
            days: const <int>[DateTime.monday, DateTime.friday],
            period: EventPeriod.wholeDay,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
            afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
            afternoonTimeOut: const ScheduleTime(hour: 17, minute: 0),
            eveningTimeIn: const ScheduleTime(hour: 18, minute: 0),
          ),
          isNull,
        );
      },
    );

    test(
      'Whole Day + optional Evening cancels overlapping Morning/Afternoon/Evening classes while keeping lunch gap & other days active',
      () {
        final morningAndWed = SubjectSchedule(
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
            // Lunch gap 12:00 PM - 1:00 PM sits cleanly between Morning and Afternoon.
            SessionType.onlineTime: SessionSchedule(
              type: SessionType.onlineTime,
              days: const <int>[DateTime.monday],
              timeIn: const ScheduleTime(hour: 12, minute: 0),
              timeOut: const ScheduleTime(hour: 13, minute: 0),
            ),
            SessionType.laboratory: SessionSchedule(
              type: SessionType.laboratory,
              days: const <int>[DateTime.monday],
              timeIn: const ScheduleTime(hour: 14, minute: 0),
              timeOut: const ScheduleTime(hour: 16, minute: 0),
            ),
          },
        );

        final eveningClass = SubjectSchedule(
          id: 'night-1',
          subject: 'Ethics',
          section: 'B',
          reminderMinutesBefore: 10,
          sessions: <SessionType, SessionSchedule>{
            SessionType.lecture: SessionSchedule(
              type: SessionType.lecture,
              days: const <int>[DateTime.monday],
              timeIn: const ScheduleTime(hour: 18, minute: 30),
              timeOut: const ScheduleTime(hour: 20, minute: 0),
            ),
          },
        );

        final wholeDayEvent = EventSchedule(
          id: 'evt-wd',
          title: 'Intramurals',
          days: const <int>[DateTime.monday],
          period: EventPeriod.wholeDay,
          morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
          morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
          afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
          afternoonTimeOut: const ScheduleTime(hour: 17, minute: 0),
          eveningTimeIn: const ScheduleTime(hour: 18, minute: 0),
        );

        final payloads = buildAlarmPayloads(
          <SubjectSchedule>[morningAndWed, eveningClass],
          events: <EventSchedule>[wholeDayEvent],
        );

        // Class alarms kept: Wed Lecture + Mon Lunch Online Time (2).
        // Event alarms created: Morning + Afternoon + Evening (3).
        expect(payloads.length, 5);
        expect(payloads.map((p) => p.id).toSet().length, 5);

        final eventAlarms =
            payloads.where((p) => p.sessionLabel == 'Event').toList();
        expect(eventAlarms.length, 3);
        expect(
          eventAlarms.any(
            (a) =>
                a.title == 'Classes Canceled · Intramurals (Morning)' &&
                a.body.contains('Calculus 1 (Sec A · Lecture)'),
          ),
          isTrue,
        );
        expect(
          eventAlarms.any(
            (a) =>
                a.title == 'Classes Canceled · Intramurals (Afternoon)' &&
                a.body.contains('Calculus 1 (Sec A · Lab)'),
          ),
          isTrue,
        );
        expect(
          eventAlarms.any(
            (a) =>
                a.title == 'Classes Canceled · Intramurals (Evening)' &&
                a.body.contains('Ethics (Sec B · Lecture)'),
          ),
          isTrue,
        );
      },
    );
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

  group('SQLite persistence, v1->v2 migration, History & Schedule Protection', () {
    test('migrates legacy v1 "both" events losslessly to v2 Whole Day', () async {
      final tempDir = await Directory.systemTemp.createTemp('seireminds_mig_');
      final dbPath = p.join(tempDir.path, 'legacy.db');

      try {
        // Create legacy v1 schema with a 'both' event row.
        final legacyDb = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 1,
            singleInstance: false,
            onCreate: (db, version) async {
              await db.execute('''
                CREATE TABLE schedules (
                  id TEXT PRIMARY KEY,
                  subject TEXT NOT NULL,
                  section TEXT NOT NULL,
                  reminder_minutes_before INTEGER NOT NULL,
                  reminder_enabled INTEGER NOT NULL,
                  updated_at TEXT NOT NULL
                )
              ''');
              await db.execute('''
                CREATE TABLE schedule_sessions (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  schedule_id TEXT NOT NULL,
                  session_type TEXT NOT NULL,
                  days_csv TEXT NOT NULL,
                  time_in_minutes INTEGER NOT NULL,
                  time_out_minutes INTEGER NOT NULL
                )
              ''');
              await db.execute('''
                CREATE TABLE events (
                  id TEXT PRIMARY KEY,
                  title TEXT NOT NULL,
                  days_csv TEXT NOT NULL,
                  period TEXT NOT NULL,
                  time_in_minutes INTEGER NOT NULL,
                  time_out_minutes INTEGER NOT NULL,
                  reminder_minutes_before INTEGER NOT NULL,
                  reminder_enabled INTEGER NOT NULL,
                  updated_at TEXT NOT NULL
                )
              ''');
              await db.execute('''
                CREATE TABLE history_entries (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  action TEXT NOT NULL,
                  entity_type TEXT NOT NULL,
                  entity_id TEXT NOT NULL,
                  title TEXT NOT NULL,
                  details TEXT NOT NULL,
                  snapshot_json TEXT,
                  is_archived INTEGER NOT NULL DEFAULT 0,
                  created_at TEXT NOT NULL
                )
              ''');
            },
          ),
        );

        await legacyDb.insert('events', <String, Object?>{
          'id': 'legacy-both',
          'title': 'Legacy Whole Day',
          'days_csv': '1,3',
          'period': 'both',
          'time_in_minutes': 8 * 60,
          'time_out_minutes': 17 * 60,
          'reminder_minutes_before': 10,
          'reminder_enabled': 1,
          'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        });
        await legacyDb.close();

        // Reopen via SqliteScheduleDatabase (v2) -> triggers onUpgrade.
        final upgraded = SqliteScheduleDatabase(
          databaseFactory: databaseFactoryFfi,
          databasePath: dbPath,
        );
        try {
          final events = await upgraded.loadEvents();
          expect(events.length, 1);
          final migrated = events.first;
          expect(migrated.period, EventPeriod.wholeDay);
          expect(migrated.morningTimeIn, const ScheduleTime(hour: 8, minute: 0));
          expect(migrated.morningTimeOut, const ScheduleTime(hour: 12, minute: 0));
          expect(migrated.afternoonTimeIn, const ScheduleTime(hour: 12, minute: 0));
          expect(migrated.afternoonTimeOut, const ScheduleTime(hour: 17, minute: 0));
          expect(migrated.eveningTimeIn, isNull);
        } finally {
          await upgraded.close();
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'soft clear preserves history, permanent clear keeps schedules, and deletion guard works',
      () async {
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

          final afterSoftClear = await repo.clearHistory();
          expect(afterSoftClear.activeHistory, isEmpty);
          expect(afterSoftClear.archivedHistory.length, 1);
          expect(afterSoftClear.schedules.length, 1);

          final afterRestore = await repo.restoreArchivedHistory();
          expect(afterRestore.activeHistory.length, 1);
          expect(afterRestore.archivedHistory, isEmpty);

          await expectLater(
            repo.permanentlyClearHistory(confirmedPermanent: false),
            throwsA(isA<ScheduleProtectionException>()),
          );

          final afterPermClear = await repo.permanentlyClearHistory(
            confirmedPermanent: true,
          );
          expect(afterPermClear.activeHistory, isEmpty);
          expect(afterPermClear.archivedHistory, isEmpty);
          expect(afterPermClear.schedules.length, 1);

          await expectLater(
            repo.deleteSchedule('sched-1', confirmedFromSchedule: false),
            throwsA(isA<ScheduleProtectionException>()),
          );

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
      },
    );

    test('saves Whole Day + optional Evening event in SQLite and keeps data if alarm sync fails', () async {
      final db = _createInMemoryDb();
      final alarmService = _FakeAlarmService()..shouldFailSync = true;
      final repo = ScheduleRepository(
        database: db,
        alarmService: alarmService,
      );

      try {
        final event = EventSchedule(
          id: 'evt-wd-sqlite',
          title: 'Campus Week',
          days: const <int>[DateTime.monday, DateTime.thursday],
          period: EventPeriod.wholeDay,
          morningTimeIn: const ScheduleTime(hour: 7, minute: 30),
          morningTimeOut: const ScheduleTime(hour: 11, minute: 30),
          afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
          afternoonTimeOut: const ScheduleTime(hour: 17, minute: 0),
          eveningTimeIn: const ScheduleTime(hour: 18, minute: 30),
        );

        final res = await repo.saveEvent(event, isNew: true);
        expect(res.events.length, 1);
        expect(res.events.first.period, EventPeriod.wholeDay);
        expect(
          res.events.first.eveningTimeIn,
          const ScheduleTime(hour: 18, minute: 30),
        );
        expect(res.alarmSyncWarning, contains('Saved in SQLite'));
      } finally {
        await repo.close();
      }
    });
  });
}
