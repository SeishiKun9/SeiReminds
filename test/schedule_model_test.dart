import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seireminds/data/repositories/schedule_repository.dart';
import 'package:seireminds/data/services/alarm_service.dart';
import 'package:seireminds/data/services/sqlite_database_service.dart';
import 'package:seireminds/domain/models/canvas_token_models.dart';
import 'package:seireminds/domain/models/schedule_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeAlarmService implements AlarmService {
  List<ScheduledAlarmPayload> lastSynced = const <ScheduledAlarmPayload>[];
  final List<({int id, String title, String body})> canvasNotifications =
      <({int id, String title, String body})>[];
  bool shouldFailSync = false;

  @override
  Future<void> syncAlarms(List<ScheduledAlarmPayload> alarms) async {
    if (shouldFailSync) {
      throw Exception('AlarmManager unavailable');
    }
    lastSynced = List<ScheduledAlarmPayload>.of(alarms);
  }

  @override
  Future<void> showCanvasNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    canvasNotifications.add((id: id, title: title, body: body));
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
  Future<void> openFullScreenIntentSettings() async {}

  @override
  Future<void> openAlarmChannelSettings() async {}

  @override
  Future<void> openCanvasChannelSettings() async {}

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

    test('groupedSubjectsForWeekday combines Online, Lecture, and Lab into one subject entry', () {
      final schedule = SubjectSchedule(
        id: 'subj-unified',
        subject: 'Data Structures',
        section: 'A',
        sessions: <SessionType, SessionSchedule>{
          SessionType.laboratory: SessionSchedule(
            type: SessionType.laboratory,
            days: const <int>[DateTime.monday, DateTime.wednesday],
            timeIn: const ScheduleTime(hour: 13, minute: 0),
            timeOut: const ScheduleTime(hour: 15, minute: 0),
          ),
          SessionType.onlineTime: SessionSchedule(
            type: SessionType.onlineTime,
            days: const <int>[DateTime.monday, DateTime.wednesday],
            timeIn: const ScheduleTime(hour: 8, minute: 0),
            timeOut: const ScheduleTime(hour: 9, minute: 30),
          ),
          SessionType.lecture: SessionSchedule(
            type: SessionType.lecture,
            days: const <int>[DateTime.monday, DateTime.wednesday],
            timeIn: const ScheduleTime(hour: 10, minute: 0),
            timeOut: const ScheduleTime(hour: 11, minute: 30),
          ),
        },
      );

      final grouped = groupedSubjectsForWeekday(
        <SubjectSchedule>[schedule],
        DateTime.monday,
      );
      expect(grouped.length, 1);
      expect(grouped.first.schedule.subject, 'Data Structures');
      expect(grouped.first.sessions.map((s) => s.type).toList(), <SessionType>[
        SessionType.onlineTime,
        SessionType.lecture,
        SessionType.laboratory,
      ]);
      expect(schedule.sharedDays, <int>[DateTime.monday, DateTime.wednesday]);
    });
  });

  group('EventSchedule Mon-Sat (Saturday Morning only) & cancellation overlap', () {
    test(
      'enforces Mon-Fri Morning/Afternoon/Whole Day and Saturday Morning only',
      () {
        expect(
          EventSchedule.validateFields(
            title: 'Sunday Event',
            days: const <int>[DateTime.sunday],
            period: EventPeriod.morning,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
          ),
          contains('Monday to Saturday'),
        );

        // Saturday Afternoon and Saturday Whole Day MUST be rejected.
        expect(
          EventSchedule.validateFields(
            title: 'Sat Seminar',
            days: const <int>[DateTime.saturday],
            period: EventPeriod.afternoon,
            afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
            afternoonTimeOut: const ScheduleTime(hour: 17, minute: 0),
          ),
          contains('Saturday events support Morning only'),
        );

        expect(
          EventSchedule.validateFields(
            title: 'Sat Whole Day',
            days: const <int>[DateTime.saturday],
            period: EventPeriod.wholeDay,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
            afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
            afternoonTimeOut: const ScheduleTime(hour: 17, minute: 0),
          ),
          contains('Saturday events support Morning only'),
        );

        // Saturday Morning IS allowed!
        expect(
          EventSchedule.validateFields(
            title: 'Saturday Assembly',
            days: const <int>[DateTime.saturday],
            period: EventPeriod.morning,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
          ),
          isNull,
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

        // Valid Mon-Fri Whole Day with Morning In/Out + Afternoon In/Out.
        expect(
          EventSchedule.validateFields(
            title: 'Foundation Day',
            days: const <int>[DateTime.monday, DateTime.friday],
            period: EventPeriod.wholeDay,
            morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
            morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
            afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
            afternoonTimeOut: const ScheduleTime(hour: 17, minute: 0),
          ),
          isNull,
        );
      },
    );

    test(
      'Whole Day and Saturday Morning events cancel overlapping classes while keeping lunch gap & other days active',
      () {
        final morningAndWed = SubjectSchedule(
          id: 'calc-1',
          subject: 'Calculus 1',
          section: 'A',
          reminderMinutesBefore: 10,
          sessions: <SessionType, SessionSchedule>{
            SessionType.lecture: SessionSchedule(
              type: SessionType.lecture,
              days: const <int>[DateTime.monday, DateTime.wednesday, DateTime.saturday],
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

        final wholeDayEvent = EventSchedule(
          id: 'evt-wd',
          title: 'Intramurals',
          days: const <int>[DateTime.monday],
          period: EventPeriod.wholeDay,
          morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
          morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
          afternoonTimeIn: const ScheduleTime(hour: 13, minute: 0),
          afternoonTimeOut: const ScheduleTime(hour: 17, minute: 0),
        );

        final saturdayMorningEvent = EventSchedule(
          id: 'evt-sat',
          title: 'Saturday Convocation',
          days: const <int>[DateTime.saturday],
          period: EventPeriod.morning,
          morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
          morningTimeOut: const ScheduleTime(hour: 12, minute: 0),
        );

        final payloads = buildAlarmPayloads(
          <SubjectSchedule>[morningAndWed],
          events: <EventSchedule>[wholeDayEvent, saturdayMorningEvent],
        );

        // Class alarms kept: Wed Lecture + Mon Lunch Online Time (2).
        // Event alarms created: Mon Morning + Mon Afternoon + Sat Morning (3).
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
                a.title == 'Classes Canceled · Saturday Convocation (Morning)' &&
                a.body.contains('Calculus 1 (Sec A · Lecture)'),
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

    test('announces "Your (online/lecture/laboratory) class is starting ..." with set minutes', () {
      final schedule = SubjectSchedule(
        id: 'announce-1',
        subject: 'Data Structures',
        section: 'A',
        reminderMinutesBefore: 15,
        sessions: <SessionType, SessionSchedule>{
          SessionType.onlineTime: SessionSchedule(
            type: SessionType.onlineTime,
            days: const <int>[DateTime.monday],
            timeIn: const ScheduleTime(hour: 8, minute: 0),
            timeOut: const ScheduleTime(hour: 9, minute: 30),
          ),
          SessionType.lecture: SessionSchedule(
            type: SessionType.lecture,
            days: const <int>[DateTime.monday],
            timeIn: const ScheduleTime(hour: 10, minute: 0),
            timeOut: const ScheduleTime(hour: 11, minute: 30),
          ),
          SessionType.laboratory: SessionSchedule(
            type: SessionType.laboratory,
            days: const <int>[DateTime.monday],
            timeIn: const ScheduleTime(hour: 13, minute: 0),
            timeOut: const ScheduleTime(hour: 15, minute: 0),
          ),
        },
      );

      final payloads = buildAlarmPayloads(<SubjectSchedule>[schedule]);
      expect(
        payloads.any((p) => p.body.startsWith('Your online class is starting in 15 minutes')),
        isTrue,
      );
      expect(
        payloads.any((p) => p.body.startsWith('Your lecture class is starting in 15 minutes')),
        isTrue,
      );
      expect(
        payloads.any((p) => p.body.startsWith('Your laboratory class is starting in 15 minutes')),
        isTrue,
      );

      final immediatePayloads = buildAlarmPayloads(<SubjectSchedule>[
        schedule.copyWith(reminderMinutesBefore: 0),
      ]);
      expect(
        immediatePayloads.any((p) => p.body.startsWith('Your lecture class is starting now')),
        isTrue,
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

    test('saves Whole Day event in SQLite and keeps data if alarm sync fails', () async {
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
        );

        final res = await repo.saveEvent(event, isNew: true);
        expect(res.events.length, 1);
        expect(res.events.first.period, EventPeriod.wholeDay);
        expect(res.alarmSyncWarning, contains('Saved in SQLite'));
      } finally {
        await repo.close();
      }
    });

    test('findNextUpcomingSession skips canceled sessions and detects in-progress class', () {
      final schedule = SubjectSchedule(
        id: 's1',
        subject: 'Algorithms',
        section: 'A',
        sessions: <SessionType, SessionSchedule>{
          SessionType.lecture: SessionSchedule(
            type: SessionType.lecture,
            days: const <int>[DateTime.monday],
            timeIn: const ScheduleTime(hour: 9, minute: 0),
            timeOut: const ScheduleTime(hour: 10, minute: 30),
          ),
          SessionType.laboratory: SessionSchedule(
            type: SessionType.laboratory,
            days: const <int>[DateTime.monday],
            timeIn: const ScheduleTime(hour: 13, minute: 0),
            timeOut: const ScheduleTime(hour: 15, minute: 0),
          ),
        },
      );
      final morningCancelEvent = EventSchedule(
        id: 'e1',
        title: 'Convocation',
        days: const <int>[DateTime.monday],
        period: EventPeriod.morning,
        morningTimeIn: const ScheduleTime(hour: 8, minute: 0),
        morningTimeOut: const ScheduleTime(hour: 11, minute: 0),
      );

      // Monday 8:30 AM -> Morning Lecture is canceled, so next up is 1:00 PM Lab.
      final next = findNextUpcomingSession(
        <SubjectSchedule>[schedule],
        <EventSchedule>[morningCancelEvent],
        now: DateTime(2026, 11, 23, 8, 30),
      );
      expect(next, isNotNull);
      expect(next!.item.session.type, SessionType.laboratory);
      expect(next.isInProgress, isFalse);
      expect(next.minutesUntilStart, 270);

      // Monday 1:30 PM -> Lab is in progress.
      final active = findNextUpcomingSession(
        <SubjectSchedule>[schedule],
        <EventSchedule>[morningCancelEvent],
        now: DateTime(2026, 11, 23, 13, 30),
      );
      expect(active, isNotNull);
      expect(active!.isInProgress, isTrue);
      expect(active.minutesUntilStart, 0);
    });

    test(
      'SQLite temporarily stores ONLY Canvas activities until deadline expires (never announcements) while protecting schedules',
      () async {
        var now = DateTime(2026, 11, 23, 10, 0);
        final db = _createInMemoryDb();
        final alarmService = _FakeAlarmService();
        final repo = ScheduleRepository(
          database: db,
          alarmService: alarmService,
          clock: () => now,
        );

        try {
          // Save an active schedule that MUST NEVER be deleted by activity cleanup.
          await repo.saveSchedule(
            SubjectSchedule(
              id: 'protected-sched',
              subject: 'Networks',
              section: 'A',
              sessions: <SessionType, SessionSchedule>{
                SessionType.lecture: SessionSchedule(
                  type: SessionType.lecture,
                  days: const <int>[DateTime.monday],
                  timeIn: const ScheduleTime(hour: 8, minute: 0),
                  timeOut: const ScheduleTime(hour: 9, minute: 30),
                ),
              },
            ),
            isNew: true,
          );

          final todayAnn = CanvasDailyItem(
            id: 'ann_100',
            kind: CanvasDailyItemKind.announcement,
            courseName: 'Networks',
            title: 'Quiz Today',
            message: 'Bring calculator.',
            postedAt: DateTime(2026, 11, 23, 9, 15).toUtc(),
            postedDate: localDateKey(now),
          );
          final activeDeadlineAct = CanvasDailyItem(
            id: 'act_deadline',
            kind: CanvasDailyItemKind.activity,
            courseName: 'Networks',
            title: 'Lab 4 Submission',
            message: 'Submit by Nov 25 5 PM.',
            postedAt: DateTime(2026, 11, 23, 8, 45).toUtc(),
            postedDate: localDateKey(now),
            dueAt: DateTime(2026, 11, 25, 17, 0).toUtc(),
            expiresAt: DateTime(2026, 11, 25, 17, 0).toUtc(),
          );
          final expiredAct = CanvasDailyItem(
            id: 'act_expired',
            kind: CanvasDailyItemKind.activity,
            courseName: 'Networks',
            title: 'Past Deadline Quiz',
            message: 'Already closed.',
            postedAt: DateTime(2026, 11, 22, 8, 0).toUtc(),
            postedDate: localDateKey(DateTime(2026, 11, 22)),
            dueAt: DateTime(2026, 11, 23, 9, 0).toUtc(),
            expiresAt: DateTime(2026, 11, 23, 9, 0).toUtc(),
          );
          final yesterdayAnn = CanvasDailyItem(
            id: 'ann_old',
            kind: CanvasDailyItemKind.announcement,
            courseName: 'Networks',
            title: 'Yesterday Notice',
            message: 'Must not be posted or notified today.',
            postedAt: DateTime(2026, 11, 22, 23, 55).toUtc(),
            postedDate: localDateKey(DateTime(2026, 11, 22)),
          );

          // First sync on Nov 23:
          // - todayAnn stays in memory ONLY (NEVER in SQLite!).
          // - activeDeadlineAct IS temporarily stored in SQLite until Nov 25 5 PM.
          // - expiredAct & yesterdayAnn are ignored completely.
          final firstSync = await repo.syncTodayCanvasItems(<CanvasDailyItem>[
            todayAnn,
            activeDeadlineAct,
            expiredAct,
            yesterdayAnn,
          ]);
          expect(firstSync.todayAnnouncements.length, 1);
          expect(firstSync.todayAnnouncements.first.id, 'ann_100');
          expect(firstSync.activeActivities.length, 1);
          expect(firstSync.activeActivities.first.id, 'act_deadline');
          expect(firstSync.newlyNotifiedCount, 2);
          expect(alarmService.canvasNotifications.length, 2);

          // Verify SQLite directly contains ONLY the activity (ZERO announcements!).
          final storedInSqlite = await db.loadActiveCanvasActivities(now: now);
          expect(storedInSqlite.length, 1);
          expect(storedInSqlite.first.id, 'act_deadline');
          expect(storedInSqlite.first.kind, CanvasDailyItemKind.activity);

          // Re-sync on Nov 23: does NOT re-notify already notified items.
          final secondSync = await repo.syncTodayCanvasItems(<CanvasDailyItem>[
            todayAnn,
            activeDeadlineAct,
          ]);
          expect(secondSync.newlyNotifiedCount, 0);
          expect(alarmService.canvasNotifications.length, 2);

          // On Nov 24 (BEFORE Nov 25 5 PM deadline): activity STILL stays in SQLite!
          now = DateTime(2026, 11, 24, 12, 0);
          final beforeDeadline = await repo.loadAllAndSync();
          expect(beforeDeadline.activeCanvasActivities.length, 1);
          expect(beforeDeadline.activeCanvasActivities.first.id, 'act_deadline');
          expect(beforeDeadline.schedules.length, 1);

          // On Nov 25 5:01 PM (AFTER deadline is up): activity is automatically deleted from SQLite,
          // and saved class schedules remain completely untouched!
          now = DateTime(2026, 11, 25, 17, 1);
          final afterDeadline = await repo.loadAllAndSync();
          expect(afterDeadline.activeCanvasActivities, isEmpty);
          expect(afterDeadline.lastDailyCleanupRemoved, 1);
          expect(afterDeadline.schedules.length, 1);

          // History view toggle persists in SQLite without deleting history or schedules.
          expect(afterDeadline.historyViewEnabled, isTrue);
          final hiddenSnap = await repo.setHistoryViewEnabled(false);
          expect(hiddenSnap.historyViewEnabled, isFalse);
          expect(hiddenSnap.activeHistory.length, 1);
          expect(hiddenSnap.schedules.length, 1);

          final reloadedSnap = await repo.loadAllAndSync();
          expect(reloadedSnap.historyViewEnabled, isFalse);
          expect(reloadedSnap.activeHistory.length, 1);

          final restoredSnap = await repo.setHistoryViewEnabled(true);
          expect(restoredSnap.historyViewEnabled, isTrue);
        } finally {
          await repo.close();
        }
      },
    );

    test(
      'AlarmPermissionStatus flags missing full-screen banner or DND bypass access',
      () {
        const missingPopUp = AlarmPermissionStatus(
          isAndroidSupported: true,
          notificationsGranted: true,
          exactAlarmsAllowed: true,
          fullScreenIntentAllowed: false,
          dndAccessGranted: true,
          ignoringBatteryOptimizations: true,
        );
        expect(missingPopUp.needsAttention, isTrue);

        const missingDnd = AlarmPermissionStatus(
          isAndroidSupported: true,
          notificationsGranted: true,
          exactAlarmsAllowed: true,
          fullScreenIntentAllowed: true,
          dndAccessGranted: false,
          ignoringBatteryOptimizations: true,
        );
        expect(missingDnd.needsAttention, isTrue);

        const ready = AlarmPermissionStatus(
          isAndroidSupported: true,
          notificationsGranted: true,
          exactAlarmsAllowed: true,
          fullScreenIntentAllowed: true,
          dndAccessGranted: true,
          ignoringBatteryOptimizations: true,
        );
        expect(ready.needsAttention, isFalse);
      },
    );

    test(
      'migrates SQLite v4 schedules losslessly to v5 with separate subject_code, classroom, and teacher_name columns',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('seireminds_v5_');
        final dbPath = p.join(tempDir.path, 'v4.db');
        try {
          final v4Db = await databaseFactoryFfi.openDatabase(
            dbPath,
            options: OpenDatabaseOptions(
              version: 4,
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
                    morning_time_in INTEGER,
                    morning_time_out INTEGER,
                    afternoon_time_in INTEGER,
                    afternoon_time_out INTEGER,
                    evening_time_in INTEGER,
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
                await db.execute('''
                  CREATE TABLE app_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                  )
                ''');
                await db.execute('''
                  CREATE TABLE canvas_activities (
                    item_id TEXT PRIMARY KEY,
                    course_name TEXT NOT NULL,
                    title TEXT NOT NULL,
                    message TEXT NOT NULL,
                    posted_at TEXT NOT NULL,
                    due_at TEXT,
                    expires_at TEXT NOT NULL,
                    notified INTEGER NOT NULL DEFAULT 0
                  )
                ''');
              },
            ),
          );
          await v4Db.insert('schedules', <String, Object?>{
            'id': 'legacy-sched',
            'subject': 'Linear Algebra',
            'section': 'A',
            'reminder_minutes_before': 10,
            'reminder_enabled': 1,
            'updated_at': DateTime.utc(2026, 2, 1).toIso8601String(),
          });
          await v4Db.insert('schedule_sessions', <String, Object?>{
            'schedule_id': 'legacy-sched',
            'session_type': 'lecture',
            'days_csv': '1,3',
            'time_in_minutes': 9 * 60,
            'time_out_minutes': 10 * 60 + 30,
          });
          await v4Db.close();

          final upgraded = SqliteScheduleDatabase(
            databaseFactory: databaseFactoryFfi,
            databasePath: dbPath,
          );
          try {
            final loaded = await upgraded.loadSchedules();
            expect(loaded.length, 1);
            expect(loaded.first.subject, 'Linear Algebra');
            expect(loaded.first.subjectCode, '');
            expect(loaded.first.classroom, '');
            expect(loaded.first.teacherName, '');

            await upgraded.upsertSchedule(
              SubjectSchedule(
                id: 'new-v5',
                subjectCode: 'CS 102',
                subject: 'Algorithms',
                section: 'C',
                classroom: 'Room 210',
                teacherName: 'Dr. Reyes',
                sessions: <SessionType, SessionSchedule>{
                  SessionType.lecture: SessionSchedule(
                    type: SessionType.lecture,
                    days: const <int>[DateTime.tuesday],
                    timeIn: const ScheduleTime(hour: 10, minute: 0),
                    timeOut: const ScheduleTime(hour: 11, minute: 30),
                  ),
                },
              ),
              isNew: true,
            );
            final all = await upgraded.loadSchedules();
            final added = all.firstWhere((s) => s.id == 'new-v5');
            expect(added.subjectCode, 'CS 102');
            expect(added.subject, 'Algorithms');
            expect(added.classroom, 'Room 210');
            expect(added.teacherName, 'Dr. Reyes');
            expect(added.displayTitle, 'CS 102 · Algorithms');
          } finally {
            await upgraded.close();
          }
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'Canvas test notification stays strictly a pop-up and never modifies class alarms',
      () async {
        final db = _createInMemoryDb();
        final alarmService = _FakeAlarmService();
        final repo = ScheduleRepository(database: db, alarmService: alarmService);
        try {
          await repo.triggerTestCanvasNotification();
          expect(alarmService.canvasNotifications.length, 1);
          expect(alarmService.canvasNotifications.first.title, contains('Canvas'));
          expect(alarmService.lastSynced, isEmpty);
        } finally {
          await repo.close();
        }
      },
    );
  });
}
