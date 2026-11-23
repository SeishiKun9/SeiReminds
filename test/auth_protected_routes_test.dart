import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seireminds/data/repositories/schedule_repository.dart';
import 'package:seireminds/data/services/alarm_service.dart';
import 'package:seireminds/data/services/auth_service.dart';
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
  Future<void> triggerTestAlarm() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('AppRoutes protected route guard', () {
    test('redirects unauthenticated users from protected routes to /login', () {
      expect(
        AppRoutes.resolveAuthorizedRoute(AppRoutes.home, isAuthenticated: false),
        AppRoutes.login,
      );
      expect(
        AppRoutes.resolveAuthorizedRoute(
          AppRoutes.settings,
          isAuthenticated: false,
        ),
        AppRoutes.login,
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
        AppRoutes.login,
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

  group('Supabase Auth & protected navigation flow', () {
    testWidgets(
      'blocks protected routes while signed out, signs in to timetable, and resets stack on sign out',
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

        // Attempt to open protected /settings while unauthenticated -> redirected to LoginPage.
        await tester.pumpWidget(
          SeiRemindsApp(
            repository: repo,
            authService: authService,
            initialRoute: AppRoutes.settings,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth_sign_in_button')), findsOneWidget);
        expect(find.text('Settings & History'), findsNothing);

        // Wrong credentials keep user blocked on LoginPage.
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
        expect(find.byKey(const Key('add_schedule_fab')), findsNothing);

        // Valid credentials unlock protected Home timetable.
        await tester.enterText(
          find.byKey(const Key('auth_password_field')),
          'secret123',
        );
        await tester.tap(find.byKey(const Key('auth_sign_in_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
        expect(find.byKey(const Key('auth_sign_in_button')), findsNothing);

        // Navigate to protected /settings -> shows signed-in user and Sign Out.
        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        expect(find.text('Seishi Student'), findsOneWidget);
        expect(find.text('student@hnu.edu.ph'), findsOneWidget);

        // Tap Sign Out -> clears stack back to LoginPage.
        await tester.tap(find.byKey(const Key('sign_out_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth_sign_in_button')), findsOneWidget);
        expect(find.text('Settings & History'), findsNothing);
      },
    );

    testWidgets(
      'kicks user back to /login immediately when session expires while on a protected route',
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
        addTearDown(() async {
          authService.dispose();
          await repo.close();
        });

        await tester.pumpWidget(
          SeiRemindsApp(
            repository: repo,
            authService: authService,
            initialRoute: AppRoutes.settings,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Settings & History'), findsOneWidget);

        // Simulate remote session invalidation/sign-out event.
        authService.emitRemoteSession(null);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth_sign_in_button')), findsOneWidget);
        expect(find.text('Settings & History'), findsNothing);
      },
    );
  });
}
