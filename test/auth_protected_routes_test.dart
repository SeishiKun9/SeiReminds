import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seireminds/data/repositories/canvas_token_repository.dart';
import 'package:seireminds/data/repositories/schedule_repository.dart';
import 'package:seireminds/data/services/alarm_service.dart';
import 'package:seireminds/data/services/auth_service.dart';
import 'package:seireminds/data/services/canvas_api_client.dart';
import 'package:seireminds/data/services/canvas_secure_storage.dart';
import 'package:seireminds/data/services/sqlite_database_service.dart';
import 'package:seireminds/domain/models/schedule_models.dart';
import 'package:seireminds/main.dart';
import 'package:seireminds/ui/core/app_routes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeAuthService implements AuthService {
  _FakeAuthService({AuthSessionUser? initialUser}) : _user = initialUser;

  final StreamController<AuthSessionUser?> _controller =
      StreamController<AuthSessionUser?>.broadcast();
  AuthSessionUser? _user;
  int resendCalls = 0;
  String? lastResendEmail;
  bool failNextResend = false;

  @override
  AuthSessionUser? get currentUser => _user;

  @override
  Stream<AuthSessionUser?> get onAuthStateChange => _controller.stream;

  void emitRemoteSession(AuthSessionUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<AuthActionResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (email.trim() == 'student@hnu.edu.ph' && password == 'secret123') {
      _user = const AuthSessionUser(
        id: 'user-1',
        email: 'student@hnu.edu.ph',
        displayName: 'Seishi Student',
      );
      _controller.add(_user);
      return AuthActionResult(
        succeeded: true,
        message: 'Signed in.',
        user: _user,
      );
    }
    return const AuthActionResult(
      succeeded: false,
      message: 'Invalid login credentials.',
    );
  }

  @override
  Future<AuthActionResult> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return const AuthActionResult(
      succeeded: true,
      requiresEmailConfirmation: true,
      message:
          'Account created! Check your email to confirm your address before signing in.',
    );
  }

  @override
  Future<AuthActionResult> resendSignUpConfirmation(String email) async {
    if (failNextResend) {
      failNextResend = false;
      return const AuthActionResult(
        succeeded: false,
        message: 'Wait 60 seconds before requesting another email.',
      );
    }
    resendCalls++;
    lastResendEmail = email;
    return const AuthActionResult(
      succeeded: true,
      message: 'Confirmation email resent. Check your inbox or spam folder.',
    );
  }

  @override
  Future<AuthActionResult> sendPasswordResetEmail(String email) async {
    return const AuthActionResult(
      succeeded: true,
      message: 'Password reset link sent. Check your email inbox.',
    );
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}

class _NoopAlarmService implements AlarmService {
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
  Future<void> syncAlarms(List<ScheduledAlarmPayload> alarms) async {}

  @override
  Future<void> showCanvasNotification({
    required int id,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> triggerTestAlarm() async {}
}

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> _map = <String, String>{};

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;
}

CanvasTokenRepository _createTestCanvasRepo() {
  return CanvasTokenRepository(
    store: _MemorySecureStore(),
    apiClient: CanvasApiClient(
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    ),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('AppRoutes offline-first & protected Canvas route guard', () {
    test('allows non-Canvas routes offline and protects /settings/canvas when signed out', () {
      expect(
        AppRoutes.resolveAuthorizedRoute(AppRoutes.home, isAuthenticated: false),
        AppRoutes.home,
      );
      expect(
        AppRoutes.resolveAuthorizedRoute(
          AppRoutes.settings,
          isAuthenticated: false,
        ),
        AppRoutes.settings,
      );
      expect(
        AppRoutes.resolveAuthorizedRoute(
          AppRoutes.canvasSettings,
          isAuthenticated: false,
        ),
        AppRoutes.login,
      );
      expect(
        AppRoutes.resolveAuthorizedRoute('/unknown', isAuthenticated: false),
        AppRoutes.home,
      );
      expect(
        AppRoutes.resolveAuthorizedRoute(
          AppRoutes.signUp,
          isAuthenticated: false,
        ),
        AppRoutes.signUp,
      );
    });

    test('redirects authenticated users away from /login and /signup to /', () {
      expect(
        AppRoutes.resolveAuthorizedRoute(AppRoutes.login, isAuthenticated: true),
        AppRoutes.home,
      );
      expect(
        AppRoutes.resolveAuthorizedRoute(
          AppRoutes.signUp,
          isAuthenticated: true,
        ),
        AppRoutes.home,
      );
      expect(
        AppRoutes.resolveAuthorizedRoute(
          AppRoutes.settings,
          isAuthenticated: true,
        ),
        AppRoutes.settings,
      );
      expect(
        AppRoutes.resolveAuthorizedRoute(
          AppRoutes.canvasSettings,
          isAuthenticated: true,
        ),
        AppRoutes.canvasSettings,
      );
    });
  });

  group('Supabase Auth, offline-first non-Canvas access & protected Canvas flow', () {
    testWidgets(
      'non-Canvas screens work offline while signed out, Canvas Settings requires sign-in, and sign-out returns safely to offline timetable',
      (WidgetTester tester) async {
        final authService = _FakeAuthService();
        final repo = ScheduleRepository(
          database: SqliteScheduleDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: inMemoryDatabasePath,
          ),
          alarmService: _NoopAlarmService(),
        );
        final canvasRepo = _createTestCanvasRepo();
        addTearDown(() async {
          authService.dispose();
          await repo.close();
        });

        // Boot signed out -> offline Home timetable opens immediately without login wall.
        await tester.pumpWidget(
          SeiRemindsApp(
            repository: repo,
            canvasRepository: canvasRepo,
            authService: authService,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
        expect(find.byKey(const Key('auth_sign_in_button')), findsNothing);

        // Settings & History works completely offline when signed out.
        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        expect(find.text('Settings & History'), findsOneWidget);
        expect(find.text('Offline Mode'), findsOneWidget);
        expect(
          find.byKey(const Key('go_to_sign_in_from_settings')),
          findsOneWidget,
        );

        // Tapping Canvas Settings while signed out redirects to LoginPage.
        final settingsScrollable = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        final canvasTile = find.byKey(const Key('open_canvas_settings_tile'));
        await tester.scrollUntilVisible(
          canvasTile,
          200,
          scrollable: settingsScrollable,
        );
        await tester.ensureVisible(canvasTile);
        await tester.pumpAndSettle();
        await tester.tap(canvasTile);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth_sign_in_button')), findsOneWidget);
        expect(find.byKey(const Key('continue_offline_button')), findsOneWidget);
        expect(find.text('Canvas Settings'), findsNothing);

        // Wrong credentials keep Canvas blocked on LoginPage.
        await tester.enterText(
          find.byKey(const Key('auth_email_field')),
          'student@hnu.edu.ph',
        );
        await tester.enterText(
          find.byKey(const Key('auth_password_field')),
          'wrongpass',
        );
        await tester.tap(find.byKey(const Key('auth_sign_in_button')));
        await tester.pumpAndSettle();

        expect(find.text('Invalid login credentials.'), findsOneWidget);
        expect(find.text('Canvas Settings'), findsNothing);

        // Valid credentials unlock the pending Canvas Settings route!
        await tester.enterText(
          find.byKey(const Key('auth_password_field')),
          'secret123',
        );
        await tester.tap(find.byKey(const Key('auth_sign_in_button')));
        await tester.pumpAndSettle();

        expect(find.text('Canvas Settings'), findsOneWidget);

        // Navigate back to Home -> open Settings -> shows signed-in user and Sign Out.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        expect(find.text('Seishi Student'), findsOneWidget);
        expect(find.text('student@hnu.edu.ph'), findsOneWidget);

        // Tap Sign Out -> returns cleanly to offline Home timetable.
        await tester.tap(find.byKey(const Key('sign_out_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
        expect(find.text('Canvas Settings'), findsNothing);
      },
    );

    testWidgets(
      'kicks user off protected /settings/canvas immediately when session expires while keeping offline timetable usable',
      (WidgetTester tester) async {
        final authService = _FakeAuthService(
          initialUser: const AuthSessionUser(
            id: 'user-1',
            email: 'student@hnu.edu.ph',
            displayName: 'Seishi Student',
          ),
        );
        final repo = ScheduleRepository(
          database: SqliteScheduleDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: inMemoryDatabasePath,
          ),
          alarmService: _NoopAlarmService(),
        );
        final canvasRepo = _createTestCanvasRepo();
        addTearDown(() async {
          authService.dispose();
          await repo.close();
        });

        await tester.pumpWidget(
          SeiRemindsApp(
            repository: repo,
            canvasRepository: canvasRepo,
            authService: authService,
            initialRoute: AppRoutes.canvasSettings,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Canvas Settings'), findsOneWidget);

        // Simulate remote session invalidation/sign-out event.
        authService.emitRemoteSession(null);
        await tester.pumpAndSettle();

        expect(find.text('Canvas Settings'), findsNothing);
        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
      },
    );

    testWidgets(
      'allows resending signup confirmation email up to 3 times and blocks further resends',
      (WidgetTester tester) async {
        final authService = _FakeAuthService();
        final repo = ScheduleRepository(
          database: SqliteScheduleDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: inMemoryDatabasePath,
          ),
          alarmService: _NoopAlarmService(),
        );
        addTearDown(() async {
          authService.dispose();
          await repo.close();
        });

        await tester.pumpWidget(
          SeiRemindsApp(
            repository: repo,
            authService: authService,
            initialRoute: AppRoutes.signUp,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('auth_resend_confirmation_button')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const Key('signup_email_field')),
          'newstudent@hnu.edu.ph',
        );
        await tester.enterText(
          find.byKey(const Key('signup_password_field')),
          'secret123',
        );
        await tester.enterText(
          find.byKey(const Key('signup_confirm_password_field')),
          'secret123',
        );
        await tester.tap(find.byKey(const Key('auth_sign_up_button')));
        await tester.pumpAndSettle();

        final resendButton = find.byKey(
          const Key('auth_resend_confirmation_button'),
        );
        expect(resendButton, findsOneWidget);
        expect(
          find.text('Resend Confirmation Email (3 left)'),
          findsOneWidget,
        );

        // Failed resend should not consume one of the 3 attempts.
        authService.failNextResend = true;
        await tester.ensureVisible(resendButton);
        await tester.tap(resendButton);
        await tester.pumpAndSettle();
        expect(authService.resendCalls, 0);
        expect(
          find.text('Wait 60 seconds before requesting another email.'),
          findsOneWidget,
        );
        expect(
          find.text('Resend Confirmation Email (3 left)'),
          findsOneWidget,
        );

        // Resend 1 -> 2 left.
        await tester.tap(resendButton);
        await tester.pumpAndSettle();
        expect(authService.resendCalls, 1);
        expect(authService.lastResendEmail, 'newstudent@hnu.edu.ph');
        expect(
          find.text('Resend Confirmation Email (2 left)'),
          findsOneWidget,
        );

        // Resend 2 -> 1 left.
        await tester.tap(resendButton);
        await tester.pumpAndSettle();
        expect(authService.resendCalls, 2);
        expect(
          find.text('Resend Confirmation Email (1 left)'),
          findsOneWidget,
        );

        // Resend 3 -> limit reached, button disabled.
        await tester.tap(resendButton);
        await tester.pumpAndSettle();
        expect(authService.resendCalls, 3);
        expect(find.text('Resend Limit Reached (0/3)'), findsOneWidget);

        // Tapping disabled button or re-submitting same email must not reset or exceed 3.
        await tester.tap(resendButton);
        await tester.pumpAndSettle();
        expect(authService.resendCalls, 3);

        await tester.ensureVisible(
          find.byKey(const Key('auth_sign_up_button')),
        );
        await tester.tap(find.byKey(const Key('auth_sign_up_button')));
        await tester.pumpAndSettle();
        expect(find.text('Resend Limit Reached (0/3)'), findsOneWidget);
        expect(authService.resendCalls, 3);
      },
    );
  });
}
