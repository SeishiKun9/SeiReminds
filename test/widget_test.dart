import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seireminds/data/repositories/schedule_repository.dart';
import 'package:seireminds/data/services/alarm_service.dart';
import 'package:seireminds/data/services/local_schedule_storage.dart';
import 'package:seireminds/domain/models/schedule_models.dart';
import 'package:seireminds/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  testWidgets(
    'Adds a class with 1-letter A-Z validation and Online Time + Lecture + Lab',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final alarmService = _RecordingAlarmService();
      final repository = ScheduleRepository(
        storage: SharedPreferencesScheduleStorage(prefs: prefs),
        alarmService: alarmService,
      );

      await tester.pumpWidget(
        SeiRemindsApp(
          repository: repository,
          initialWeekday: DateTime.monday,
        ),
      );
      await tester.pumpAndSettle();

      // Verify Mon-Sat tabs exist and Sunday is omitted.
      expect(find.text('SeiReminds'), findsOneWidget);
      expect(find.text('Beta · Offline'), findsOneWidget);
      for (final day in kSchoolWeekdays) {
        expect(find.byKey(Key('weekday_tab_$day')), findsOneWidget);
      }
      expect(find.text('Sun'), findsNothing);
      expect(find.text('No classes on Monday'), findsOneWidget);

      // Open Add Class form.
      await tester.tap(find.byKey(const Key('add_schedule_fab')));
      await tester.pumpAndSettle();

      // Step 1: Enter subject.
      await tester.enterText(
        find.byKey(const Key('subject_field')),
        'Data Structures',
      );
      await tester.pump();

      // Step 2: Validate single-letter A-Z constraint.
      await tester.enterText(find.byKey(const Key('section_field')), 'AB');
      await tester.pump();
      expect(find.text('Enter only 1 letter (A–Z)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('section_field')), '7');
      await tester.pump();
      expect(find.text('Section must be a letter from A to Z'), findsOneWidget);

      // Pick valid section B.
      await tester.enterText(find.byKey(const Key('section_field')), 'b');
      await tester.pump();
      expect(find.text('Enter only 1 letter (A–Z)'), findsNothing);

      // Step 3: Online Time is on by default; also enable Lecture & Laboratory.
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

      // Also put Lecture on Wednesday.
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

      // Save schedule.
      await tester.tap(find.byKey(const Key('save_schedule_button')));
      await tester.pumpAndSettle();

      // Monday shows all 3 sessions for Data Structures · Sec B.
      expect(find.text('Data Structures'), findsNWidgets(3));
      expect(find.text('Sec B'), findsNWidgets(3));
      expect(find.text('Online Time'), findsOneWidget);
      expect(find.text('Lecture'), findsOneWidget);
      expect(find.text('Laboratory'), findsOneWidget);

      // 4 alarms synced: Mon Online, Mon Lecture, Wed Lecture, Mon Laboratory.
      expect(alarmService.syncedAlarms.length, 4);

      // Switch to Wednesday tab -> shows Lecture session.
      await tester.tap(find.byKey(const Key('weekday_tab_${DateTime.wednesday}')));
      await tester.pumpAndSettle();
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('Data Structures'), findsOneWidget);
      expect(find.text('Lecture'), findsOneWidget);

      // Test Alarm setup sheet test & stop triggers.
      await tester.tap(find.byKey(const Key('alarm_setup_button')));
      await tester.pumpAndSettle();
      final testAlarmButton = find.text('Test Loud Alarm');
      await tester.ensureVisible(testAlarmButton);
      await tester.pumpAndSettle();
      await tester.tap(testAlarmButton);
      await tester.pump();
      expect(alarmService.testAlarmCalls, 1);

      final stopAlarmButton = find.text('Stop');
      await tester.ensureVisible(stopAlarmButton);
      await tester.pumpAndSettle();
      await tester.tap(stopAlarmButton);
      await tester.pump();
      expect(alarmService.stopAlarmCalls, 1);
    },
  );
}
