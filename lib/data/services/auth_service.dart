import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';

class AuthSessionUser {
  const AuthSessionUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  final String id;
  final String email;
  final String? displayName;

  String get label {
    final trimmed = displayName?.trim() ?? '';
    return trimmed.isNotEmpty ? trimmed : email;
  }

  @override
  String toString() => 'AuthSessionUser(id: $id, email: $email)';
}

class AuthActionResult {
  const AuthActionResult({
    required this.succeeded,
    required this.message,
    this.user,
    this.resendsRemaining,
  });

  final bool succeeded;
  final String message;
  final AuthSessionUser? user;
  final int? resendsRemaining;
}

abstract class AuthService {
  AuthSessionUser? get currentUser;
  Stream<AuthSessionUser?> get onAuthStateChange;

  Future<AuthActionResult> signInWithPassword({
    required String email,
    required String password,
  });

  Future<AuthActionResult> requestSignUpCode({
    required String email,
    String? displayName,
  });

  Future<AuthActionResult> verifySignUpCode({
    required String email,
    required String code,
    required String password,
    String? displayName,
  });

  Future<AuthActionResult> requestPasswordRecoveryCode(String email);

  Future<AuthActionResult> verifyPasswordRecoveryCode({
    required String email,
    required String code,
    required String newPassword,
  });

  Future<void> signOut();
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({
    this._authClient,
    this.isAvailable = true,
    this._httpClient,
  });

  final GoTrueClient? _authClient;
  final bool isAvailable;
  final http.Client? _httpClient;

  static const String _offlineAuthMessage =
      'Online account service is unavailable offline. Schedules, events, history, and alarms still work offline.';

  static Uri get _otpEndpoint =>
      Uri.parse('${SupabaseConfig.url}/functions/v1/auth-otp-gmail');

  GoTrueClient? get _auth {
    if (_authClient != null) return _authClient;
    if (!isAvailable) return null;
    try {
      return Supabase.instance.client.auth;
    } catch (_) {
      return null;
    }
  }

  static AuthSessionUser? _fromSupabaseUser(User? user) {
    if (user == null) return null;
    final meta = user.userMetadata;
    final rawName = meta?['display_name'] ?? meta?['full_name'];
    return AuthSessionUser(
      id: user.id,
      email: user.email ?? '',
      displayName: rawName is String ? rawName : null,
    );
  }

  @override
  AuthSessionUser? get currentUser => _fromSupabaseUser(_auth?.currentUser);

  @override
  Stream<AuthSessionUser?> get onAuthStateChange {
    final auth = _auth;
    if (auth == null) return const Stream<AuthSessionUser?>.empty();
    return auth.onAuthStateChange
        .map((state) => _fromSupabaseUser(state.session?.user));
  }

  Future<AuthActionResult> _postOtpAction(
    Map<String, Object> payload, {
    required String defaultSuccessMessage,
    required String timeoutMessage,
    required String offlineMessage,
  }) async {
    if (_auth == null && _httpClient == null) {
      return const AuthActionResult(
        succeeded: false,
        message: _offlineAuthMessage,
      );
    }

    final ownsClient = _httpClient == null;
    final client = _httpClient ?? http.Client();
    try {
      final response = await client
          .post(
            _otpEndpoint,
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'apikey': SupabaseConfig.publishableKey,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic>? decoded;
      try {
        final raw = jsonDecode(response.body);
        if (raw is Map<String, dynamic>) decoded = raw;
      } catch (_) {}

      final resendsRemaining = decoded?['resends_remaining'] is num
          ? (decoded!['resends_remaining'] as num).toInt()
          : null;

      if (response.statusCode != 200) {
        final errorMsg = (decoded?['error'] is String &&
                (decoded!['error'] as String).trim().isNotEmpty)
            ? decoded['error'] as String
            : 'Request failed (HTTP ${response.statusCode}).';
        return AuthActionResult(
          succeeded: false,
          message: errorMsg,
          resendsRemaining: resendsRemaining,
        );
      }

      final successMsg = (decoded?['message'] is String &&
              (decoded!['message'] as String).trim().isNotEmpty)
          ? decoded['message'] as String
          : defaultSuccessMessage;
      return AuthActionResult(
        succeeded: true,
        message: successMsg,
        resendsRemaining: resendsRemaining,
      );
    } on TimeoutException {
      return AuthActionResult(succeeded: false, message: timeoutMessage);
    } on SocketException {
      return AuthActionResult(succeeded: false, message: offlineMessage);
    } on http.ClientException {
      return AuthActionResult(succeeded: false, message: offlineMessage);
    } finally {
      if (ownsClient) {
        client.close();
      }
    }
  }

  @override
  Future<AuthActionResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) {
      return const AuthActionResult(
        succeeded: false,
        message: _offlineAuthMessage,
      );
    }
    try {
      final response = await auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = _fromSupabaseUser(response.user);
      if (user == null || response.session == null) {
        return const AuthActionResult(
          succeeded: false,
          message: 'Sign-in did not establish a valid session.',
        );
      }
      return AuthActionResult(
        succeeded: true,
        message: 'Signed in as ${user.label}.',
        user: user,
      );
    } on AuthException catch (e) {
      return AuthActionResult(succeeded: false, message: e.message);
    } catch (_) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Could not reach Supabase Auth. Check your internet connection.',
      );
    }
  }

  @override
  Future<AuthActionResult> requestSignUpCode({
    required String email,
    String? displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedName = displayName?.trim() ?? '';
    return _postOtpAction(
      <String, Object>{
        'action': 'send_signup_otp',
        'email': normalizedEmail,
        if (trimmedName.isNotEmpty) 'display_name': trimmedName,
      },
      defaultSuccessMessage:
          '6-digit verification code sent to $normalizedEmail.',
      timeoutMessage:
          'Sending verification code timed out. Check your internet connection.',
      offlineMessage:
          'Could not send verification code. Check your internet connection.',
    );
  }

  @override
  Future<AuthActionResult> verifySignUpCode({
    required String email,
    required String code,
    required String password,
    String? displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedName = displayName?.trim() ?? '';
    final verified = await _postOtpAction(
      <String, Object>{
        'action': 'verify_signup_otp',
        'email': normalizedEmail,
        'code': code.trim(),
        'password': password,
        if (trimmedName.isNotEmpty) 'display_name': trimmedName,
      },
      defaultSuccessMessage: 'Account verified and created!',
      timeoutMessage:
          'Verification timed out. Check your internet connection.',
      offlineMessage:
          'Could not verify code. Check your internet connection.',
    );
    if (!verified.succeeded) return verified;

    final auth = _auth;
    if (auth == null) {
      return const AuthActionResult(
        succeeded: true,
        message: 'Account verified and created! You can now sign in.',
      );
    }

    final signInResult = await signInWithPassword(
      email: normalizedEmail,
      password: password,
    );
    if (signInResult.succeeded) {
      return AuthActionResult(
        succeeded: true,
        message:
            'Account verified and signed in as ${signInResult.user?.label ?? normalizedEmail}.',
        user: signInResult.user,
      );
    }

    return const AuthActionResult(
      succeeded: false,
      message:
          'Account verified and created, but automatic sign-in failed. Please sign in.',
    );
  }

  @override
  Future<AuthActionResult> requestPasswordRecoveryCode(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    return _postOtpAction(
      <String, Object>{
        'action': 'send_recovery_otp',
        'email': normalizedEmail,
      },
      defaultSuccessMessage:
          '6-digit recovery code sent to $normalizedEmail.',
      timeoutMessage:
          'Sending recovery code timed out. Check your internet connection.',
      offlineMessage:
          'Could not send recovery code. Check your internet connection.',
    );
  }

  @override
  Future<AuthActionResult> verifyPasswordRecoveryCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    return _postOtpAction(
      <String, Object>{
        'action': 'verify_recovery_otp',
        'email': normalizedEmail,
        'code': code.trim(),
        'new_password': newPassword,
      },
      defaultSuccessMessage:
          'Password updated! You can now sign in with your new password.',
      timeoutMessage:
          'Password reset timed out. Check your internet connection.',
      offlineMessage:
          'Could not reset password. Check your internet connection.',
    );
  }

  @override
  Future<void> signOut() async {
    await _auth?.signOut();
  }
}
