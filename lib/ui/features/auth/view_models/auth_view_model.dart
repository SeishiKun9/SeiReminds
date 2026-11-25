import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/services/auth_service.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required this._authService})
      : _currentUser = _authService.currentUser {
    _subscription = _authService.onAuthStateChange.listen((user) {
      if (_currentUser?.id == user?.id && _currentUser?.email == user?.email) {
        return;
      }
      _currentUser = user;
      notifyListeners();
    });
  }

  static const int maxOtpResends = 3;

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

  Future<AuthActionResult> requestSignUpCode({
    required String email,
    String? displayName,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _authService.requestSignUpCode(
        email: email,
        displayName: displayName,
      );
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

  Future<AuthActionResult> verifySignUpCode({
    required String email,
    required String code,
    required String password,
    String? displayName,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _authService.verifySignUpCode(
        email: email,
        code: code,
        password: password,
        displayName: displayName,
      );
      if (result.succeeded) {
        _currentUser = result.user ?? _authService.currentUser;
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

  Future<AuthActionResult> requestPasswordRecoveryCode(String email) async {
    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _authService.requestPasswordRecoveryCode(email);
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

  Future<AuthActionResult> verifyPasswordRecoveryCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final result = await _authService.verifyPasswordRecoveryCode(
        email: email,
        code: code,
        newPassword: newPassword,
      );
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
