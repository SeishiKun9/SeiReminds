const String kDefaultCanvasBaseUrl = 'https://holynameuniversity.instructure.com';

/// Validates and normalizes a Canvas LMS base URL, requiring HTTPS.
String normalizeCanvasBaseUrl(String raw) {
  final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) {
    throw const FormatException('Enter a Canvas URL.');
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    throw const FormatException(
      'Canvas URL must be a valid HTTPS address (e.g. https://holynameuniversity.instructure.com).',
    );
  }
  return '${uri.scheme.toLowerCase()}://${uri.authority}${uri.path}'
      .replaceAll(RegExp(r'/+$'), '');
}

/// Masks a Canvas API token so the full secret is never displayed or logged.
String maskCanvasToken(String rawToken) {
  final trimmed = rawToken.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.length < 10) return '••••••••';
  return '••••••••${trimmed.substring(trimmed.length - 4)}';
}

enum CanvasConnectionStatus {
  notConnected('Not Connected'),
  connected('Connected'),
  expiringSoon('Expiring Soon'),
  expired('Expired'),
  invalidToken('Invalid Token'),
  replacementValidationFailed('Replacement Validation Failed'),
  replacementSuccessful('Replacement Successful');

  const CanvasConnectionStatus(this.label);
  final String label;
}

enum CanvasExpirationSource {
  canvasApi('canvas_api', 'Verified by Canvas API'),
  manual('manual', 'Recorded manually (Canvas API did not expose expiration)'),
  unverified('unverified', 'Cannot be verified from Canvas API');

  const CanvasExpirationSource(this.key, this.label);
  final String key;
  final String label;

  static CanvasExpirationSource fromKey(String key) {
    return switch (key) {
      'canvas_api' => CanvasExpirationSource.canvasApi,
      'manual' => CanvasExpirationSource.manual,
      _ => CanvasExpirationSource.unverified,
    };
  }
}

enum TokenExpirationWarningLevel {
  unverified,
  none,
  sevenDays,
  threeDays,
  twentyFourHours,
  expired,
}

class TokenExpirationAssessment {
  const TokenExpirationAssessment({
    required this.level,
    required this.source,
    this.expiresAt,
    this.remaining,
  });

  final TokenExpirationWarningLevel level;
  final CanvasExpirationSource source;
  final DateTime? expiresAt;
  final Duration? remaining;

  bool get isWarning =>
      level == TokenExpirationWarningLevel.sevenDays ||
      level == TokenExpirationWarningLevel.threeDays ||
      level == TokenExpirationWarningLevel.twentyFourHours ||
      level == TokenExpirationWarningLevel.expired;

  bool get isExpiringSoon =>
      level == TokenExpirationWarningLevel.sevenDays ||
      level == TokenExpirationWarningLevel.threeDays ||
      level == TokenExpirationWarningLevel.twentyFourHours;

  String get message {
    switch (level) {
      case TokenExpirationWarningLevel.unverified:
        return 'Expiration date cannot be verified from the Canvas API.';
      case TokenExpirationWarningLevel.expired:
        return 'This Canvas API token has expired. Replace your API token to restore Canvas access.';
      case TokenExpirationWarningLevel.twentyFourHours:
        final rem = remaining ?? Duration.zero;
        final hours = rem.inHours;
        final mins = rem.inMinutes.remainder(60);
        final timeText = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
        return 'Final warning (24h): Your Canvas API token expires in $timeText. Replace it immediately.';
      case TokenExpirationWarningLevel.threeDays:
        final days = ((remaining ?? Duration.zero).inHours / 24).ceil();
        return 'Urgent warning (3-day): Your Canvas API token expires in $days ${days == 1 ? 'day' : 'days'}. Replace it soon.';
      case TokenExpirationWarningLevel.sevenDays:
        final days = ((remaining ?? Duration.zero).inHours / 24).ceil();
        return 'Expiring soon (7-day warning): Your Canvas API token expires in $days days. Plan to replace it.';
      case TokenExpirationWarningLevel.none:
        final days = (remaining ?? Duration.zero).inDays;
        return 'Token is valid ($days days remaining).';
    }
  }
}

/// Evaluates token expiration thresholds: 7 days, 3 days, 24 hours, and expired.
/// Never invents an expiration date when [expiresAt] is null.
TokenExpirationAssessment evaluateTokenExpiration({
  required DateTime? expiresAt,
  required CanvasExpirationSource source,
  DateTime? now,
}) {
  if (expiresAt == null) {
    return const TokenExpirationAssessment(
      level: TokenExpirationWarningLevel.unverified,
      source: CanvasExpirationSource.unverified,
    );
  }

  final current = (now ?? DateTime.now()).toUtc();
  final remaining = expiresAt.toUtc().difference(current);

  if (remaining <= Duration.zero) {
    return TokenExpirationAssessment(
      level: TokenExpirationWarningLevel.expired,
      source: source,
      expiresAt: expiresAt.toUtc(),
      remaining: Duration.zero,
    );
  }
  if (remaining <= const Duration(hours: 24)) {
    return TokenExpirationAssessment(
      level: TokenExpirationWarningLevel.twentyFourHours,
      source: source,
      expiresAt: expiresAt.toUtc(),
      remaining: remaining,
    );
  }
  if (remaining <= const Duration(days: 3)) {
    return TokenExpirationAssessment(
      level: TokenExpirationWarningLevel.threeDays,
      source: source,
      expiresAt: expiresAt.toUtc(),
      remaining: remaining,
    );
  }
  if (remaining <= const Duration(days: 7)) {
    return TokenExpirationAssessment(
      level: TokenExpirationWarningLevel.sevenDays,
      source: source,
      expiresAt: expiresAt.toUtc(),
      remaining: remaining,
    );
  }
  return TokenExpirationAssessment(
    level: TokenExpirationWarningLevel.none,
    source: source,
    expiresAt: expiresAt.toUtc(),
    remaining: remaining,
  );
}

/// Non-secret metadata for the currently active Canvas token slot.
/// Never holds or logs raw API tokens.
class CanvasTokenMetadata {
  const CanvasTokenMetadata({
    required this.baseUrl,
    required this.slotKey,
    required this.maskedToken,
    required this.userId,
    required this.userName,
    required this.coursesAccessibleCount,
    required this.expirationSource,
    required this.lastVerifiedAt,
    this.expiresAt,
    this.isInvalidOnLastCheck = false,
    this.isExpiredOnLastCheck = false,
  });

  final String baseUrl;
  final String slotKey;
  final String maskedToken;
  final String userId;
  final String userName;
  final int coursesAccessibleCount;
  final DateTime? expiresAt;
  final CanvasExpirationSource expirationSource;
  final DateTime lastVerifiedAt;
  final bool isInvalidOnLastCheck;
  final bool isExpiredOnLastCheck;

  TokenExpirationAssessment assessExpiration({DateTime? now}) {
    if (isExpiredOnLastCheck && expiresAt == null) {
      return const TokenExpirationAssessment(
        level: TokenExpirationWarningLevel.expired,
        source: CanvasExpirationSource.unverified,
      );
    }
    return evaluateTokenExpiration(
      expiresAt: expiresAt,
      source: expirationSource,
      now: now,
    );
  }

  CanvasConnectionStatus resolveConnectionStatus({DateTime? now}) {
    if (isExpiredOnLastCheck) {
      return CanvasConnectionStatus.expired;
    }
    final assessment = assessExpiration(now: now);
    if (assessment.level == TokenExpirationWarningLevel.expired) {
      return CanvasConnectionStatus.expired;
    }
    if (isInvalidOnLastCheck) {
      return CanvasConnectionStatus.invalidToken;
    }
    if (assessment.isExpiringSoon) {
      return CanvasConnectionStatus.expiringSoon;
    }
    return CanvasConnectionStatus.connected;
  }

  CanvasTokenMetadata copyWith({
    String? baseUrl,
    String? slotKey,
    String? maskedToken,
    String? userId,
    String? userName,
    int? coursesAccessibleCount,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    CanvasExpirationSource? expirationSource,
    DateTime? lastVerifiedAt,
    bool? isInvalidOnLastCheck,
    bool? isExpiredOnLastCheck,
  }) {
    return CanvasTokenMetadata(
      baseUrl: baseUrl ?? this.baseUrl,
      slotKey: slotKey ?? this.slotKey,
      maskedToken: maskedToken ?? this.maskedToken,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      coursesAccessibleCount:
          coursesAccessibleCount ?? this.coursesAccessibleCount,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      expirationSource: expirationSource ?? this.expirationSource,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      isInvalidOnLastCheck: isInvalidOnLastCheck ?? this.isInvalidOnLastCheck,
      isExpiredOnLastCheck: isExpiredOnLastCheck ?? this.isExpiredOnLastCheck,
    );
  }

  factory CanvasTokenMetadata.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'baseUrl': final String baseUrl,
        'slotKey': final String slotKey,
        'maskedToken': final String maskedToken,
        'userId': final String userId,
        'userName': final String userName,
        'coursesAccessibleCount': final int coursesAccessibleCount,
        'expirationSource': final String expirationSourceKey,
        'lastVerifiedAt': final String lastVerifiedAtRaw,
        'isInvalidOnLastCheck': final bool isInvalidOnLastCheck,
      } =>
        CanvasTokenMetadata(
          baseUrl: baseUrl,
          slotKey: slotKey,
          maskedToken: maskedToken,
          userId: userId,
          userName: userName,
          coursesAccessibleCount: coursesAccessibleCount,
          expiresAt: json['expiresAt'] is String
              ? DateTime.parse(json['expiresAt'] as String).toUtc()
              : null,
          expirationSource: CanvasExpirationSource.fromKey(expirationSourceKey),
          lastVerifiedAt: DateTime.parse(lastVerifiedAtRaw).toUtc(),
          isInvalidOnLastCheck: isInvalidOnLastCheck,
          isExpiredOnLastCheck: json['isExpiredOnLastCheck'] == true,
        ),
      _ => throw const FormatException('Invalid CanvasTokenMetadata JSON'),
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'baseUrl': baseUrl,
        'slotKey': slotKey,
        'maskedToken': maskedToken,
        'userId': userId,
        'userName': userName,
        'coursesAccessibleCount': coursesAccessibleCount,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'expirationSource': expirationSource.key,
        'lastVerifiedAt': lastVerifiedAt.toUtc().toIso8601String(),
        'isInvalidOnLastCheck': isInvalidOnLastCheck,
        'isExpiredOnLastCheck': isExpiredOnLastCheck,
      };

  @override
  String toString() =>
      'CanvasTokenMetadata(baseUrl: $baseUrl, token: $maskedToken, user: $userName)';
}

class CanvasValidationResult {
  const CanvasValidationResult({
    required this.userId,
    required this.userName,
    required this.coursesAccessibleCount,
    required this.expirationSource,
    this.expiresAt,
  });

  final String userId;
  final String userName;
  final int coursesAccessibleCount;
  final DateTime? expiresAt;
  final CanvasExpirationSource expirationSource;

  @override
  String toString() =>
      'CanvasValidationResult(userId: $userId, userName: $userName, courses: $coursesAccessibleCount)';
}

class CanvasApiException implements Exception {
  const CanvasApiException(
    this.message, {
    this.statusCode,
    this.isAuthFailure = false,
    this.isExpired = false,
  });

  final String message;
  final int? statusCode;
  final bool isAuthFailure;
  final bool isExpired;

  @override
  String toString() => 'CanvasApiException($statusCode): $message';
}

class CanvasOperationResult {
  const CanvasOperationResult({
    required this.succeeded,
    required this.status,
    required this.message,
    this.metadata,
  });

  final bool succeeded;
  final CanvasConnectionStatus status;
  final String message;
  final CanvasTokenMetadata? metadata;
}

/// Formats a local calendar date key (`YYYY-MM-DD`) for strict current-day filtering.
String localDateKey(DateTime dt) {
  final local = dt.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Returns true ONLY when [postedAt] falls on the exact same local calendar day as [now].
/// Items from yesterday or earlier (or another day) always return false.
bool isPostedOnCurrentDay(DateTime postedAt, {DateTime? now}) {
  final localPosted = postedAt.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  return localPosted.year == localNow.year &&
      localPosted.month == localNow.month &&
      localPosted.day == localNow.day;
}

/// Strips basic HTML tags/entities and clamps message length to keep daily storage compact.
String stripCanvasHtml(String raw, {int maxLength = 240}) {
  final collapsed = raw
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (collapsed.length <= maxLength) return collapsed;
  return '${collapsed.substring(0, maxLength - 1).trimRight()}…';
}

/// Deterministic positive Android notification ID for a today-only Canvas update.
int stableCanvasNotificationId(String itemId, String postedDate) {
  var hash = 0x811C9DC5;
  final key = 'canvas|$postedDate|$itemId';
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return (hash & 0x1FFFFFFF) + 50000;
}

/// Returns the end of [dt]'s local calendar day (`23:59:59.999`) in UTC.
DateTime endOfLocalDay(DateTime dt) {
  final local = dt.toLocal();
  return DateTime(local.year, local.month, local.day, 23, 59, 59, 999).toUtc();
}

/// Returns true only when [expiresAt] is strictly in the future relative to [now].
bool isBeforeDeadline(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return false;
  final currentUtc = (now ?? DateTime.now()).toUtc();
  return expiresAt.toUtc().isAfter(currentUtc);
}

enum CanvasDailyItemKind {
  announcement('announcement', 'Announcement'),
  activity('activity', 'Activity');

  const CanvasDailyItemKind(this.key, this.label);
  final String key;
  final String label;

  static CanvasDailyItemKind fromKey(String key) {
    return key == 'announcement'
        ? CanvasDailyItemKind.announcement
        : CanvasDailyItemKind.activity;
  }
}

/// A Canvas announcement (in-memory today-only) or activity (stored temporarily
/// in SQLite ONLY until its deadline [effectiveExpiresAt] expires).
class CanvasDailyItem {
  const CanvasDailyItem({
    required this.id,
    required this.kind,
    required this.courseName,
    required this.title,
    required this.message,
    required this.postedAt,
    required this.postedDate,
    this.dueAt,
    this.expiresAt,
    this.notified = false,
  });

  final String id;
  final CanvasDailyItemKind kind;
  final String courseName;
  final String title;
  final String message;
  final DateTime postedAt;
  final String postedDate;
  final DateTime? dueAt;
  final DateTime? expiresAt;
  final bool notified;

  bool get hasExplicitDeadline => dueAt != null;

  DateTime get effectiveExpiresAt =>
      (expiresAt ?? dueAt ?? endOfLocalDay(postedAt)).toUtc();
}

class DailyCleanupResult {
  const DailyCleanupResult({
    required this.dateKey,
    required this.clearedItemsCount,
  });

  final String dateKey;
  final int clearedItemsCount;
}

class CanvasTodaySyncResult {
  const CanvasTodaySyncResult({
    required this.succeeded,
    required this.message,
    required this.todayAnnouncements,
    required this.activeActivities,
    required this.newlyNotifiedCount,
    required this.clearedStaleCount,
  });

  final bool succeeded;
  final String message;
  final List<CanvasDailyItem> todayAnnouncements;
  final List<CanvasDailyItem> activeActivities;
  final int newlyNotifiedCount;
  final int clearedStaleCount;

  List<CanvasDailyItem> get todayItems {
    final combined = <CanvasDailyItem>[
      ...todayAnnouncements,
      ...activeActivities,
    ]..sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return combined;
  }
}
