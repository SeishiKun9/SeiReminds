import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seireminds/data/repositories/schedule_repository.dart';
import 'package:seireminds/data/services/alarm_service.dart';
import 'package:seireminds/data/services/sqlite_database_service.dart';
import 'package:seireminds/domain/models/schedule_models.dart';
import 'package:seireminds/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RecordingAlarmService implements AlarmService {
  List<ScheduledAlarmPayload> syncedAlarms = const <ScheduledAlarmPayload>[];
  int testAlarmCalls = 0;
  int stopAlarmCalls = 0;

  @override
  Future<void> syncAlarms(List<ScheduledAlarmPayload> alarms) async {
    syncedAlarms = List<ScheduledAlarmPayload>.of(alarms);
  }

  @override
  Future<void> triggerTestAlarm() async {
    testAlarmCalls++;
  }

  @override
  Future<void> stopActiveAlarm() async {
    stopAlarmCalls++;
  }

  @override
  Future<AlarmPermissionStatus> getPermissionStatus() async {
    return const AlarmPermissionStatus(
      isAndroidSupported: true,
      notificationsGranted: true,
      exactAlarmsAllowed: true,
      dndAccessGranted: false,
      ignoringBatteryOptimizations: true,
    );
  }

  @override
  Future<void> openBatteryOptimizationSettings() async {}

  @override
  Future<void> openDndSettings() async {}

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  testWidgets(
    'Adds class, announces cancellation on overlapping event, and preserves schedules across History clears',
    (WidgetTester tester) async {
      final alarmService = _RecordingAlarmService();
      final repository = ScheduleRepository(
        database: SqliteScheduleDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: inMemoryDatabasePath,
        ),
        alarmService: alarmService,
      );
      addTearDown(repository.close);

      await tester.pumpWidget(
        SeiRemindsApp(repository: repository, initialWeekday: DateTime.monday),
      );
      await tester.pumpAndSettle();

      // Verify Mon-Sat tabs exist and Sunday is omitted.
      expect(find.text('SeiReminds'), findsOneWidget);
      expect(find.text('Beta · Offline'), findsOneWidget);
      for (final day in kSchoolWeekdays) {
        expect(find.byKey(Key('weekday_tab_$day')), findsOneWidget);
      }
      expect(find.text('Sun'), findsNothing);

      // 1. Add class with section 1-letter A-Z validation and Online + Lecture + Lab.
      await tester.tap(find.byKey(const Key('add_schedule_fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('subject_field')),
        'Data Structures',
      );
      await tester.pump();

      await tester.enterText(find.byKey(const Key('section_field')), 'AB');
      await tester.pump();
      expect(find.text('Enter only 1 letter (A–Z)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('section_field')), 'b');
      await tester.pump();
      expect(find.text('Enter only 1 letter (A–Z)'), findsNothing);

      final formScrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;

      final lectureToggle = find.byKey(const Key('session_toggle_lecture'));
      await tester.scrollUntilVisible(
        lectureToggle,
        300,
        scrollable: formScrollable,
      );
      await tester.tap(lectureToggle);
      await tester.pumpAndSettle();

      final wedLectureChip = find.byKey(
        const Key('day_lecture_${DateTime.wednesday}'),
      );
      await tester.scrollUntilVisible(
        wedLectureChip,
        200,
        scrollable: formScrollable,
      );
      await tester.tap(wedLectureChip);
      await tester.pumpAndSettle();

      final labToggle = find.byKey(const Key('session_toggle_laboratory'));
      await tester.scrollUntilVisible(
        labToggle,
        300,
        scrollable: formScrollable,
      );
      await tester.tap(labToggle);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save_schedule_button')));
      await tester.pumpAndSettle();

      expect(find.text('Data Structures'), findsNWidgets(3));
      expect(find.text('Sec B'), findsNWidgets(3));
      expect(alarmService.syncedAlarms.length, 4);

      // 2. Add Monday Morning Event (8:00 AM - 12:00 PM) that hits Online & Lecture.
      await tester.tap(find.byKey(const Key('add_event_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('event_title_field')),
        'Foundation Day',
      );
      await tester.pump();

      // Live preview detects the 2 overlapping Monday morning sessions.
      expect(
        find.textContaining('Will announce classes canceled (2 hit)'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('save_event_button')));
      await tester.pumpAndSettle();

      // Timetable announces canceled classes and marks overlapping sessions canceled.
      expect(find.text('CLASSES CANCELED · Foundation Day'), findsOneWidget);
      expect(find.text('CANCELED · Foundation Day'), findsNWidgets(2));

      // Synced alarms now include the Event cancellation alarm and suppress the 2 canceled morning sessions
      // (keeping Mon Lab + Wed Lecture + Mon Event = 3 total).
      expect(alarmService.syncedAlarms.length, 3);
      expect(
        alarmService.syncedAlarms.any(
          (a) => a.title == 'Classes Canceled · Foundation Day',
        ),
        isTrue,
      );

      // 3. Open Settings -> History: verify soft clear preserves records and permanent clear keeps schedules.
      await tester.tap(find.byKey(const Key('settings_button')));
      await tester.pumpAndSettle();

      expect(find.text('Visible (2)'), findsOneWidget);
      expect(find.text('Preserved (0)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('soft_clear_history_button')));
      await tester.pumpAndSettle();

      expect(find.text('Visible (0)'), findsOneWidget);
      expect(find.text('Preserved (2)'), findsOneWidget);

      // Permanently clear history after explicit confirmation.
      await tester.tap(find.byKey(const Key('permanent_clear_history_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_permanent_clear_button')));
      await tester.pumpAndSettle();

      expect(find.text('Visible (0)'), findsOneWidget);
      expect(find.text('Preserved (0)'), findsOneWidget);

      // Return to timetable and verify schedules were NEVER deleted.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Data Structures'), findsNWidgets(3));
      expect(find.text('CLASSES CANCELED · Foundation Day'), findsOneWidget);
    },
  );
}
