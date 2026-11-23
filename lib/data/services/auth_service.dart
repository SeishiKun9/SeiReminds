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

  Future<AuthActionResult> sendPasswordResetEmail(String email);

  Future<void> signOut();
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({this._authClient});

  final GoTrueClient? _authClient;

  GoTrueClient get _auth => _authClient ?? Supabase.instance.client.auth;

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
  AuthSessionUser? get currentUser => _fromSupabaseUser(_auth.currentUser);

  @override
  Stream<AuthSessionUser?> get onAuthStateChange =>
      _auth.onAuthStateChange.map((state) => _fromSupabaseUser(state.session?.user));

  @override
  Future<AuthActionResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
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
    try {
      final trimmedName = displayName?.trim() ?? '';
      final response = await _auth.signUp(
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
  Future<AuthActionResult> sendPasswordResetEmail(String email) async {
    try {
      await _auth.resetPasswordForEmail(
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
    await _auth.signOut();
  }
}
