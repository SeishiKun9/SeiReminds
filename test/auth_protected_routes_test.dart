import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seireminds/core/supabase_config.dart';
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
  _FakeAuthService({AuthSessionUser? initialUser}) : _user = initialUser {
    _registeredEmails.add('student@hnu.edu.ph');
  }

  final StreamController<AuthSessionUser?> _controller =
      StreamController<AuthSessionUser?>.broadcast();
  final Set<String> _registeredEmails = <String>{};
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
    if (email.trim().toLowerCase() == 'student@hnu.edu.ph' &&
        password == 'secret123') {
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
    final normalized = email.trim().toLowerCase();
    if (_registeredEmails.contains(normalized)) {
      return const AuthActionResult(
        succeeded: false,
        message:
            'An account with this email already exists. Please sign in instead.',
      );
    }
    _registeredEmails.add(normalized);
    _user = AuthSessionUser(
      id: 'user-${_registeredEmails.length}',
      email: normalized,
      displayName: displayName?.trim(),
    );
    _controller.add(_user);
    return AuthActionResult(
      succeeded: true,
      message: 'Account created and signed in as ${_user!.label}.',
      user: _user,
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
      'creates account instantly without confirmation email and blocks duplicate email signups',
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

        // Duplicate email (case-insensitive) is rejected.
        await tester.enterText(
          find.byKey(const Key('signup_email_field')),
          'STUDENT@hnu.edu.ph',
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

        expect(
          find.text(
            'An account with this email already exists. Please sign in instead.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Resend Confirmation'), findsNothing);

        // Fresh email signs up and signs in immediately without any confirmation email step.
        await tester.enterText(
          find.byKey(const Key('signup_email_field')),
          'newstudent@hnu.edu.ph',
        );
        final signUpBtn = find.byKey(const Key('auth_sign_up_button'));
        await tester.ensureVisible(signUpBtn);
        await tester.pumpAndSettle();
        await tester.tap(signUpBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
        expect(authService.currentUser?.email, 'newstudent@hnu.edu.ph');
      },
    );

    test(
      'SupabaseAuthService.signUp posts normalized lowercase email to signup-instant and surfaces duplicate 409 error',
      () async {
        late http.Request captured;
        final service = SupabaseAuthService(
          isAvailable: false,
          httpClient: MockClient((http.Request req) async {
            captured = req;
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            if (body['email'] == 'dup@hnu.edu.ph') {
              return http.Response(
                jsonEncode(<String, Object>{
                  'error':
                      'An account with this email already exists. Please sign in instead.',
                }),
                409,
              );
            }
            return http.Response(
              jsonEncode(<String, Object>{
                'user': <String, Object>{
                  'id': 'u-1',
                  'email': body['email'] as String,
                },
              }),
              200,
            );
          }),
        );

        final dup = await service.signUp(
          email: '  DUP@HNU.EDU.PH ',
          password: 'password123',
          displayName: 'Test',
        );
        expect(dup.succeeded, isFalse);
        expect(dup.message, contains('already exists'));
        expect(
          captured.url.toString(),
          '${SupabaseConfig.url}/functions/v1/signup-instant',
        );
        expect(captured.headers['apikey'], SupabaseConfig.publishableKey);
        expect(captured.headers.containsKey('Authorization'), isFalse);
        expect(
          (jsonDecode(captured.body) as Map<String, dynamic>)['email'],
          'dup@hnu.edu.ph',
        );

        final ok = await service.signUp(
          email: 'fresh@hnu.edu.ph',
          password: 'password123',
        );
        expect(ok.succeeded, isTrue);
      },
    );
  });
}
