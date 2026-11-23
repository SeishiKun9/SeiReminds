import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seireminds/data/repositories/canvas_token_repository.dart';
import 'package:seireminds/data/services/canvas_api_client.dart';
import 'package:seireminds/data/services/canvas_secure_storage.dart';
import 'package:seireminds/domain/models/canvas_token_models.dart';
import 'package:seireminds/ui/features/canvas/view_models/canvas_settings_view_model.dart';
import 'package:seireminds/ui/features/canvas/views/canvas_settings_page.dart';

class _InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  final List<String> ops = <String>[];
  String? failWriteKey;
  int failWriteAfterCount = 0;
  int _writeAttemptsOnTarget = 0;

  @override
  Future<String?> read(String key) async {
    ops.add('read:$key');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    ops.add('write:$key');
    if (failWriteKey == key) {
      _writeAttemptsOnTarget++;
      if (_writeAttemptsOnTarget > failWriteAfterCount) {
        throw Exception('Simulated KeyStore write failure on $key');
      }
    }
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    ops.add('delete:$key');
    data.remove(key);
  }
}

void main() {
  final fixedNow = DateTime.utc(2026, 11, 23, 12, 0);

  group('Canvas URL, masking & expiration monitoring', () {
    test('enforces HTTPS URLs and masks full tokens safely', () {
      expect(
        normalizeCanvasBaseUrl('$kDefaultCanvasBaseUrl///'),
        kDefaultCanvasBaseUrl,
      );
      expect(
        () => normalizeCanvasBaseUrl('http://holynameuniversity.instructure.com'),
        throwsFormatException,
      );

      const rawToken = '12345~SecretTokenValue9876';
      final masked = maskCanvasToken(rawToken);
      expect(masked, '••••••••9876');
      expect(masked.contains('Secret'), isFalse);
      expect(maskCanvasToken('short'), '••••••••');
    });

    test('evaluates 7-day, 3-day, 24-hour, expired, and unverified states accurately', () {
      // Unverified: never invents a date.
      final unverified = evaluateTokenExpiration(
        expiresAt: null,
        source: CanvasExpirationSource.unverified,
        now: fixedNow,
      );
      expect(unverified.level, TokenExpirationWarningLevel.unverified);
      expect(unverified.expiresAt, isNull);
      expect(unverified.message, contains('cannot be verified'));

      // Healthy (> 7 days).
      final healthy = evaluateTokenExpiration(
        expiresAt: fixedNow.add(const Duration(days: 15)),
        source: CanvasExpirationSource.canvasApi,
        now: fixedNow,
      );
      expect(healthy.level, TokenExpirationWarningLevel.none);
      expect(healthy.isWarning, isFalse);

      // 7-day warning (5 days remaining).
      final warn7 = evaluateTokenExpiration(
        expiresAt: fixedNow.add(const Duration(days: 5)),
        source: CanvasExpirationSource.canvasApi,
        now: fixedNow,
      );
      expect(warn7.level, TokenExpirationWarningLevel.sevenDays);
      expect(warn7.isExpiringSoon, isTrue);
      expect(warn7.message, contains('7-day'));

      // 3-day warning (2 days remaining).
      final warn3 = evaluateTokenExpiration(
        expiresAt: fixedNow.add(const Duration(days: 2)),
        source: CanvasExpirationSource.canvasApi,
        now: fixedNow,
      );
      expect(warn3.level, TokenExpirationWarningLevel.threeDays);
      expect(warn3.message, contains('3-day'));

      // 24-hour final warning (10 hours remaining).
      final warn24 = evaluateTokenExpiration(
        expiresAt: fixedNow.add(const Duration(hours: 10)),
        source: CanvasExpirationSource.canvasApi,
        now: fixedNow,
      );
      expect(warn24.level, TokenExpirationWarningLevel.twentyFourHours);
      expect(warn24.message, contains('24h'));

      // Expired.
      final expired = evaluateTokenExpiration(
        expiresAt: fixedNow.subtract(const Duration(minutes: 1)),
        source: CanvasExpirationSource.canvasApi,
        now: fixedNow,
      );
      expect(expired.level, TokenExpirationWarningLevel.expired);
      expect(expired.message, contains('expired'));
    });
  });

  group('Atomic two-slot Canvas token replacement invariants', () {
    const oldToken = '1001~OldWorkingCanvasToken1111';
    const newToken = '1001~NewWorkingCanvasToken2222';
    const badToken = '1001~InvalidCanvasToken9999';

    MockClient buildCanvasMock({
      required List<String> httpTrace,
      bool allowCoursesForNew = true,
      bool failSecondProfileConfirmForNew = false,
      bool exposeTokenExpiry = true,
      DateTime? oldExpiry,
      DateTime? newExpiry,
    }) {
      var newProfileCalls = 0;
      return MockClient((http.Request request) async {
        final auth = request.headers[HttpHeaders.authorizationHeader] ?? '';
        final token = auth.replaceFirst('Bearer ', '');
        httpTrace.add('${request.method} ${request.url.path} [$token]');

        // Safety invariant: never issue DELETE to revoke tokens on Canvas.
        expect(request.method, 'GET');

        if (token == badToken) {
          return http.Response('{"errors":[{"message":"Invalid access token."}]}', 401);
        }

        if (request.url.path == '/api/v1/users/self/profile') {
          if (token == newToken) {
            newProfileCalls++;
            if (failSecondProfileConfirmForNew && newProfileCalls >= 2) {
              return http.Response('Server Error', 500);
            }
          }
          return http.Response(
            jsonEncode(<String, Object>{
              'id': 42,
              'name': token == newToken ? 'Seishi Updated' : 'Seishi Student',
            }),
            200,
          );
        }

        if (request.url.path == '/api/v1/courses') {
          if (token == newToken && !allowCoursesForNew) {
            return http.Response('Forbidden', 403);
          }
          return http.Response(
            jsonEncode(<Map<String, Object>>[
              <String, Object>{'id': 1, 'name': 'Data Structures'},
              <String, Object>{'id': 2, 'name': 'Operating Systems'},
            ]),
            200,
          );
        }

        if (request.url.path == '/api/v1/users/self/tokens') {
          if (!exposeTokenExpiry) {
            return http.Response('Forbidden', 403);
          }
          final exp = token == newToken
              ? (newExpiry ?? fixedNow.add(const Duration(days: 60)))
              : (oldExpiry ?? fixedNow.add(const Duration(days: 2)));
          return http.Response(
            jsonEncode(<Map<String, Object>>[
              <String, Object>{
                'hint': token == newToken ? 'NewWorking' : 'OldWorking',
                'expires_at': exp.toUtc().toIso8601String(),
              },
            ]),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });
    }

    test('never deletes old token until replacement is validated, saved, and confirmed working', () async {
      final store = _InMemorySecureStore();
      final httpTrace = <String>[];
      final repo = CanvasTokenRepository(
        store: store,
        apiClient: CanvasApiClient(
          httpClient: buildCanvasMock(httpTrace: httpTrace),
        ),
        clock: () => fixedNow,
      );

      // Connect initial token (lands in slot_a).
      final initial = await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: oldToken,
        isReplacement: false,
      );
      expect(initial.succeeded, isTrue);
      expect(initial.metadata!.slotKey, 'slot_a');
      expect(initial.metadata!.maskedToken, '••••••••1111');
      expect(store.data['seireminds_canvas_token_slot_a'], oldToken);

      store.ops.clear();
      httpTrace.clear();

      // Replace with valid new token (stages in slot_b, commits, confirms, THEN deletes slot_a).
      final replaced = await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: newToken,
        isReplacement: true,
      );
      expect(replaced.succeeded, isTrue);
      expect(replaced.status, CanvasConnectionStatus.replacementSuccessful);
      expect(replaced.metadata!.slotKey, 'slot_b');
      expect(replaced.metadata!.maskedToken, '••••••••2222');
      expect(store.data['seireminds_canvas_token_slot_b'], newToken);
      expect(store.data.containsKey('seireminds_canvas_token_slot_a'), isFalse);

      // Verify exact ordering: slot_a deletion is the LAST storage operation,
      // strictly AFTER active pointer commit & post-save read-back confirmation.
      final commitIdx = store.ops.indexOf('write:seireminds_canvas_active_slot');
      final confirmReadIdx = store.ops.lastIndexOf('read:seireminds_canvas_token_slot_b');
      final oldDeleteIdx = store.ops.indexOf('delete:seireminds_canvas_token_slot_a');
      expect(commitIdx, greaterThan(-1));
      expect(confirmReadIdx, greaterThan(commitIdx));
      expect(oldDeleteIdx, greaterThan(confirmReadIdx));

      // Post-save profile confirmation ran a second time with newToken before old slot delete.
      expect(
        httpTrace.where((e) => e.contains('/api/v1/users/self/profile [$newToken]')).length,
        2,
      );
    });

    test('invalid replacement token is discarded while existing working token stays intact', () async {
      final store = _InMemorySecureStore();
      final httpTrace = <String>[];
      final repo = CanvasTokenRepository(
        store: store,
        apiClient: CanvasApiClient(
          httpClient: buildCanvasMock(httpTrace: httpTrace),
        ),
        clock: () => fixedNow,
      );

      await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: oldToken,
        isReplacement: false,
      );

      final failed = await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: badToken,
        isReplacement: true,
      );

      expect(failed.succeeded, isFalse);
      expect(failed.status, CanvasConnectionStatus.replacementValidationFailed);
      expect(failed.metadata!.maskedToken, '••••••••1111');
      // Old slot untouched; staging slot discarded.
      expect(store.data['seireminds_canvas_token_slot_a'], oldToken);
      expect(store.data['seireminds_canvas_active_slot'], 'slot_a');
      expect(store.data.containsKey('seireminds_canvas_token_slot_b'), isFalse);
    });

    test('replacement lacking courses access fails and preserves existing token', () async {
      final store = _InMemorySecureStore();
      final httpTrace = <String>[];
      final repo = CanvasTokenRepository(
        store: store,
        apiClient: CanvasApiClient(
          httpClient: buildCanvasMock(
            httpTrace: httpTrace,
            allowCoursesForNew: false,
          ),
        ),
        clock: () => fixedNow,
      );

      await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: oldToken,
        isReplacement: false,
      );

      final failed = await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: newToken,
        isReplacement: true,
      );

      expect(failed.succeeded, isFalse);
      expect(failed.status, CanvasConnectionStatus.replacementValidationFailed);
      expect(store.data['seireminds_canvas_token_slot_a'], oldToken);
      expect(store.data.containsKey('seireminds_canvas_token_slot_b'), isFalse);
    });

    test('storage failure during commit rolls back atomically and preserves existing token', () async {
      final store = _InMemorySecureStore();
      final httpTrace = <String>[];
      final repo = CanvasTokenRepository(
        store: store,
        apiClient: CanvasApiClient(
          httpClient: buildCanvasMock(httpTrace: httpTrace),
        ),
        clock: () => fixedNow,
      );

      await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: oldToken,
        isReplacement: false,
      );

      // Fault-inject failure when attempting to flip active_slot to slot_b.
      store.failWriteKey = 'seireminds_canvas_active_slot';
      store.failWriteAfterCount = 0;

      final failed = await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: newToken,
        isReplacement: true,
      );

      expect(failed.succeeded, isFalse);
      expect(failed.status, CanvasConnectionStatus.replacementValidationFailed);
      expect(store.data['seireminds_canvas_token_slot_a'], oldToken);
      expect(store.data['seireminds_canvas_active_slot'], 'slot_a');
      expect(store.data.containsKey('seireminds_canvas_token_slot_b'), isFalse);

      // Reload confirms original connection is completely intact.
      final state = await repo.loadState();
      expect(state.metadata!.maskedToken, '••••••••1111');
      expect(state.metadata!.slotKey, 'slot_a');
    });

    test('post-save confirmation failure rolls back pointer and keeps old token', () async {
      final store = _InMemorySecureStore();
      final httpTrace = <String>[];
      final repo = CanvasTokenRepository(
        store: store,
        apiClient: CanvasApiClient(
          httpClient: buildCanvasMock(
            httpTrace: httpTrace,
            failSecondProfileConfirmForNew: true,
          ),
        ),
        clock: () => fixedNow,
      );

      await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: oldToken,
        isReplacement: false,
      );

      final failed = await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: newToken,
        isReplacement: true,
      );

      expect(failed.succeeded, isFalse);
      expect(failed.status, CanvasConnectionStatus.replacementValidationFailed);
      expect(store.data['seireminds_canvas_token_slot_a'], oldToken);
      expect(store.data['seireminds_canvas_active_slot'], 'slot_a');
      expect(store.data.containsKey('seireminds_canvas_token_slot_b'), isFalse);
    });

    test('reports unverified expiration honestly when Canvas hides /users/self/tokens', () async {
      final store = _InMemorySecureStore();
      final httpTrace = <String>[];
      final repo = CanvasTokenRepository(
        store: store,
        apiClient: CanvasApiClient(
          httpClient: buildCanvasMock(
            httpTrace: httpTrace,
            exposeTokenExpiry: false,
          ),
        ),
        clock: () => fixedNow,
      );

      final connected = await repo.saveOrReplaceToken(
        baseUrl: kDefaultCanvasBaseUrl,
        candidateToken: oldToken,
        isReplacement: false,
      );

      expect(connected.succeeded, isTrue);
      expect(connected.metadata!.expiresAt, isNull);
      expect(
        connected.metadata!.expirationSource,
        CanvasExpirationSource.unverified,
      );
      expect(
        connected.metadata!.assessExpiration(now: fixedNow).level,
        TokenExpirationWarningLevel.unverified,
      );
    });
  });

  group('CanvasSettingsPage UI workflow', () {
    testWidgets(
      'displays default HNU URL, masks token, shows warnings, keeps old token on failed replacement, and succeeds on retry',
      (WidgetTester tester) async {
        const oldToken = '1001~OldSecretToken1111';
        const badToken = '1001~BadSecretToken0000';
        const newToken = '1001~NewSecretToken2222';

        final store = _InMemorySecureStore();
        final mockClient = MockClient((http.Request request) async {
          final token =
              (request.headers[HttpHeaders.authorizationHeader] ?? '')
                  .replaceFirst('Bearer ', '');
          if (token == badToken) {
            return http.Response('Unauthorized', 401);
          }
          if (request.url.path == '/api/v1/users/self/profile') {
            return http.Response(
              jsonEncode(<String, Object>{'id': 9, 'name': 'Juan Dela Cruz'}),
              200,
            );
          }
          if (request.url.path == '/api/v1/courses') {
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{'id': 1, 'name': 'Algorithms'},
              ]),
              200,
            );
          }
          if (request.url.path == '/api/v1/users/self/tokens') {
            final exp = token == oldToken
                ? fixedNow.add(const Duration(hours: 12))
                : fixedNow.add(const Duration(days: 45));
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{
                  'hint': token == oldToken ? 'OldSecret' : 'NewSecret',
                  'expires_at': exp.toUtc().toIso8601String(),
                },
              ]),
              200,
            );
          }
          return http.Response('Not Found', 404);
        });

        final repo = CanvasTokenRepository(
          store: store,
          apiClient: CanvasApiClient(httpClient: mockClient),
          clock: () => fixedNow,
        );
        final vm = CanvasSettingsViewModel(
          repository: repo,
          clock: () => fixedNow,
        );
        addTearDown(vm.dispose);

        await tester.pumpWidget(
          MaterialApp(home: CanvasSettingsPage(viewModel: vm)),
        );
        await tester.pumpAndSettle();

        // Default URL pre-populated.
        expect(find.text(kDefaultCanvasBaseUrl), findsOneWidget);
        expect(find.text('Not Connected'), findsOneWidget);

        // Connect initial token expiring in 12 hours -> Expiring Soon + 24h warning.
        await tester.enterText(
          find.byKey(const Key('connect_canvas_token_field')),
          oldToken,
        );
        await tester.tap(find.byKey(const Key('connect_canvas_button')));
        await tester.pumpAndSettle();

        expect(find.text('Expiring Soon'), findsAtLeastNWidgets(1));
        expect(find.textContaining('Final warning (24h)'), findsOneWidget);
        expect(find.text('••••••••1111'), findsOneWidget);
        // Full token MUST NEVER appear in UI!
        expect(find.textContaining(oldToken), findsNothing);
        expect(find.textContaining('OldSecret'), findsNothing);

        // Attempt replacement with INVALID token -> Replacement Validation Failed + old token retained.
        final pageScrollable = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        final replaceButton = find.byKey(
          const Key('replace_canvas_token_button'),
        );
        await tester.scrollUntilVisible(
          replaceButton,
          200,
          scrollable: pageScrollable,
        );
        await tester.tap(replaceButton);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('replace_canvas_token_field')),
          badToken,
        );
        await tester.tap(find.byKey(const Key('confirm_replace_token_button')));
        await tester.pumpAndSettle();

        // Scroll back to top to inspect status banner & retry button.
        await tester.drag(pageScrollable, const Offset(0, 400));
        await tester.pumpAndSettle();

        expect(find.text('Replacement Validation Failed'), findsOneWidget);
        expect(find.byKey(const Key('retry_replace_button')), findsOneWidget);
        expect(find.text('••••••••1111'), findsOneWidget);
        expect(store.data['seireminds_canvas_token_slot_a'], oldToken);

        // Retry with VALID replacement token -> Replacement Successful + masked updated.
        await tester.tap(find.byKey(const Key('retry_replace_button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('replace_canvas_token_field')),
          newToken,
        );
        await tester.tap(find.byKey(const Key('confirm_replace_token_button')));
        await tester.pumpAndSettle();

        expect(find.text('Replacement Successful'), findsOneWidget);
        expect(find.text('••••••••2222'), findsOneWidget);
        expect(find.textContaining(newToken), findsNothing);
        expect(store.data['seireminds_canvas_token_slot_b'], newToken);
        expect(store.data.containsKey('seireminds_canvas_token_slot_a'), isFalse);

        // Disconnect Canvas -> clears local storage cleanly.
        await tester.scrollUntilVisible(
          find.byKey(const Key('disconnect_canvas_button')),
          200,
          scrollable: pageScrollable,
        );
        await tester.tap(find.byKey(const Key('disconnect_canvas_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('confirm_disconnect_canvas_button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Not Connected'), findsOneWidget);
        expect(store.data.containsKey('seireminds_canvas_token_slot_b'), isFalse);
      },
    );
  });
}
