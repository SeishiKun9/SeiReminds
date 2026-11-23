import 'package:flutter/foundation.dart';

import '../../../../data/repositories/canvas_token_repository.dart';
import '../../../../domain/models/canvas_token_models.dart';

class CanvasSettingsViewModel extends ChangeNotifier {
  CanvasSettingsViewModel({
    required this._repository,
    DateTime Function()? clock,
    this._onSyncTodayUpdates,
    this._onDisconnected,
  }) : _clock = clock ?? DateTime.now;

  final CanvasTokenRepository _repository;
  final DateTime Function() _clock;
  final Future<CanvasTodaySyncResult> Function()? _onSyncTodayUpdates;
  final Future<void> Function()? _onDisconnected;

  bool get canSyncTodayUpdates => _onSyncTodayUpdates != null;

  String _baseUrl = kDefaultCanvasBaseUrl;
  String get baseUrl => _baseUrl;

  CanvasTokenMetadata? _metadata;
  CanvasTokenMetadata? get metadata => _metadata;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  CanvasConnectionStatus? _lastOperationStatus;
  String? _feedbackMessage;
  String? get feedbackMessage => _feedbackMessage;

  bool _feedbackIsError = false;
  bool get feedbackIsError => _feedbackIsError;

  bool get isConnected => _metadata != null;

  TokenExpirationAssessment? get expirationAssessment =>
      _metadata?.assessExpiration(now: _clock());

  CanvasConnectionStatus get connectionStatus {
    final meta = _metadata;
    if (meta == null) return CanvasConnectionStatus.notConnected;
    return meta.resolveConnectionStatus(now: _clock());
  }

  /// Primary status displayed on the Canvas Settings page, including transient
  /// Replacement Successful / Replacement Validation Failed outcomes.
  CanvasConnectionStatus get displayedStatus {
    if (_lastOperationStatus ==
            CanvasConnectionStatus.replacementValidationFailed ||
        _lastOperationStatus == CanvasConnectionStatus.replacementSuccessful) {
      return _lastOperationStatus!;
    }
    return connectionStatus;
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
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
