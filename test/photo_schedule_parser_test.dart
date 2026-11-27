import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seireminds/data/repositories/schedule_repository.dart';
import 'package:seireminds/data/services/alarm_service.dart';
import 'package:seireminds/data/services/schedule_ocr_service.dart';
import 'package:seireminds/data/services/schedule_photo_parser.dart';
import 'package:seireminds/data/services/sqlite_database_service.dart';
import 'package:seireminds/domain/models/schedule_models.dart';
import 'package:seireminds/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeOcrService implements ScheduleOcrService {
  _FakeOcrService(this.result);
  final ScheduleOcrResult? result;

  @override
  Future<ScheduleOcrResult?> pickAndRecognize(PhotoImportSource source) async {
    return result;
  }
}

class _CapturingAlarmService implements AlarmService {
  List<ScheduledAlarmPayload> syncedAlarms = const <ScheduledAlarmPayload>[];
  int canvasNotifications = 0;

  @override
  Future<void> syncAlarms(List<ScheduledAlarmPayload> alarms) async {
    syncedAlarms = List<ScheduledAlarmPayload>.of(alarms);
  }

  @override
  Future<void> showCanvasNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    canvasNotifications++;
  }

  @override
  Future<AlarmPermissionStatus> getPermissionStatus() async =>
      const AlarmPermissionStatus.unsupported();

  @override
  Future<void> openAlarmChannelSettings() async {}

  @override
  Future<void> openBatteryOptimizationSettings() async {}

  @override
  Future<void> openCanvasChannelSettings() async {}

  @override
  Future<void> openDndSettings() async {}

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> openFullScreenIntentSettings() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> stopActiveAlarm() async {}

  @override
  Future<void> triggerTestAlarm() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('SchedulePhotoParser', () {
    test(
      'reconstructs visual COR table rows from bounding boxes and extracts separate code, full name, section, days, times, room, and teacher',
      () {
        const lines = <OcrTextLine>[
          // Row 1 (y ~ 100)
          OcrTextLine(text: 'CS 101', left: 10, top: 92, right: 80, bottom: 112),
          OcrTextLine(
            text: 'Data Structures & Algorithms',
            left: 120,
            top: 94,
            right: 360,
            bottom: 114,
          ),
          OcrTextLine(text: 'Sec B', left: 400, top: 93, right: 455, bottom: 113),
          OcrTextLine(text: 'MWF', left: 495, top: 95, right: 545, bottom: 115),
          OcrTextLine(
            text: '8:00-9:30 AM',
            left: 585,
            top: 94,
            right: 715,
            bottom: 114,
          ),
          OcrTextLine(
            text: 'Room 304',
            left: 755,
            top: 95,
            right: 845,
            bottom: 115,
          ),
          OcrTextLine(
            text: 'Prof. Maria Santos',
            left: 885,
            top: 94,
            right: 1050,
            bottom: 114,
          ),
          // Row 2 (y ~ 160) — Lab for same CS 101 Sec B should merge into one subject!
          OcrTextLine(text: 'CS 101', left: 10, top: 152, right: 80, bottom: 172),
          OcrTextLine(
            text: 'Data Structures Lab',
            left: 120,
            top: 153,
            right: 320,
            bottom: 173,
          ),
          OcrTextLine(text: 'Sec B', left: 400, top: 153, right: 455, bottom: 173),
          OcrTextLine(text: 'TTh', left: 495, top: 154, right: 540, bottom: 174),
          OcrTextLine(
            text: '1:30 - 3:00 PM',
            left: 585,
            top: 153,
            right: 720,
            bottom: 173,
          ),
          OcrTextLine(
            text: 'Comp Lab 2',
            left: 755,
            top: 154,
            right: 865,
            bottom: 174,
          ),
          // Row 3 (y ~ 220) — Online class with comma-formatted instructor name
          OcrTextLine(text: 'MATH 2', left: 10, top: 212, right: 85, bottom: 232),
          OcrTextLine(
            text: 'Discrete Mathematics (Online)',
            left: 120,
            top: 213,
            right: 380,
            bottom: 233,
          ),
          OcrTextLine(text: 'C', left: 410, top: 212, right: 425, bottom: 232),
          OcrTextLine(text: 'Sat', left: 495, top: 213, right: 530, bottom: 233),
          OcrTextLine(
            text: '10:30 - 12:00 PM',
            left: 585,
            top: 214,
            right: 740,
            bottom: 234,
          ),
          OcrTextLine(
            text: 'Dela Cruz, Juan',
            left: 885,
            top: 213,
            right: 1020,
            bottom: 233,
          ),
        ];

        final drafts = SchedulePhotoParser.parseOcrLines(lines);
        expect(drafts.length, 2);

        final cs = drafts.first;
        expect(cs.subjectCode, 'CS 101');
        expect(cs.subject, 'Data Structures & Algorithms');
        expect(cs.section, 'B');
        expect(cs.classroom, 'Room 304');
        expect(cs.teacherName, 'Prof. Maria Santos');
        expect(cs.sessions.length, 2);
        expect(
          cs.sessions[SessionType.lecture]!.days,
          <int>[DateTime.monday, DateTime.wednesday, DateTime.friday],
        );
        expect(
          cs.sessions[SessionType.lecture]!.timeIn,
          const ScheduleTime(hour: 8, minute: 0),
        );
        expect(
          cs.sessions[SessionType.lecture]!.timeOut,
          const ScheduleTime(hour: 9, minute: 30),
        );
        expect(
          cs.sessions[SessionType.laboratory]!.days,
          <int>[DateTime.tuesday, DateTime.thursday],
        );
        expect(
          cs.sessions[SessionType.laboratory]!.timeIn,
          const ScheduleTime(hour: 13, minute: 30),
        );
        expect(
          cs.sessions[SessionType.laboratory]!.timeOut,
          const ScheduleTime(hour: 15, minute: 0),
        );

        final math = drafts[1];
        expect(math.subjectCode, 'MATH 2');
        expect(math.subject, 'Discrete Mathematics');
        expect(math.section, 'C');
        expect(math.teacherName, 'Dela Cruz, Juan');
        expect(math.sessions.keys, contains(SessionType.onlineTime));
        expect(math.sessions[SessionType.onlineTime]!.days, <int>[DateTime.saturday]);
        expect(
          math.sessions[SessionType.onlineTime]!.timeIn,
          const ScheduleTime(hour: 10, minute: 30),
        );
        expect(
          math.sessions[SessionType.onlineTime]!.timeOut,
          const ScheduleTime(hour: 12, minute: 0),
        );
      },
    );

    test('parses multi-line stacked cards and school-hour heuristic times', () {
      const text = '''
Subject Code | Descriptive Title | Time & Day | Room
DSA | Data Structures | Sec A
M-F 1:00 - 2:30 | Rm 208
Engr. Noel Reyes
''';
      final drafts = SchedulePhotoParser.parseRawText(text);
      expect(drafts.length, 1);
      final d = drafts.first;
      expect(d.subjectCode, 'DSA');
      expect(d.subject, 'Data Structures');
      expect(d.section, 'A');
      expect(d.classroom, 'Rm 208');
      expect(d.teacherName, 'Engr. Noel Reyes');
      expect(
        d.sessions[SessionType.lecture]!.days,
        <int>[1, 2, 3, 4, 5],
      );
      expect(
        d.sessions[SessionType.lecture]!.timeIn,
        const ScheduleTime(hour: 13, minute: 0),
      );
      expect(
        d.sessions[SessionType.lecture]!.timeOut,
        const ScheduleTime(hour: 14, minute: 30),
      );
    });
  });

  testWidgets(
    'Imports parsed photo schedule into SQLite and syncs class alarms without triggering Canvas pop-ups',
    (WidgetTester tester) async {
      final alarmService = _CapturingAlarmService();
      final repo = ScheduleRepository(
        database: SqliteScheduleDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: inMemoryDatabasePath,
        ),
        alarmService: alarmService,
      );
      addTearDown(repo.close);

      final ocr = _FakeOcrService(
        const ScheduleOcrResult(
          rawText:
              'CS 201 | Operating Systems | Sec A | MWF | 9:00 AM - 10:30 AM | Room 402 | Prof. Elena Cruz',
          lines: <OcrTextLine>[],
        ),
      );

      await tester.pumpWidget(
        SeiRemindsApp(
          repository: repo,
          ocrService: ocr,
          initialWeekday: DateTime.monday,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_photo_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_pick_gallery_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('parsed_draft_card_0')), findsOneWidget);
      expect(find.text('CS 201'), findsOneWidget);
      expect(find.text('Operating Systems'), findsOneWidget);
      expect(find.text('Room 402'), findsOneWidget);
      expect(find.text('Prof. Elena Cruz'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_photo_import_button')));
      await tester.pumpAndSettle();

      // Back on Monday timetable: separate Acronym, Full Name, Classroom, and Teacher displayed.
      expect(find.text('CS 201'), findsOneWidget);
      expect(find.text('Operating Systems'), findsOneWidget);
      expect(find.text('Room 402'), findsOneWidget);
      expect(find.text('Prof. Elena Cruz'), findsOneWidget);

      // Class alarms synced for MWF (3 alarms), zero Canvas pop-ups mixed in.
      expect(alarmService.syncedAlarms.length, 3);
      expect(alarmService.syncedAlarms.first.title, 'CS 201 · Operating Systems · Sec A');
      expect(alarmService.syncedAlarms.first.body, contains('Room 402'));
      expect(alarmService.syncedAlarms.first.body, contains('Prof. Elena Cruz'));
      expect(alarmService.canvasNotifications, 0);
    },
  );
}
