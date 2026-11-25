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
  Future<void> showCanvasNotification({
    required int id,
    required String title,
    required String body,
  }) async {}

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
  Future<void> openFullScreenIntentSettings() async {}

  @override
  Future<void> openAlarmChannelSettings() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  testWidgets(
    'Adds class, creates Whole Day + optional Evening event canceling sessions, and preserves schedules across History clears',
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
        SeiRemindsApp(
          repository: repository,
          initialWeekday: DateTime.monday,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SeiReminds'), findsOneWidget);
      expect(find.text('v1.1-beta.5'), findsOneWidget);
      expect(find.text('Beta · Offline'), findsNothing);
      for (final day in kSchoolWeekdays) {
        expect(find.byKey(Key('weekday_tab_$day')), findsOneWidget);
      }
      expect(find.text('Sun'), findsNothing);

      // 1. Add unified subject with generalized Mon & Wed days and Online + Lecture + Lab times.
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

      // Generalized Schedule Days selector (Mon already selected; also select Wed).
      final wedSharedDayChip = find.byKey(
        const Key('subject_day_${DateTime.wednesday}'),
      );
      await tester.scrollUntilVisible(
        wedSharedDayChip,
        200,
        scrollable: formScrollable,
      );
      await tester.tap(wedSharedDayChip);
      await tester.pumpAndSettle();

      final lectureToggle = find.byKey(const Key('session_toggle_lecture'));
      await tester.scrollUntilVisible(
        lectureToggle,
        300,
        scrollable: formScrollable,
      );
      await tester.tap(lectureToggle);
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

      // ONE unified subject card on Monday showing Online Time, Lecture, and Laboratory together!
      expect(find.text('Data Structures'), findsOneWidget);
      expect(find.text('Sec B'), findsOneWidget);
      expect(find.text('Online Time'), findsOneWidget);
      expect(find.text('Lecture'), findsOneWidget);
      expect(find.text('Laboratory'), findsOneWidget);
      // 3 sessions x 2 generalized days (Mon, Wed) = 6 alarms.
      expect(alarmService.syncedAlarms.length, 6);

      // Tapping the subject opens the detail sheet displaying Online, Lecture, and Laboratory together.
      await tester.tap(find.text('Data Structures'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('subject_detail_sheet')), findsOneWidget);
      expect(
        find.byKey(const Key('detail_session_online_time')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('detail_session_lecture')), findsOneWidget);
      expect(
        find.byKey(const Key('detail_session_laboratory')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // 2. Add Event: verify Saturday (Morning only), no Evening optional, and Whole Day on Mon.
      await tester.tap(find.byKey(const Key('add_event_button')));
      await tester.pumpAndSettle();

      expect(find.text('Whole Day'), findsOneWidget);
      expect(find.byKey(const Key('event_day_${DateTime.saturday}')), findsOneWidget);
      expect(find.byKey(const Key('event_evening_toggle')), findsNothing);
      expect(find.textContaining('Evening'), findsNothing);

      // Selecting Saturday locks coverage to Morning only.
      await tester.tap(find.byKey(const Key('event_day_${DateTime.saturday}')));
      await tester.pumpAndSettle();
      final afternoonChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('event_period_afternoon')),
      );
      final wholeDayChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('event_period_whole_day')),
      );
      expect(afternoonChip.onSelected, isNull);
      expect(wholeDayChip.onSelected, isNull);

      // Uncheck Saturday so Monday can use Whole Day.
      await tester.tap(find.byKey(const Key('event_day_${DateTime.saturday}')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('event_title_field')),
        'Foundation Day',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('event_period_whole_day')));
      await tester.pumpAndSettle();

      final eventScrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(find.byKey(const Key('event_morning_in')), findsOneWidget);
      expect(find.byKey(const Key('event_morning_out')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('event_afternoon_in')),
        200,
        scrollable: eventScrollable,
      );
      expect(find.byKey(const Key('event_afternoon_in')), findsOneWidget);
      expect(find.byKey(const Key('event_afternoon_out')), findsOneWidget);

      // Whole Day hits all 3 Monday sessions (Online 8-9:30, Lecture 10-11:30, Lab 1-3).
      final impactText = find.textContaining(
        'Will announce classes canceled (3 hit)',
      );
      await tester.scrollUntilVisible(
        impactText,
        250,
        scrollable: eventScrollable,
      );
      expect(impactText, findsOneWidget);

      await tester.tap(find.byKey(const Key('save_event_button')));
      await tester.pumpAndSettle();

      expect(find.text('CLASSES CANCELED · Foundation Day'), findsOneWidget);
      expect(find.text('CANCELED · Foundation Day'), findsNWidgets(3));

      // Synced alarms: Wed (Online, Lecture, Lab = 3) + Mon Whole Day (Morning, Afternoon = 2) = 5 total.
      expect(alarmService.syncedAlarms.length, 5);
      expect(
        alarmService.syncedAlarms.any(
          (a) => a.title == 'Classes Canceled · Foundation Day (Morning)',
        ),
        isTrue,
      );
      expect(
        alarmService.syncedAlarms.any(
          (a) => a.title == 'Classes Canceled · Foundation Day (Afternoon)',
        ),
        isTrue,
      );

      // 3. Open Settings -> History: verify daily cleanup card, soft clear preserves & permanent clear keeps schedules.
      await tester.tap(find.byKey(const Key('settings_button')));
      await tester.pumpAndSettle();
      // Let the previous SnackBar dismiss so it cannot obscure lower Settings tiles.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('daily_cleanup_card')), findsOneWidget);

      final settingsScrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      final historyToggle = find.byKey(const Key('toggle_history_view_switch'));
      await tester.scrollUntilVisible(
        historyToggle,
        200,
        scrollable: settingsScrollable,
      );
      await tester.drag(settingsScrollable, const Offset(0, -160));
      await tester.pumpAndSettle();

      // Toggle viewing history OFF -> history list and buttons hide without deleting records.
      await tester.ensureVisible(historyToggle);
      await tester.tap(historyToggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('soft_clear_history_button')), findsNothing);
      expect(find.text('Visible (2)'), findsNothing);

      // Toggle viewing history back ON -> history records reappear intact.
      await tester.ensureVisible(historyToggle);
      await tester.tap(historyToggle);
      await tester.pumpAndSettle();

      final softClearBtn = find.byKey(const Key('soft_clear_history_button'));
      await tester.scrollUntilVisible(
        softClearBtn,
        200,
        scrollable: settingsScrollable,
      );
      await tester.drag(settingsScrollable, const Offset(0, -160));
      await tester.pumpAndSettle();

      expect(find.text('Visible (2)'), findsOneWidget);
      expect(find.text('Preserved (0)'), findsOneWidget);

      await tester.ensureVisible(softClearBtn);
      await tester.tap(softClearBtn);
      await tester.pumpAndSettle();

      expect(find.text('Visible (0)'), findsOneWidget);
      expect(find.text('Preserved (2)'), findsOneWidget);

      final permClearBtn = find.byKey(
        const Key('permanent_clear_history_button'),
      );
      await tester.ensureVisible(permClearBtn);
      await tester.tap(permClearBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_permanent_clear_button')));
      await tester.pumpAndSettle();

      expect(find.text('Visible (0)'), findsOneWidget);
      expect(find.text('Preserved (0)'), findsOneWidget);

      // Return to timetable and verify unified schedule remains untouched.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Data Structures'), findsOneWidget);
      expect(find.text('CLASSES CANCELED · Foundation Day'), findsOneWidget);
    },
  );
}
