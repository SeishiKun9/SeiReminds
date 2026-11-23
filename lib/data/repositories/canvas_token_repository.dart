import 'dart:convert';

import '../../domain/models/canvas_token_models.dart';
import '../services/canvas_api_client.dart';
import '../services/canvas_secure_storage.dart';

class CanvasStateSnapshot {
  const CanvasStateSnapshot({
    required this.baseUrl,
    this.metadata,
  });

  final String baseUrl;
  final CanvasTokenMetadata? metadata;
}

/// Manages encrypted Canvas API tokens with two-slot atomic replacement.
/// Invariant: an existing token is NEVER deleted until its replacement is
/// validated against Canvas, securely saved, committed, and confirmed working.
class CanvasTokenRepository {
  CanvasTokenRepository({
    required this._store,
    required this._apiClient,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const String _slotA = 'slot_a';
  static const String _slotB = 'slot_b';
  static const String _keySlotA = 'seireminds_canvas_token_slot_a';
  static const String _keySlotB = 'seireminds_canvas_token_slot_b';
  static const String _keyActiveSlot = 'seireminds_canvas_active_slot';
  static const String _keyMetadata = 'seireminds_canvas_metadata_v1';
  static const String _keyBaseUrl = 'seireminds_canvas_base_url_v1';

  final SecureKeyValueStore _store;
  final CanvasApiClient _apiClient;
  final DateTime Function() _clock;

  String _storageKeyForSlot(String slot) =>
      slot == _slotA ? _keySlotA : _keySlotB;

  String _inactiveSlotFor(String? activeSlot) =>
      activeSlot == _slotA ? _slotB : _slotA;

  Future<CanvasStateSnapshot> loadState() async {
    final savedUrl = await _store.read(_keyBaseUrl);
    final baseUrl =
        (savedUrl != null && savedUrl.trim().isNotEmpty)
            ? savedUrl
            : kDefaultCanvasBaseUrl;

    final activeSlot = await _store.read(_keyActiveSlot);
    final rawMeta = await _store.read(_keyMetadata);
    if (activeSlot == null || rawMeta == null) {
      return CanvasStateSnapshot(baseUrl: baseUrl);
    }

    final activeToken = await _store.read(_storageKeyForSlot(activeSlot));
    if (activeToken == null || activeToken.trim().isEmpty) {
      return CanvasStateSnapshot(baseUrl: baseUrl);
    }

    try {
      final decoded = jsonDecode(rawMeta);
      if (decoded is! Map<String, dynamic>) {
        return CanvasStateSnapshot(baseUrl: baseUrl);
      }
      final meta = CanvasTokenMetadata.fromJson(decoded);
      return CanvasStateSnapshot(baseUrl: meta.baseUrl, metadata: meta);
    } catch (_) {
      return CanvasStateSnapshot(baseUrl: baseUrl);
    }
  }

  /// Connects an initial Canvas token or safely replaces the existing one atomically.
  ///
  /// Protocol:
  /// 1. Leave existing slot, active pointer, and metadata untouched.
  /// 2. Write replacement token into the inactive encrypted staging slot.
  /// 3. Read replacement back and validate against Canvas profile + courses APIs.
  /// 4. Commit updated metadata and flip the active slot pointer.
  /// 5. Read back active slot and confirm the saved token works with Canvas.
  /// 6. Only after confirmation succeeds, delete the previous token slot.
  /// On ANY error before step 6, roll back pointer/metadata, discard staging,
  /// and preserve the existing working token untouched.
  Future<CanvasOperationResult> saveOrReplaceToken({
    required String baseUrl,
    required String candidateToken,
    DateTime? manualExpiresAt,
    required bool isReplacement,
  }) async {
    final existingSnapshot = await loadState();
    final existingMetadata = existingSnapshot.metadata;
    final oldSlot = await _store.read(_keyActiveSlot);
    final oldMetadataRaw = await _store.read(_keyMetadata);
    final oldBaseUrlRaw = await _store.read(_keyBaseUrl);

    final failureStatus = isReplacement
        ? CanvasConnectionStatus.replacementValidationFailed
        : CanvasConnectionStatus.invalidToken;

    final String normalizedBaseUrl;
    try {
      normalizedBaseUrl = normalizeCanvasBaseUrl(baseUrl);
    } on FormatException catch (e) {
      return CanvasOperationResult(
        succeeded: false,
        status: failureStatus,
        message: e.message,
        metadata: existingMetadata,
      );
    }

    final trimmedToken = candidateToken.trim();
    if (trimmedToken.isEmpty) {
      return CanvasOperationResult(
        succeeded: false,
        status: failureStatus,
        message: 'Enter a valid Canvas API token.',
        metadata: existingMetadata,
      );
    }

    // Step 2: Hold replacement token securely in the inactive slot without touching oldSlot.
    final targetSlot = _inactiveSlotFor(oldSlot);
    final targetStorageKey = _storageKeyForSlot(targetSlot);

    try {
      await _store.write(targetStorageKey, trimmedToken);
      final stagedReadBack = await _store.read(targetStorageKey);
      if (stagedReadBack != trimmedToken) {
        await _safeDelete(targetStorageKey);
        return CanvasOperationResult(
          succeeded: false,
          status: failureStatus,
          message:
              'Could not verify encrypted storage for the new token. Your existing token was kept.',
          metadata: existingMetadata,
        );
      }
    } catch (_) {
      await _safeDelete(targetStorageKey);
      return CanvasOperationResult(
        succeeded: false,
        status: failureStatus,
        message:
            'Secure storage failed while staging the replacement token. Your existing token was kept.',
        metadata: existingMetadata,
      );
    }

    // Step 3 & 4: Validate the staged token via authenticated Canvas API requests.
    final CanvasValidationResult validation;
    try {
      final stagedToken = await _store.read(targetStorageKey);
      if (stagedToken == null || stagedToken != trimmedToken) {
        throw const CanvasApiException(
          'Staged replacement token could not be read back from encrypted storage.',
        );
      }

      validation = await _apiClient.validateToken(
        baseUrl: normalizedBaseUrl,
        token: stagedToken,
        manualExpiresAt: manualExpiresAt,
      );

      final now = _clock().toUtc();
      if (validation.expiresAt != null && !validation.expiresAt!.isAfter(now)) {
        throw const CanvasApiException(
          'The replacement token is already expired. Generate a fresh token in Canvas and retry.',
          isAuthFailure: true,
          isExpired: true,
        );
      }
    } on CanvasApiException catch (e) {
      await _safeDelete(targetStorageKey);
      return CanvasOperationResult(
        succeeded: false,
        status: failureStatus,
        message: isReplacement
            ? '${e.message} Existing Canvas token was kept unchanged.'
            : e.message,
        metadata: existingMetadata,
      );
    } catch (_) {
      await _safeDelete(targetStorageKey);
      return CanvasOperationResult(
        succeeded: false,
        status: failureStatus,
        message: isReplacement
            ? 'Validation failed unexpectedly. Existing Canvas token was kept unchanged.'
            : 'Validation failed unexpectedly. Check your network and retry.',
        metadata: existingMetadata,
      );
    }

    // Step 5 & 6: Build metadata and commit active pointer atomically.
    final now = _clock().toUtc();
    final newMetadata = CanvasTokenMetadata(
      baseUrl: normalizedBaseUrl,
      slotKey: targetSlot,
      maskedToken: maskCanvasToken(trimmedToken),
      userId: validation.userId,
      userName: validation.userName,
      coursesAccessibleCount: validation.coursesAccessibleCount,
      expiresAt: validation.expiresAt,
      expirationSource: validation.expirationSource,
      lastVerifiedAt: now,
      isInvalidOnLastCheck: false,
    );

    try {
      await _store.write(_keyMetadata, jsonEncode(newMetadata.toJson()));
      await _store.write(_keyActiveSlot, targetSlot);
      await _store.write(_keyBaseUrl, normalizedBaseUrl);

      // Step 7: Confirm the replacement is saved in the active slot AND working
      // BEFORE deleting the previous token.
      final confirmedSlot = await _store.read(_keyActiveSlot);
      final confirmedToken = await _store.read(targetStorageKey);
      if (confirmedSlot != targetSlot || confirmedToken != trimmedToken) {
        throw StateError('Active slot confirmation mismatch');
      }
      await _apiClient.confirmTokenWorking(
        baseUrl: normalizedBaseUrl,
        token: confirmedToken!,
      );
    } catch (_) {
      // Atomic rollback: restore previous pointer/metadata and discard ONLY targetSlot.
      await _rollbackCommit(
        oldSlot: oldSlot,
        oldMetadataRaw: oldMetadataRaw,
        oldBaseUrlRaw: oldBaseUrlRaw,
        failedTargetKey: targetStorageKey,
      );
      return CanvasOperationResult(
        succeeded: false,
        status: failureStatus,
        message: isReplacement
            ? 'Could not confirm saving the replacement token. Your previous token and connection were preserved.'
            : 'Could not confirm saving the token securely. Please retry.',
        metadata: existingMetadata,
      );
    }

    // Step 8: Confirmed saved and working — NOW safely remove old token from local storage.
    // Never auto-revoke on Canvas server.
    if (oldSlot != null && oldSlot != targetSlot) {
      await _safeDelete(_storageKeyForSlot(oldSlot));
    }

    final successStatus = isReplacement
        ? CanvasConnectionStatus.replacementSuccessful
        : newMetadata.resolveConnectionStatus(now: now);

    return CanvasOperationResult(
      succeeded: true,
      status: successStatus,
      message: isReplacement
          ? 'Replacement successful. Connected as ${newMetadata.userName} (${newMetadata.coursesAccessibleCount} active courses accessible).'
          : 'Connected to Canvas as ${newMetadata.userName}.',
      metadata: newMetadata,
    );
  }

  /// Re-validates the currently saved token without modifying or deleting it.
  Future<CanvasOperationResult> verifyCurrentToken() async {
    final snapshot = await loadState();
    final existing = snapshot.metadata;
    if (existing == null) {
      return const CanvasOperationResult(
        succeeded: false,
        status: CanvasConnectionStatus.notConnected,
        message: 'No Canvas API token is currently saved.',
      );
    }

    final token = await _store.read(_storageKeyForSlot(existing.slotKey));
    if (token == null || token.trim().isEmpty) {
      return const CanvasOperationResult(
        succeeded: false,
        status: CanvasConnectionStatus.notConnected,
        message: 'No Canvas API token is currently saved.',
      );
    }

    final now = _clock().toUtc();
    try {
      final result = await _apiClient.validateToken(
        baseUrl: existing.baseUrl,
        token: token,
        manualExpiresAt: existing.expirationSource == CanvasExpirationSource.manual
            ? existing.expiresAt
            : null,
      );

      final updated = existing.copyWith(
        userId: result.userId,
        userName: result.userName,
        coursesAccessibleCount: result.coursesAccessibleCount,
        expiresAt: result.expiresAt,
        clearExpiresAt: result.expiresAt == null,
        expirationSource: result.expirationSource,
        lastVerifiedAt: now,
        isInvalidOnLastCheck: false,
        isExpiredOnLastCheck: false,
      );
      await _store.write(_keyMetadata, jsonEncode(updated.toJson()));

      final resolvedStatus = updated.resolveConnectionStatus(now: now);
      return CanvasOperationResult(
        succeeded: resolvedStatus != CanvasConnectionStatus.expired,
        status: resolvedStatus,
        message: resolvedStatus == CanvasConnectionStatus.expired
            ? 'Canvas token has expired.'
            : 'Canvas connection verified as ${updated.userName}.',
        metadata: updated,
      );
    } on CanvasApiException catch (e) {
      if (e.isAuthFailure || e.isExpired) {
        // Never invent an expiration date when Canvas reports expiry without a timestamp.
        final updated = existing.copyWith(
          lastVerifiedAt: now,
          isInvalidOnLastCheck: true,
          isExpiredOnLastCheck: e.isExpired,
        );
        await _store.write(_keyMetadata, jsonEncode(updated.toJson()));
        final status = e.isExpired
            ? CanvasConnectionStatus.expired
            : CanvasConnectionStatus.invalidToken;
        return CanvasOperationResult(
          succeeded: false,
          status: status,
          message: e.message,
          metadata: updated,
        );
      }

      // Transient network error: preserve existing connection metadata & status.
      return CanvasOperationResult(
        succeeded: false,
        status: existing.resolveConnectionStatus(now: now),
        message: '${e.message} Existing saved token was kept.',
        metadata: existing,
      );
    }
  }

  /// Fetches announcements and activities posted ONLY on the current local day
  /// using the active encrypted token. Never logs or returns raw secrets.
  Future<List<CanvasDailyItem>> fetchTodayUpdates({DateTime? now}) async {
    final snapshot = await loadState();
    final existing = snapshot.metadata;
    if (existing == null) {
      throw const CanvasApiException(
        'Connect your Canvas API token first to sync today\'s updates.',
        isAuthFailure: true,
      );
    }

    final current = now ?? _clock();
    if (existing.resolveConnectionStatus(now: current) ==
        CanvasConnectionStatus.expired) {
      throw const CanvasApiException(
        'Your Canvas API token has expired. Replace your token to sync today\'s updates.',
        isAuthFailure: true,
        isExpired: true,
      );
    }

    final token = await _store.read(_storageKeyForSlot(existing.slotKey));
    if (token == null || token.trim().isEmpty) {
      throw const CanvasApiException(
        'No Canvas API token is currently saved.',
        isAuthFailure: true,
      );
    }

    return _apiClient.fetchTodayAnnouncementsAndActivities(
      baseUrl: existing.baseUrl,
      token: token,
      now: current,
    );
  }

  /// Removes the saved Canvas token from local encrypted storage only.
  /// Never revokes the token on Canvas servers.
  Future<void> disconnect() async {
    await _safeDelete(_keySlotA);
    await _safeDelete(_keySlotB);
    await _safeDelete(_keyActiveSlot);
    await _safeDelete(_keyMetadata);
  }

  void dispose() {
    _apiClient.dispose();
  }

  Future<void> _rollbackCommit({
    required String? oldSlot,
    required String? oldMetadataRaw,
    required String? oldBaseUrlRaw,
    required String failedTargetKey,
  }) async {
    if (oldSlot != null) {
      await _safeWrite(_keyActiveSlot, oldSlot);
    } else {
      await _safeDelete(_keyActiveSlot);
    }
    if (oldMetadataRaw != null) {
      await _safeWrite(_keyMetadata, oldMetadataRaw);
    } else {
      await _safeDelete(_keyMetadata);
    }
    if (oldBaseUrlRaw != null) {
      await _safeWrite(_keyBaseUrl, oldBaseUrlRaw);
    }
    await _safeDelete(failedTargetKey);
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _store.write(key, value);
    } catch (_) {}
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _store.delete(key);
    } catch (_) {}
  }
}
