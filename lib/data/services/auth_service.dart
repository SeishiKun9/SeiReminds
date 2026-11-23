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
    this.requiresEmailConfirmation = false,
    this.user,
  });

  final bool succeeded;
  final String message;
  final bool requiresEmailConfirmation;
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

  Future<AuthActionResult> resendSignUpConfirmation(String email);

  Future<AuthActionResult> sendPasswordResetEmail(String email);

  Future<void> signOut();
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({this._authClient, this.isAvailable = true});

  final GoTrueClient? _authClient;
  final bool isAvailable;

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
        email: email.trim(),
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
  Future<AuthActionResult> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final auth = _auth;
    if (auth == null) {
      return const AuthActionResult(
        succeeded: false,
        message: _offlineAuthMessage,
      );
    }
    try {
      final trimmedName = displayName?.trim() ?? '';
      final response = await auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: SupabaseConfig.authRedirectUrl,
        data: trimmedName.isNotEmpty
            ? <String, Object>{'display_name': trimmedName}
            : null,
      );
      final user = _fromSupabaseUser(response.user);
      final needsConfirm = response.session == null;
      return AuthActionResult(
        succeeded: true,
        requiresEmailConfirmation: needsConfirm,
        message: needsConfirm
            ? 'Account created! Check your email to confirm your address before signing in.'
            : 'Account created and signed in as ${user?.label ?? email.trim()}.',
        user: user,
      );
    } on AuthException catch (e) {
      return AuthActionResult(succeeded: false, message: e.message);
    } catch (_) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Could not create account. Check your internet connection.',
      );
    }
  }

  @override
  Future<AuthActionResult> resendSignUpConfirmation(String email) async {
    final auth = _auth;
    if (auth == null) {
      return const AuthActionResult(
        succeeded: false,
        message: _offlineAuthMessage,
      );
    }
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Enter your email address first.',
      );
    }
    try {
      await auth.resend(
        type: OtpType.signup,
        email: trimmed,
        emailRedirectTo: SupabaseConfig.authRedirectUrl,
      );
      return const AuthActionResult(
        succeeded: true,
        message: 'Confirmation email resent. Check your inbox or spam folder.',
      );
    } on AuthException catch (e) {
      return AuthActionResult(succeeded: false, message: e.message);
    } catch (_) {
      return const AuthActionResult(
        succeeded: false,
        message:
            'Could not resend confirmation email. Check your internet connection.',
      );
    }
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
        email.trim(),
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
