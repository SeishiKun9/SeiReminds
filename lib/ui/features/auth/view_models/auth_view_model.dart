import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/services/auth_service.dart';

class AuthViewModel extends ChangeNotifier {
  static const int maxConfirmationResends = 3;

  AuthViewModel({required this._authService})
      : _currentUser = _authService.currentUser {
    _subscription = _authService.onAuthStateChange.listen((user) {
      if (_currentUser?.id == user?.id && _currentUser?.email == user?.email) {
        return;
      }
      _currentUser = user;
      if (user != null) {
        _resetPendingConfirmation();
      }
      notifyListeners();
    });
  }

  final AuthService _authService;
  late final StreamSubscription<AuthSessionUser?> _subscription;

  AuthSessionUser? _currentUser;
  AuthSessionUser? get currentUser => _currentUser;

  bool get isAuthenticated => _currentUser != null;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _infoMessage;
  String? get infoMessage => _infoMessage;

  String? _pendingConfirmationEmail;
  String? get pendingConfirmationEmail => _pendingConfirmationEmail;

  // shortcut: resend count lives in memory only; persist if limit must survive app restarts.
  int _confirmationResendsUsed = 0;
  int get confirmationResendsUsed => _confirmationResendsUsed;

  int get confirmationResendsRemaining =>
      (maxConfirmationResends - _confirmationResendsUsed).clamp(
        0,
        maxConfirmationResends,
      );

  bool get canResendConfirmation =>
      _pendingConfirmationEmail != null && confirmationResendsRemaining > 0;

  void _resetPendingConfirmation() {
    _pendingConfirmationEmail = null;
    _confirmationResendsUsed = 0;
  }

  void clearMessages() {
    if (_errorMessage == null && _infoMessage == null) return;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  Future<AuthActionResult> signIn({
    required String email,
    required String password,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _authService.signInWithPassword(
        email: email,
        password: password,
      );
      if (result.succeeded) {
        _resetPendingConfirmation();
        _currentUser = result.user ?? _authService.currentUser;
      } else {
        _errorMessage = result.message;
      }
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<AuthActionResult> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _authService.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (result.succeeded) {
        if (result.requiresEmailConfirmation) {
          final trimmedEmail = email.trim();
          if (_pendingConfirmationEmail?.toLowerCase() !=
              trimmedEmail.toLowerCase()) {
            _pendingConfirmationEmail = trimmedEmail;
            _confirmationResendsUsed = 0;
          }
          _infoMessage = result.message;
        } else {
          _resetPendingConfirmation();
          _currentUser = result.user ?? _authService.currentUser;
        }
      } else {
        _errorMessage = result.message;
      }
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<AuthActionResult> resendSignUpConfirmation() async {
    if (_isBusy) {
      return const AuthActionResult(
        succeeded: false,
        message: 'Please wait for the current request to finish.',
      );
    }
    final email = _pendingConfirmationEmail;
    if (email == null) {
      const msg = 'Create an account first before resending confirmation.';
      _errorMessage = msg;
      _infoMessage = null;
      notifyListeners();
      return const AuthActionResult(succeeded: false, message: msg);
    }
    if (_confirmationResendsUsed >= maxConfirmationResends) {
      const msg =
          'You have reached the maximum of $maxConfirmationResends confirmation email resends.';
      _errorMessage = msg;
      _infoMessage = null;
      notifyListeners();
      return const AuthActionResult(succeeded: false, message: msg);
    }

    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _authService.resendSignUpConfirmation(email);
      if (result.succeeded) {
        _confirmationResendsUsed++;
        final remaining = confirmationResendsRemaining;
        final suffix = remaining > 0
            ? '($remaining ${remaining == 1 ? 'resend' : 'resends'} remaining)'
            : '(No resends remaining.)';
        _infoMessage = '${result.message} $suffix';
      } else {
        _errorMessage = result.message;
      }
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<AuthActionResult> sendPasswordReset(String email) async {
    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _authService.sendPasswordResetEmail(email);
      if (result.succeeded) {
        _infoMessage = result.message;
      } else {
        _errorMessage = result.message;
      }
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      await _authService.signOut();
      _resetPendingConfirmation();
      _currentUser = null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
