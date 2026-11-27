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
    _passwords['student@hnu.edu.ph'] = 'secret123';
    _displayNames['student@hnu.edu.ph'] = 'Seishi Student';
  }

  final StreamController<AuthSessionUser?> _controller =
      StreamController<AuthSessionUser?>.broadcast();
  final Map<String, String> _passwords = <String, String>{};
  final Map<String, String> _displayNames = <String, String>{};
  final Map<String, String> _signupCodes = <String, String>{};
  final Map<String, int> _signupSends = <String, int>{};
  final Map<String, String> _recoveryCodes = <String, String>{};
  final Map<String, int> _recoverySends = <String, int>{};
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
    final normalized = email.trim().toLowerCase();
    if (_passwords[normalized] == password) {
      _user = AuthSessionUser(
        id: 'user-$normalized',
        email: normalized,
        displayName: _displayNames[normalized],
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
  Future<AuthActionResult> requestSignUpCode({
    required String email,
    String? displayName,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (_passwords.containsKey(normalized)) {
      return const AuthActionResult(
        succeeded: false,
        message:
            'An account with this email already exists. Please sign in instead.',
      );
    }
    final sentCount = _signupSends[normalized] ?? 0;
    if (sentCount >= 4) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Resend limit reached (maximum 3 resends).',
        resendsRemaining: 0,
      );
    }
    _signupSends[normalized] = sentCount + 1;
    _signupCodes[normalized] = '123456';
    return AuthActionResult(
      succeeded: true,
      message: '6-digit verification code sent to $normalized.',
      resendsRemaining: (3 - sentCount).clamp(0, 3),
    );
  }

  @override
  Future<AuthActionResult> verifySignUpCode({
    required String email,
    required String code,
    required String password,
    String? displayName,
    String legalConsentVersion = '1.1.0',
  }) async {
    final normalized = email.trim().toLowerCase();
    if (_signupCodes[normalized] != code.trim()) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Incorrect 6-digit code. 4 attempts remaining.',
      );
    }
    _signupCodes.remove(normalized);
    _passwords[normalized] = password;
    if (displayName != null && displayName.trim().isNotEmpty) {
      _displayNames[normalized] = displayName.trim();
    }
    _user = AuthSessionUser(
      id: 'user-${_passwords.length}',
      email: normalized,
      displayName: _displayNames[normalized],
    );
    _controller.add(_user);
    return AuthActionResult(
      succeeded: true,
      message: 'Account verified and signed in as ${_user!.label}.',
      user: _user,
    );
  }

  @override
  Future<AuthActionResult> requestPasswordRecoveryCode(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!_passwords.containsKey(normalized)) {
      return const AuthActionResult(
        succeeded: false,
        message: 'No SeiReminds account was found for that email address.',
      );
    }
    final sentCount = _recoverySends[normalized] ?? 0;
    if (sentCount >= 4) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Resend limit reached (maximum 3 resends).',
        resendsRemaining: 0,
      );
    }
    _recoverySends[normalized] = sentCount + 1;
    _recoveryCodes[normalized] = '654321';
    return AuthActionResult(
      succeeded: true,
      message: '6-digit recovery code sent to $normalized.',
      resendsRemaining: (3 - sentCount).clamp(0, 3),
    );
  }

  @override
  Future<AuthActionResult> verifyPasswordRecoveryCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (_recoveryCodes[normalized] != code.trim()) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Incorrect 6-digit code. 4 attempts remaining.',
      );
    }
    _recoveryCodes.remove(normalized);
    _passwords[normalized] = newPassword;
    return const AuthActionResult(
      succeeded: true,
      message: 'Password updated! You can now sign in with your new password.',
    );
  }

  @override
  Future<AuthActionResult> deleteAccount() async {
    final active = _user;
    if (active == null) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Sign in while online to permanently delete your account.',
      );
    }
    _passwords.remove(active.email);
    _displayNames.remove(active.email);
    _user = null;
    _controller.add(null);
    return const AuthActionResult(
      succeeded: true,
      message:
          'Your SeiReminds account and server profile data have been permanently deleted.',
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
          AppRoutes.canvasHub,
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

  group('Supabase Auth, Gmail 6-digit OTP & online-only Canvas guard', () {
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

        await tester.pumpWidget(
          SeiRemindsApp(
            repository: repo,
            canvasRepository: canvasRepo,
            authService: authService,
            onlineChecker: () async => true,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
        expect(find.byKey(const Key('auth_sign_in_button')), findsNothing);

        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        expect(find.text('Settings & History'), findsOneWidget);
        expect(find.text('Offline Mode'), findsOneWidget);
        expect(
          find.byKey(const Key('go_to_sign_in_from_settings')),
          findsOneWidget,
        );

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

        await tester.enterText(
          find.byKey(const Key('auth_password_field')),
          'secret123',
        );
        await tester.tap(find.byKey(const Key('auth_sign_in_button')));
        await tester.pumpAndSettle();

        expect(find.text('Canvas Settings'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        expect(find.text('Seishi Student'), findsOneWidget);
        expect(find.text('student@hnu.edu.ph'), findsOneWidget);

        await tester.tap(find.byKey(const Key('sign_out_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
        expect(find.text('Canvas Settings'), findsNothing);
      },
    );

    testWidgets(
      'blocks Canvas token Settings while offline even when signed in, and unlocks once back online',
      (WidgetTester tester) async {
        var online = false;
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
            onlineChecker: () async => online,
            initialRoute: AppRoutes.canvasSettings,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();

        // Offline: Canvas token UI is blocked by the online-only guard.
        expect(find.byKey(const Key('canvas_offline_guard')), findsOneWidget);
        expect(find.byKey(const Key('canvas_status_label')), findsNothing);

        // Come back online and tap Retry Connection -> Canvas Settings unlocks.
        online = true;
        await tester.tap(find.byKey(const Key('canvas_retry_online_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('canvas_offline_guard')), findsNothing);
        expect(find.byKey(const Key('canvas_status_label')), findsOneWidget);
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
            onlineChecker: () async => true,
            initialRoute: AppRoutes.canvasSettings,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Canvas Settings'), findsOneWidget);

        authService.emitRemoteSession(null);
        await tester.pumpAndSettle();

        expect(find.text('Canvas Settings'), findsNothing);
        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
      },
    );

    testWidgets(
      'verifies signup with 6-digit Gmail code, enforces 3-resend cap, and blocks duplicate emails',
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

        // Duplicate email (case-insensitive) is blocked if consent is unchecked first,
        // and rejected after checking legal consent.
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
        final sendBtnFirst = find.byKey(const Key('auth_sign_up_button'));
        await tester.ensureVisible(sendBtnFirst);
        await tester.tap(sendBtnFirst);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'You must agree to the Privacy Policy and Terms of Service to create an account.',
          ),
          findsOneWidget,
        );

        // Agree to Privacy Policy & Terms of Service.
        final consentBox = find.byKey(const Key('signup_legal_consent_checkbox'));
        await tester.ensureVisible(consentBox);
        await tester.tap(consentBox);
        await tester.pumpAndSettle();

        await tester.ensureVisible(sendBtnFirst);
        await tester.tap(sendBtnFirst);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'An account with this email already exists. Please sign in instead.',
          ),
          findsOneWidget,
        );

        // Fresh email sends 6-digit code and enters OTP verification step.
        await tester.enterText(
          find.byKey(const Key('signup_email_field')),
          'newstudent@hnu.edu.ph',
        );
        final sendBtn = find.byKey(const Key('auth_sign_up_button'));
        await tester.ensureVisible(sendBtn);
        await tester.pumpAndSettle();
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('signup_otp_field')), findsOneWidget);
        expect(find.text('Resend Code (3 left)'), findsOneWidget);

        // Resend 3 times -> hits 0 left and disables button.
        final resendBtn = find.byKey(const Key('resend_signup_code_button'));
        for (final expectedLeft in <int>[2, 1, 0]) {
          await tester.ensureVisible(resendBtn);
          await tester.tap(resendBtn);
          await tester.pumpAndSettle();
          if (expectedLeft > 0) {
            expect(find.text('Resend Code ($expectedLeft left)'), findsOneWidget);
          } else {
            expect(find.text('Resend Limit Reached (0 left)'), findsOneWidget);
          }
        }

        // Wrong 6-digit code is rejected.
        await tester.enterText(
          find.byKey(const Key('signup_otp_field')),
          '000000',
        );
        await tester.tap(find.byKey(const Key('verify_signup_code_button')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Incorrect 6-digit code'), findsOneWidget);

        // Valid 6-digit code verifies account and signs in immediately.
        await tester.enterText(
          find.byKey(const Key('signup_otp_field')),
          '123456',
        );
        await tester.tap(find.byKey(const Key('verify_signup_code_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
        expect(authService.currentUser?.email, 'newstudent@hnu.edu.ph');
      },
    );

    testWidgets(
      'recovers forgotten password via 6-digit Gmail code and allows sign-in with new password',
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
            initialRoute: AppRoutes.login,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('auth_forgot_password_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('recovery_email_field')),
          'student@hnu.edu.ph',
        );
        await tester.tap(find.byKey(const Key('send_recovery_code_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('recovery_otp_field')), findsOneWidget);
        expect(find.text('Resend Code (3 left)'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('recovery_otp_field')),
          '654321',
        );
        await tester.enterText(
          find.byKey(const Key('recovery_new_password_field')),
          'newpass456',
        );
        await tester.enterText(
          find.byKey(const Key('recovery_confirm_password_field')),
          'newpass456',
        );
        await tester.tap(find.byKey(const Key('confirm_recovery_reset_button')));
        await tester.pumpAndSettle();

        // Sign in on LoginPage with the updated password.
        await tester.enterText(
          find.byKey(const Key('auth_password_field')),
          'newpass456',
        );
        await tester.tap(find.byKey(const Key('auth_sign_in_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
        expect(authService.currentUser?.email, 'student@hnu.edu.ph');
      },
    );

    test(
      'SupabaseAuthService posts Gmail OTP actions to auth-otp-gmail and parses resends_remaining',
      () async {
        final capturedActions = <Map<String, dynamic>>[];
        final service = SupabaseAuthService(
          isAvailable: false,
          httpClient: MockClient((http.Request req) async {
            expect(
              req.url.toString(),
              '${SupabaseConfig.url}/functions/v1/auth-otp-gmail',
            );
            expect(req.headers['apikey'], SupabaseConfig.publishableKey);
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            capturedActions.add(body);
            if (body['action'] == 'send_signup_otp' &&
                body['email'] == 'dup@hnu.edu.ph') {
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
                'ok': true,
                'resends_remaining': 2,
                'message': 'Code sent.',
              }),
              200,
            );
          }),
        );

        final dup = await service.requestSignUpCode(
          email: '  DUP@HNU.EDU.PH ',
          displayName: 'Test',
        );
        expect(dup.succeeded, isFalse);
        expect(dup.message, contains('already exists'));

        final sendSignup = await service.requestSignUpCode(
          email: 'fresh@hnu.edu.ph',
          displayName: 'Fresh',
        );
        expect(sendSignup.succeeded, isTrue);
        expect(sendSignup.resendsRemaining, 2);

        final verifySignup = await service.verifySignUpCode(
          email: 'fresh@hnu.edu.ph',
          code: '123456',
          password: 'password123',
        );
        expect(verifySignup.succeeded, isTrue);

        final sendRecovery = await service.requestPasswordRecoveryCode(
          'fresh@hnu.edu.ph',
        );
        expect(sendRecovery.succeeded, isTrue);

        final verifyRecovery = await service.verifyPasswordRecoveryCode(
          email: 'fresh@hnu.edu.ph',
          code: '654321',
          newPassword: 'newpassword123',
        );
        expect(verifyRecovery.succeeded, isTrue);

        expect(
          capturedActions.map((e) => e['action']).toList(),
          <String>[
            'send_signup_otp',
            'send_signup_otp',
            'verify_signup_otp',
            'send_recovery_otp',
            'verify_recovery_otp',
          ],
        );
      },
    );

    test(
      'SupabaseAuthService.deleteAccount posts Bearer token to delete-account',
      () async {
        late http.Request captured;
        final service = SupabaseAuthService(
          isAvailable: false,
          httpClient: MockClient((http.Request req) async {
            captured = req;
            return http.Response(
              jsonEncode(<String, Object>{
                'ok': true,
                'message': 'Account deleted.',
              }),
              200,
            );
          }),
        );

        final res = await service.deleteAccount(
          accessTokenOverride: 'jwt-secret-token',
        );
        expect(res.succeeded, isTrue);
        expect(
          captured.url.toString(),
          '${SupabaseConfig.url}/functions/v1/delete-account',
        );
        expect(captured.headers['Authorization'], 'Bearer jwt-secret-token');
        expect(captured.headers['apikey'], SupabaseConfig.publishableKey);
      },
    );

    testWidgets(
      'Settings exposes Privacy Policy, Terms of Service, secret-free Export My Data, and permanent in-app Delete Account',
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
            onlineChecker: () async => true,
            initialRoute: AppRoutes.settings,
            initialWeekday: DateTime.monday,
          ),
        );
        await tester.pumpAndSettle();

        final settingsScrollable = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;

        // Open Privacy Policy viewer offline.
        final privacyTile = find.byKey(const Key('open_privacy_policy_tile'));
        await tester.scrollUntilVisible(
          privacyTile,
          250,
          scrollable: settingsScrollable,
        );
        await tester.ensureVisible(privacyTile);
        await tester.tap(privacyTile);
        await tester.pumpAndSettle();
        expect(find.text('SeiReminds Privacy Policy'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Open Terms of Service viewer offline.
        final termsTile = find.byKey(const Key('open_terms_of_service_tile'));
        await tester.ensureVisible(termsTile);
        await tester.tap(termsTile);
        await tester.pumpAndSettle();
        expect(find.text('SeiReminds Terms of Service'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Open Export My Data dialog (secret-free JSON).
        final exportTile = find.byKey(const Key('export_my_data_tile'));
        await tester.ensureVisible(exportTile);
        await tester.tap(exportTile);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('export_data_dialog')), findsOneWidget);
        expect(find.textContaining('Canvas API tokens are excluded'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        // Permanently delete account -> clears auth session and returns cleanly to offline Home.
        final deleteBtn = find.byKey(const Key('delete_account_button'));
        await tester.scrollUntilVisible(
          deleteBtn,
          200,
          scrollable: settingsScrollable,
        );
        await tester.ensureVisible(deleteBtn);
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_delete_account_button')));
        await tester.pumpAndSettle();

        expect(authService.currentUser, isNull);
        expect(find.byKey(const Key('add_schedule_fab')), findsOneWidget);
      },
    );
  });
}
