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

  /// Fetches Canvas announcements and activity stream items posted ONLY on the
  /// current local day. Items from yesterday or earlier are strictly discarded.
  Future<List<CanvasDailyItem>> fetchTodayAnnouncementsAndActivities({
    required String baseUrl,
    required String token,
    DateTime? now,
  }) async {
    final normalizedBase = normalizeCanvasBaseUrl(baseUrl);
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw const CanvasApiException(
        'API token cannot be empty.',
        isAuthFailure: true,
      );
    }

    final current = now ?? DateTime.now();
    final todayKey = localDateKey(current);
    final headers = _authHeaders(trimmedToken);

    // 1. Load active courses so we can resolve course names and query announcements.
    final coursesResponse = await _safeGet(
      Uri.parse(
        '$normalizedBase/api/v1/courses?enrollment_state=active&per_page=50',
      ),
      headers: headers,
    );
    _assertSuccess(
      coursesResponse,
      contextLabel: 'Canvas courses fetch',
    );
    final coursesList = _decodeJsonList(
      coursesResponse.body,
      contextLabel: 'Canvas courses response',
    );

    final courseNames = <String, String>{};
    final contextCodes = <String>[];
    for (final raw in coursesList.whereType<Map<String, dynamic>>()) {
      final id = raw['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = (raw['name'] as String?)?.trim() ??
          (raw['course_code'] as String?)?.trim() ??
          'Course $id';
      courseNames[id] = name;
      if (contextCodes.length < 20) {
        contextCodes.add('course_$id');
      }
    }

    final itemsById = <String, CanvasDailyItem>{};
    final seenAnnouncementIds = <String>{};

    // 2. Fetch course announcements for today and filter strictly by local current day.
    if (contextCodes.isNotEmpty) {
      final queryParts = <String>[
        for (final code in contextCodes)
          'context_codes[]=${Uri.encodeQueryComponent(code)}',
        'start_date=${Uri.encodeQueryComponent(todayKey)}',
        'end_date=${Uri.encodeQueryComponent(todayKey)}',
        'per_page=50',
      ];
      final announcementsUri = Uri.parse(
        '$normalizedBase/api/v1/announcements?${queryParts.join('&')}',
      );
      final annResponse = await _safeGet(announcementsUri, headers: headers);
      _assertSuccess(annResponse, contextLabel: 'Canvas announcements fetch');
      final annList = _decodeJsonList(
        annResponse.body,
        contextLabel: 'Canvas announcements response',
      );

      for (final raw in annList.whereType<Map<String, dynamic>>()) {
        final rawId = raw['id']?.toString() ?? '';
        final postedRaw =
            (raw['posted_at'] as String?) ?? (raw['created_at'] as String?);
        if (rawId.isEmpty || postedRaw == null) continue;
        final postedAt = DateTime.tryParse(postedRaw)?.toUtc();
        if (postedAt == null || !isPostedOnCurrentDay(postedAt, now: current)) {
          continue;
        }

        final contextCode = (raw['context_code'] as String?) ?? '';
        final courseId = contextCode.startsWith('course_')
            ? contextCode.substring('course_'.length)
            : '';
        final courseName = courseNames[courseId] ?? 'Canvas Course';
        final title = (raw['title'] as String?)?.trim();
        final message = stripCanvasHtml((raw['message'] as String?) ?? '');
        final canonicalId = 'ann_$rawId';
        seenAnnouncementIds.add(rawId);

        itemsById[canonicalId] = CanvasDailyItem(
          id: canonicalId,
          kind: CanvasDailyItemKind.announcement,
          courseName: courseName,
          title: (title != null && title.isNotEmpty) ? title : 'Announcement',
          message: message,
          postedAt: postedAt,
          postedDate: todayKey,
        );
      }
    }

    // 3. Fetch personal activity stream (today's activities + deadline-bearing activities).
    final streamResponse = await _safeGet(
      Uri.parse('$normalizedBase/api/v1/users/self/activity_stream?per_page=50'),
      headers: headers,
    );
    _assertSuccess(streamResponse, contextLabel: 'Canvas activity stream fetch');
    final streamList = _decodeJsonList(
      streamResponse.body,
      contextLabel: 'Canvas activity stream response',
    );

    final seenAssignmentIds = <String>{};

    for (final raw in streamList.whereType<Map<String, dynamic>>()) {
      final rawId = raw['id']?.toString() ?? '';
      // Prefer created_at (when the activity was sent); fall back to updated_at only if absent.
      final sentRaw =
          (raw['created_at'] as String?) ?? (raw['updated_at'] as String?);
      if (rawId.isEmpty || sentRaw == null) continue;
      final postedAt = DateTime.tryParse(sentRaw)?.toUtc();
      if (postedAt == null) continue;

      final typeRaw = (raw['type'] as String?)?.trim() ?? 'Activity';
      final isAnnouncement = typeRaw.toLowerCase() == 'announcement';

      // Extract optional assignment deadline (due_at) if present on activity.
      final assignmentMap = raw['assignment'] is Map<String, dynamic>
          ? raw['assignment'] as Map<String, dynamic>
          : null;
      final rawDue = (assignmentMap?['due_at'] as String?) ??
          (raw['due_at'] as String?);
      final dueAt = rawDue != null ? DateTime.tryParse(rawDue)?.toUtc() : null;

      if (isAnnouncement) {
        if (!isPostedOnCurrentDay(postedAt, now: current)) continue;
        final linkedAnnouncementId = raw['announcement_id']?.toString() ?? rawId;
        if (seenAnnouncementIds.contains(linkedAnnouncementId)) continue;
        final courseId = raw['course_id']?.toString() ?? '';
        final courseName = courseNames[courseId] ?? 'Canvas';
        final title = (raw['title'] as String?)?.trim();
        final message = stripCanvasHtml((raw['message'] as String?) ?? '');
        final canonicalId = 'ann_$linkedAnnouncementId';

        itemsById.putIfAbsent(
          canonicalId,
          () => CanvasDailyItem(
            id: canonicalId,
            kind: CanvasDailyItemKind.announcement,
            courseName: courseName,
            title: (title != null && title.isNotEmpty) ? title : 'Announcement',
            message: message,
            postedAt: postedAt,
            postedDate: todayKey,
          ),
        );
        continue;
      }

      // Activity filtering:
      // - If an explicit deadline exists, keep only while deadline is still ahead.
      // - Otherwise keep only if posted today (expires at end of current local day).
      if (dueAt != null) {
        if (!isBeforeDeadline(dueAt, now: current)) continue;
      } else if (!isPostedOnCurrentDay(postedAt, now: current)) {
        continue;
      }

      final assignmentId = assignmentMap?['id']?.toString() ??
          raw['assignment_id']?.toString();
      if (assignmentId != null && assignmentId.isNotEmpty) {
        seenAssignmentIds.add(assignmentId);
      }

      final courseId = raw['course_id']?.toString() ?? '';
      final courseName = courseNames[courseId] ?? 'Canvas';
      final title = (raw['title'] as String?)?.trim();
      final message = stripCanvasHtml((raw['message'] as String?) ?? '');
      final canonicalId = assignmentId != null && assignmentId.isNotEmpty
          ? 'act_assignment_$assignmentId'
          : 'act_${typeRaw.toLowerCase()}_$rawId';

      itemsById.putIfAbsent(
        canonicalId,
        () => CanvasDailyItem(
          id: canonicalId,
          kind: CanvasDailyItemKind.activity,
          courseName: courseName,
          title: (title != null && title.isNotEmpty) ? title : typeRaw,
          message: message,
          postedAt: postedAt,
          postedDate: localDateKey(postedAt),
          dueAt: dueAt,
          expiresAt: dueAt ?? endOfLocalDay(current),
        ),
      );
    }

    // 4. Best-effort fetch of upcoming Canvas assignment activities with explicit deadlines.
    try {
      final upcomingResponse = await _httpClient
          .get(
            Uri.parse('$normalizedBase/api/v1/users/self/upcoming_events'),
            headers: headers,
          )
          .timeout(_timeout);
      if (upcomingResponse.statusCode == 200) {
        final decoded = jsonDecode(upcomingResponse.body);
        if (decoded is List<dynamic>) {
          for (final raw in decoded.whereType<Map<String, dynamic>>()) {
            final assignment = raw['assignment'] is Map<String, dynamic>
                ? raw['assignment'] as Map<String, dynamic>
                : null;
            final rawDue = (assignment?['due_at'] as String?) ??
                (raw['end_at'] as String?) ??
                (raw['start_at'] as String?);
            if (rawDue == null) continue;
            final dueAt = DateTime.tryParse(rawDue)?.toUtc();
            if (dueAt == null || !isBeforeDeadline(dueAt, now: current)) {
              continue;
            }

            final assignmentId =
                assignment?['id']?.toString() ?? raw['id']?.toString() ?? '';
            if (assignmentId.isEmpty || seenAssignmentIds.contains(assignmentId)) {
              continue;
            }
            seenAssignmentIds.add(assignmentId);

            final contextCode = (raw['context_code'] as String?) ?? '';
            final courseId = contextCode.startsWith('course_')
                ? contextCode.substring('course_'.length)
                : (assignment?['course_id']?.toString() ?? '');
            final courseName = (raw['context_name'] as String?)?.trim() ??
                courseNames[courseId] ??
                'Canvas Course';
            final title = (raw['title'] as String?)?.trim() ??
                (assignment?['name'] as String?)?.trim() ??
                'Upcoming Activity';
            final message = stripCanvasHtml(
              (raw['description'] as String?) ??
                  (assignment?['description'] as String?) ??
                  '',
            );
            final postedRaw = (assignment?['created_at'] as String?) ??
                (raw['created_at'] as String?);
            final postedAt =
                (postedRaw != null ? DateTime.tryParse(postedRaw) : null)
                    ?.toUtc() ??
                current.toUtc();
            final canonicalId = 'act_assignment_$assignmentId';

            itemsById.putIfAbsent(
              canonicalId,
              () => CanvasDailyItem(
                id: canonicalId,
                kind: CanvasDailyItemKind.activity,
                courseName: courseName,
                title: title,
                message: message,
                postedAt: postedAt,
                postedDate: localDateKey(postedAt),
                dueAt: dueAt,
                expiresAt: dueAt,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Upcoming events endpoint is optional; activity stream results remain valid.
    }

    final result = itemsById.values.toList()
      ..sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return result;
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
