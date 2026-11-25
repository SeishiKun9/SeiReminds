import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/supabase_config.dart';
import '../../../../data/repositories/canvas_token_repository.dart';
import '../../../../domain/models/canvas_token_models.dart';

typedef OnlineStatusChecker = Future<bool> Function();

/// Lightweight online reachability check for online-only Canvas routes.
Future<bool> checkOnlineConnectivity() async {
  if (kIsWeb) return true;
  try {
    final host = Uri.parse(SupabaseConfig.url).host;
    final addresses = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 4));
    return addresses.isNotEmpty && addresses.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

class CanvasSettingsViewModel extends ChangeNotifier {
  CanvasSettingsViewModel({
    required this._repository,
    DateTime Function()? clock,
    this._onSyncTodayUpdates,
    this._onDisconnected,
    this._onlineChecker,
  }) : _clock = clock ?? DateTime.now;

  final CanvasTokenRepository _repository;
  final DateTime Function() _clock;
  final Future<CanvasTodaySyncResult> Function()? _onSyncTodayUpdates;
  final Future<void> Function()? _onDisconnected;
  final OnlineStatusChecker? _onlineChecker;

  static const String offlineCanvasMessage =
      'Canvas requires an active internet connection and a verified account. Schedules, events, history, and alarms still work offline.';

  bool get canSyncTodayUpdates => _onSyncTodayUpdates != null;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  String _baseUrl = kDefaultCanvasBaseUrl;
  String get baseUrl => _baseUrl;

  CanvasTokenMetadata? _metadata;
  CanvasTokenMetadata? get metadata => _isOnline ? _metadata : null;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  CanvasConnectionStatus? _lastOperationStatus;
  String? _feedbackMessage;
  String? get feedbackMessage => _feedbackMessage;

  bool _feedbackIsError = false;
  bool get feedbackIsError => _feedbackIsError;

  bool get isConnected => _isOnline && _metadata != null;

  TokenExpirationAssessment? get expirationAssessment =>
      metadata?.assessExpiration(now: _clock());

  CanvasConnectionStatus get connectionStatus {
    final meta = metadata;
    if (meta == null) return CanvasConnectionStatus.notConnected;
    return meta.resolveConnectionStatus(now: _clock());
  }

  /// Primary status displayed on the Canvas Settings page, including transient
  /// Replacement Successful / Replacement Validation Failed outcomes.
  CanvasConnectionStatus get displayedStatus {
    if (!_isOnline) return CanvasConnectionStatus.notConnected;
    if (_lastOperationStatus ==
            CanvasConnectionStatus.replacementValidationFailed ||
        _lastOperationStatus == CanvasConnectionStatus.replacementSuccessful) {
      return _lastOperationStatus!;
    }
    return connectionStatus;
  }

  Future<bool> _verifyOnline() async {
    final checker = _onlineChecker;
    if (checker == null) {
      _isOnline = true;
      return true;
    }
    try {
      _isOnline = await checker();
    } catch (_) {
      _isOnline = false;
    }
    return _isOnline;
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final online = await _verifyOnline();
      if (!online) {
        _feedbackMessage = offlineCanvasMessage;
        _feedbackIsError = true;
        return;
      }
      if (_feedbackMessage == offlineCanvasMessage) {
        _feedbackMessage = null;
        _feedbackIsError = false;
      }
      final snapshot = await _repository.loadState();
      _baseUrl = snapshot.baseUrl;
      _metadata = snapshot.metadata;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<CanvasOperationResult> connectToken({
    required String baseUrl,
    required String token,
    DateTime? manualExpiresAt,
  }) async {
    _isBusy = true;
    _lastOperationStatus = null;
    _feedbackMessage = null;
    _feedbackIsError = false;
    notifyListeners();

    try {
      if (!await _verifyOnline()) {
        _feedbackMessage = offlineCanvasMessage;
        _feedbackIsError = true;
        return const CanvasOperationResult(
          succeeded: false,
          status: CanvasConnectionStatus.notConnected,
          message: offlineCanvasMessage,
        );
      }
      final result = await _repository.saveOrReplaceToken(
        baseUrl: baseUrl,
        candidateToken: token,
        manualExpiresAt: manualExpiresAt,
        isReplacement: false,
      );
      if (result.metadata != null) {
        _metadata = result.metadata;
        _baseUrl = result.metadata!.baseUrl;
      }
      _feedbackMessage = result.message;
      _feedbackIsError = !result.succeeded;
      if (!result.succeeded && _metadata == null) {
        _lastOperationStatus = result.status;
      }
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<CanvasOperationResult> replaceToken({
    required String baseUrl,
    required String replacementToken,
    DateTime? manualExpiresAt,
  }) async {
    _isBusy = true;
    _lastOperationStatus = null;
    _feedbackMessage = null;
    _feedbackIsError = false;
    notifyListeners();

    try {
      if (!await _verifyOnline()) {
        _feedbackMessage = offlineCanvasMessage;
        _feedbackIsError = true;
        return const CanvasOperationResult(
          succeeded: false,
          status: CanvasConnectionStatus.replacementValidationFailed,
          message: offlineCanvasMessage,
        );
      }
      final result = await _repository.saveOrReplaceToken(
        baseUrl: baseUrl,
        candidateToken: replacementToken,
        manualExpiresAt: manualExpiresAt,
        isReplacement: true,
      );
      _metadata = result.metadata;
      if (result.metadata != null) {
        _baseUrl = result.metadata!.baseUrl;
      }
      _lastOperationStatus = result.status;
      _feedbackMessage = result.message;
      _feedbackIsError = !result.succeeded;
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<CanvasOperationResult> verifyConnection() async {
    _isBusy = true;
    _lastOperationStatus = null;
    _feedbackMessage = null;
    _feedbackIsError = false;
    notifyListeners();

    try {
      if (!await _verifyOnline()) {
        _feedbackMessage = offlineCanvasMessage;
        _feedbackIsError = true;
        return const CanvasOperationResult(
          succeeded: false,
          status: CanvasConnectionStatus.notConnected,
          message: offlineCanvasMessage,
        );
      }
      final result = await _repository.verifyCurrentToken();
      _metadata = result.metadata;
      _feedbackMessage = result.message;
      _feedbackIsError = !result.succeeded;
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<CanvasTodaySyncResult?> syncTodayUpdates() async {
    final handler = _onSyncTodayUpdates;
    if (handler == null) return null;
    _isBusy = true;
    _lastOperationStatus = null;
    _feedbackMessage = null;
    _feedbackIsError = false;
    notifyListeners();
    try {
      if (!await _verifyOnline()) {
        _feedbackMessage = offlineCanvasMessage;
        _feedbackIsError = true;
        return const CanvasTodaySyncResult(
          succeeded: false,
          message: offlineCanvasMessage,
          todayAnnouncements: <CanvasDailyItem>[],
          activeActivities: <CanvasDailyItem>[],
          newlyNotifiedCount: 0,
          clearedStaleCount: 0,
        );
      }
      final result = await handler();
      _feedbackMessage = result.message;
      _feedbackIsError = !result.succeeded;
      return result;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _isBusy = true;
    notifyListeners();
    try {
      if (!await _verifyOnline()) {
        _feedbackMessage = offlineCanvasMessage;
        _feedbackIsError = true;
        return;
      }
      await _repository.disconnect();
      await _onDisconnected?.call();
      _metadata = null;
      _lastOperationStatus = null;
      _feedbackMessage =
          'Disconnected Canvas from SeiReminds. Your token was removed from local encrypted storage (not revoked on Canvas).';
      _feedbackIsError = false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
