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
  });

  final bool succeeded;
  final String message;
  final AuthSessionUser? user;
}

abstract class AuthService {
  AuthSessionUser? get currentUser;
  Stream<AuthSessionUser?> get onAuthStateChange;

  Future<AuthActionResult> signInWithPassword({
    required String email,
    required String password,
  });

  Future<AuthActionResult> signUp({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthActionResult> sendPasswordResetEmail(String email);

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

  /// Creates an already-confirmed account via the `signup-instant` Edge Function
  /// (no confirmation email required, duplicate emails rejected) and signs in immediately.
  @override
  Future<AuthActionResult> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final auth = _auth;
    if (auth == null && _httpClient == null) {
      return const AuthActionResult(
        succeeded: false,
        message: _offlineAuthMessage,
      );
    }

    final normalizedEmail = email.trim().toLowerCase();
    final trimmedName = displayName?.trim() ?? '';
    final ownsClient = _httpClient == null;
    final client = _httpClient ?? http.Client();

    try {
      final response = await client
          .post(
            Uri.parse('${SupabaseConfig.url}/functions/v1/signup-instant'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'apikey': SupabaseConfig.publishableKey,
            },
            body: jsonEncode(<String, Object>{
              'email': normalizedEmail,
              'password': password,
              if (trimmedName.isNotEmpty) 'display_name': trimmedName,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        String errorMsg = 'Could not create account (HTTP ${response.statusCode}).';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['error'] is String) {
            errorMsg = decoded['error'] as String;
          }
        } catch (_) {}
        return AuthActionResult(succeeded: false, message: errorMsg);
      }
    } on TimeoutException {
      return const AuthActionResult(
        succeeded: false,
        message: 'Account creation timed out. Check your internet connection.',
      );
    } on SocketException {
      return const AuthActionResult(
        succeeded: false,
        message: 'Could not create account. Check your internet connection.',
      );
    } on http.ClientException {
      return const AuthActionResult(
        succeeded: false,
        message: 'Could not create account. Check your internet connection.',
      );
    } finally {
      if (ownsClient) {
        client.close();
      }
    }

    if (auth == null) {
      return const AuthActionResult(
        succeeded: true,
        message: 'Account created! You can now sign in.',
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
            'Account created and signed in as ${signInResult.user?.label ?? normalizedEmail}.',
        user: signInResult.user,
      );
    }

    return const AuthActionResult(
      succeeded: false,
      message: 'Account created, but automatic sign-in failed. Please sign in.',
    );
  }

  @override
  Future<AuthActionResult> sendPasswordResetEmail(String email) async {
    final auth = _auth;
    if (auth == null) {
      return const AuthActionResult(
        succeeded: false,
        message: _offlineAuthMessage,
      );
    }
    try {
      await auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: SupabaseConfig.authRedirectUrl,
      );
      return const AuthActionResult(
        succeeded: true,
        message: 'Password reset link sent. Check your email inbox.',
      );
    } on AuthException catch (e) {
      return AuthActionResult(succeeded: false, message: e.message);
    } catch (_) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Could not send reset email. Check your internet connection.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _auth?.signOut();
  }
}
