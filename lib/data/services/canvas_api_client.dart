import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/models/canvas_token_models.dart';

/// Authenticated Canvas LMS REST client for token validation and expiry probing.
/// Read-only GET requests only — never revokes tokens automatically and never logs secrets.
// shortcut: direct HTTPS to Canvas LMS (no Supabase backend yet); swap client transport if routing through Edge Functions later.
class CanvasApiClient {
  CanvasApiClient({
    http.Client? httpClient,
    this._timeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Duration _timeout;

  Map<String, String> _authHeaders(String token) => <String, String>{
        HttpHeaders.authorizationHeader: 'Bearer $token',
        HttpHeaders.acceptHeader: 'application/json',
      };

  /// Validates that [token] authenticates with Canvas and can access required
  /// user profile and active courses endpoints, and probes expiration if exposed.
  Future<CanvasValidationResult> validateToken({
    required String baseUrl,
    required String token,
    DateTime? manualExpiresAt,
  }) async {
    final normalizedBase = normalizeCanvasBaseUrl(baseUrl);
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const CanvasApiException(
        'API token cannot be empty.',
        isAuthFailure: true,
      );
    }

    final headers = _authHeaders(trimmedToken);

    // 1. Verify authentication and identity.
    final profileResponse = await _safeGet(
      Uri.parse('$normalizedBase/api/v1/users/self/profile'),
      headers: headers,
    );
    _assertSuccess(
      profileResponse,
      contextLabel: 'Canvas profile verification',
    );
    final profileJson = _decodeJsonMap(
      profileResponse.body,
      contextLabel: 'Canvas profile response',
    );
    final userId = profileJson['id']?.toString() ?? '';
    final userName = (profileJson['name'] as String?)?.trim() ??
        (profileJson['short_name'] as String?)?.trim() ??
        'Canvas User';
    if (userId.isEmpty) {
      throw const CanvasApiException(
        'Canvas profile response did not include a user ID.',
      );
    }

    // 2. Verify access to required Canvas course/schedule data.
    final coursesResponse = await _safeGet(
      Uri.parse(
        '$normalizedBase/api/v1/courses?enrollment_state=active&per_page=10',
      ),
      headers: headers,
    );
    _assertSuccess(
      coursesResponse,
      contextLabel: 'Canvas courses access check',
    );
    final coursesList = _decodeJsonList(
      coursesResponse.body,
      contextLabel: 'Canvas courses response',
    );

    // 3. Probe token expiration if exposed by Canvas API. Never invent a date.
    final apiExpiresAt = await _probeExpirationFromApi(
      normalizedBase: normalizedBase,
      headers: headers,
      token: trimmedToken,
      profileResponseHeaders: profileResponse.headers,
    );

    if (apiExpiresAt != null) {
      return CanvasValidationResult(
        userId: userId,
        userName: userName,
        coursesAccessibleCount: coursesList.length,
        expiresAt: apiExpiresAt,
        expirationSource: CanvasExpirationSource.canvasApi,
      );
    }

    if (manualExpiresAt != null) {
      return CanvasValidationResult(
        userId: userId,
        userName: userName,
        coursesAccessibleCount: coursesList.length,
        expiresAt: manualExpiresAt.toUtc(),
        expirationSource: CanvasExpirationSource.manual,
      );
    }

    return CanvasValidationResult(
      userId: userId,
      userName: userName,
      coursesAccessibleCount: coursesList.length,
      expirationSource: CanvasExpirationSource.unverified,
    );
  }

  /// Lightweight confirmation check executed after saving a replacement token
  /// to confirm the saved token works before deleting the previous token.
  Future<void> confirmTokenWorking({
    required String baseUrl,
    required String token,
  }) async {
    final normalizedBase = normalizeCanvasBaseUrl(baseUrl);
    final response = await _safeGet(
      Uri.parse('$normalizedBase/api/v1/users/self/profile'),
      headers: _authHeaders(token.trim()),
    );
    _assertSuccess(
      response,
      contextLabel: 'post-save Canvas confirmation',
    );
  }

  Future<DateTime?> _probeExpirationFromApi({
    required String normalizedBase,
    required Map<String, String> headers,
    required String token,
    required Map<String, String> profileResponseHeaders,
  }) async {
    final headerExpiry = profileResponseHeaders['x-token-expires-at'] ??
        profileResponseHeaders['x-canvas-token-expires-at'];
    if (headerExpiry != null && headerExpiry.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(headerExpiry.trim());
      if (parsed != null) return parsed.toUtc();
    }

    // Standard Canvas instances often block /users/self/tokens for personal tokens;
    // treat any error or empty match as unverified rather than failing validation.
    try {
      final response = await _httpClient
          .get(
            Uri.parse('$normalizedBase/api/v1/users/self/tokens?per_page=50'),
            headers: headers,
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! List<dynamic> || decoded.isEmpty) return null;

      final tokenMaps = decoded.whereType<Map<String, dynamic>>().toList();
      if (tokenMaps.isEmpty) return null;

      final matched = _matchTokenMetadataRow(tokenMaps, token);
      final rawExpires = matched?['expires_at'];
      if (rawExpires is String && rawExpires.trim().isNotEmpty) {
        return DateTime.tryParse(rawExpires.trim())?.toUtc();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _matchTokenMetadataRow(
    List<Map<String, dynamic>> rows,
    String rawToken,
  ) {
    // Canvas access tokens expose a short `hint` prefix (e.g. first chars after `~`).
    final tildeIndex = rawToken.indexOf('~');
    final secretPart =
        tildeIndex >= 0 ? rawToken.substring(tildeIndex + 1) : rawToken;

    final matches = rows.where((row) {
      final hint = (row['hint'] as String?)?.trim() ?? '';
      if (hint.isEmpty) return false;
      return rawToken.startsWith(hint) ||
          secretPart.startsWith(hint) ||
          rawToken.endsWith(hint);
    }).toList();

    if (matches.length == 1) return matches.first;
    if (rows.length == 1 && rows.first['expires_at'] is String) {
      return rows.first;
    }
    return null;
  }

  Future<http.Response> _safeGet(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    try {
      return await _httpClient.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw const CanvasApiException(
        'Connection to Canvas timed out. Check your internet connection and retry.',
      );
    } on SocketException {
      throw const CanvasApiException(
        'Could not reach Canvas server. Check your internet connection and Canvas URL.',
      );
    } on http.ClientException {
      throw const CanvasApiException(
        'Network error while contacting Canvas. Check your connection and retry.',
      );
    }
  }

  void _assertSuccess(
    http.Response response, {
    required String contextLabel,
  }) {
    if (response.statusCode == 200) return;

    final lowerBody = response.body.toLowerCase();
    final lowerAuthHeader =
        (response.headers['www-authenticate'] ?? '').toLowerCase();
    final mentionsExpired = lowerBody.contains('expired') ||
        lowerAuthHeader.contains('expired');

    if (response.statusCode == 401) {
      throw CanvasApiException(
        mentionsExpired
            ? 'Canvas rejected the token because it has expired (HTTP 401).'
            : 'Invalid or unauthorized Canvas API token (HTTP 401).',
        statusCode: 401,
        isAuthFailure: true,
        isExpired: mentionsExpired,
      );
    }
    if (response.statusCode == 403) {
      throw CanvasApiException(
        'Canvas denied access during $contextLabel (HTTP 403). Verify token permissions.',
        statusCode: 403,
        isAuthFailure: true,
      );
    }
    throw CanvasApiException(
      'Canvas returned HTTP ${response.statusCode} during $contextLabel.',
      statusCode: response.statusCode,
    );
  }

  Map<String, dynamic> _decodeJsonMap(
    String body, {
    required String contextLabel,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Handled uniformly below.
    }
    throw CanvasApiException('Unexpected non-JSON $contextLabel from Canvas.');
  }

  List<dynamic> _decodeJsonList(
    String body, {
    required String contextLabel,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is List<dynamic>) return decoded;
    } on FormatException {
      // Handled uniformly below.
    }
    throw CanvasApiException('Unexpected $contextLabel format from Canvas.');
  }

  void dispose() {
    _httpClient.close();
  }
}
