import '../../domain/models/schedule_models.dart';

/// Positioned text line extracted by on-device OCR.
class OcrTextLine {
  const OcrTextLine({
    required this.text,
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => (bottom - top).abs();
  double get centerY => (top + bottom) / 2;
}

/// Editable draft parsed from a class schedule photo before saving to SQLite.
class ParsedScheduleDraft {
  ParsedScheduleDraft({
    required this.subjectCode,
    required this.subject,
    required this.section,
    required this.classroom,
    required this.teacherName,
    required this.sessions,
    this.selected = true,
    this.sourceSnippet = '',
  });

  String subjectCode;
  String subject;
  String section;
  String classroom;
  String teacherName;
  Map<SessionType, SessionSchedule> sessions;
  bool selected;
  String sourceSnippet;

  SubjectSchedule toSubjectSchedule({
    required String id,
    int reminderMinutesBefore = 10,
    bool reminderEnabled = true,
  }) {
    final normalizedSubject =
        subject.trim().isNotEmpty ? subject.trim() : subjectCode.trim();
    final normalizedSection =
        validateSectionLetter(section) == null ? normalizeSectionLetter(section) : 'A';
    return SubjectSchedule(
      id: id,
      subjectCode: subjectCode.trim(),
      subject: normalizedSubject,
      section: normalizedSection,
      classroom: classroom.trim(),
      teacherName: teacherName.trim(),
      sessions: sessions,
      reminderMinutesBefore: reminderMinutesBefore,
      reminderEnabled: reminderEnabled,
    );
  }
}

/// Pure-Dart parser that turns on-device OCR lines or raw schedule text into
/// structured [ParsedScheduleDraft] items (code, full name, section, days,
/// time in/out, session type, classroom, and teacher name).
class SchedulePhotoParser {
  static final RegExp _timeRangePattern = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*(AM|PM|A\.M\.|P\.M\.)?\s*(?:-|–|—|\bto\b)\s*(\d{1,2})(?::(\d{2}))?\s*(AM|PM|A\.M\.|P\.M\.)?\b',
    caseSensitive: false,
  );

  static final RegExp _explicitSectionPattern = RegExp(
    r'\b(?:sec(?:tion)?|blk|block)\.?\s*[:\-]?\s*([A-Za-z])\b',
    caseSensitive: false,
  );

  static final RegExp _classroomPattern = RegExp(
    r'\b(?:(?:room|rm\.?|bldg\.?|building|hall|comp(?:uter)?\s*lab|lab(?:oratory)?|cl|avr|gym)\s*[-:#]?\s*[A-Za-z0-9]{1,6}(?:-[A-Za-z0-9]{1,5})?|(?:avr|gymnasium|gym))\b',
    caseSensitive: false,
  );

  static final RegExp _teacherPrefixedPattern = RegExp(
    r"\b(?:(?:Prof|PROF|prof|Dr|DR|dr|Engr|ENGR|engr|Atty|ATTY|atty|Mr|MR|mr|Ms|MS|ms|Mrs|MRS|mrs|Sir|SIR|sir|Ma'am|Maam|Instructor|INSTRUCTOR|Teacher|TEACHER)\.?\s*:?\s+)([A-Z][A-Za-z'.-]+(?:\s+(?:[A-Z]\.|[A-Z][A-Za-z'.-]+)){0,3})\b",
  );

  static final RegExp _teacherCommaPattern = RegExp(
    r'\b([A-Z][a-zA-Z-]+(?:\s+[A-Z][a-zA-Z-]+)?,\s+[A-Z][a-zA-Z.]+(?:\s+[A-Z]\.?)?)\b',
  );

  static final RegExp _courseCodeWithDigitsPattern = RegExp(
    r'\b([A-Z]{2,6}[\s-]?\d{1,4}[A-Z]?)\b',
  );

  static final RegExp _acronymOnlyPattern = RegExp(r'\b([A-Z]{2,6})\b');

  static const Set<String> _reservedUpperTokens = <String>{
    'AM',
    'PM',
    'MON',
    'TUE',
    'TUES',
    'WED',
    'THU',
    'THUR',
    'THURS',
    'FRI',
    'SAT',
    'SUN',
    'MWF',
    'MW',
    'WF',
    'MF',
    'TF',
    'TTH',
    'TH',
    'MTWTHF',
    'MTWTHFS',
    'MTWHF',
    'MTWH',
    'DAILY',
    'LEC',
    'LAB',
    'ONLINE',
    'SYNC',
    'SEC',
    'BLK',
    'ROOM',
    'RM',
    'BLDG',
    'TBA',
    'TBD',
    'UNITS',
    'UNIT',
    'CODE',
    'TIME',
    'DAYS',
    'DAY',
    'PROF',
    'DR',
    'MR',
    'MS',
    'MRS',
    'ENGR',
    'SIR',
    'AVR',
    'GYM',
    'CL',
    'TOTAL',
    'SCHEDULE',
    'SUBJECT',
    'SECTION',
    'TEACHER',
    'INSTRUCTOR',
    'CLASSROOM',
  };

  /// Reconstructs visual horizontal table rows from OCR bounding boxes so
  /// columns on a printed COR / timetable align on the same logical line.
  static List<String> reconstructVisualRows(List<OcrTextLine> lines) {
    final cleaned = lines
        .where((line) => line.text.trim().isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return const <String>[];

    final hasGeometry = cleaned.any((l) => l.bottom > l.top || l.right > l.left);
    if (!hasGeometry) {
      return cleaned.map((l) => l.text.trim()).toList();
    }

    cleaned.sort((a, b) {
      final byTop = a.top.compareTo(b.top);
      return byTop != 0 ? byTop : a.left.compareTo(b.left);
    });

    final rows = <List<OcrTextLine>>[];
    for (final line in cleaned) {
      List<OcrTextLine>? targetRow;
      for (final row in rows) {
        final avgY = row.fold<double>(0, (sum, e) => sum + e.centerY) / row.length;
        final avgH = row.fold<double>(0, (sum, e) => sum + (e.height > 0 ? e.height : 16)) /
            row.length;
        final tolerance = (avgH * 0.65).clamp(8.0, 40.0);
        if ((line.centerY - avgY).abs() <= tolerance) {
          targetRow = row;
          break;
        }
      }
      if (targetRow != null) {
        targetRow.add(line);
      } else {
        rows.add(<OcrTextLine>[line]);
      }
    }

    return rows.map((row) {
      row.sort((a, b) => a.left.compareTo(b.left));
      final buffer = StringBuffer();
      for (var i = 0; i < row.length; i++) {
        if (i > 0) {
          final prev = row[i - 1];
          final gap = row[i].left - prev.right;
          final refH = prev.height > 0 ? prev.height : 16;
          buffer.write(gap > refH * 0.9 ? ' | ' : ' ');
        }
        buffer.write(row[i].text.trim());
      }
      return buffer.toString().trim();
    }).toList();
  }

  /// Parses positioned OCR lines into merged, deduplicated schedule drafts.
  static List<ParsedScheduleDraft> parseOcrLines(List<OcrTextLine> lines) {
    final rows = reconstructVisualRows(lines);
    return parseRawText(rows.join('\n'));
  }

  /// Parses raw text (one or more schedule rows / stacked cards) into drafts.
  static List<ParsedScheduleDraft> parseRawText(String rawText) {
    final rawLines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (rawLines.isEmpty) return const <ParsedScheduleDraft>[];

    final entries = <_RawParsedRow>[];
    final pendingContext = <String>[];

    for (var i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      if (_isHeaderOrNoiseLine(line)) {
        pendingContext.clear();
        continue;
      }

      final timeMatch = _extractTimeRange(line);
      if (timeMatch == null) {
        // Might be the subject title line preceding a time/day line, or a
        // trailing teacher/room line for the immediately preceding entry.
        if (entries.isNotEmpty && _attachTrailingMetadata(entries.last, line)) {
          continue;
        }
        pendingContext.add(line);
        if (pendingContext.length > 2) {
          pendingContext.removeAt(0);
        }
        continue;
      }

      final combined = pendingContext.isEmpty
          ? line
          : '${pendingContext.join(' | ')} | $line';
      pendingContext.clear();

      final parsed = _parseCombinedRow(combined, timeMatch);
      if (parsed != null) {
        entries.add(parsed);
      }
    }

    return _mergeEntries(entries);
  }

  static bool _isHeaderOrNoiseLine(String line) {
    final lower = line.toLowerCase();
    final hasTime = _timeRangePattern.hasMatch(line);
    if (hasTime) return false;
    final headerHits = <String>[
      'subject code',
      'course code',
      'descriptive title',
      'time & day',
      'day/time',
      'schedule of classes',
      'certificate of registration',
      'total units',
      'student name',
      'semester',
      'school year',
    ].where(lower.contains).length;
    return headerHits >= 1;
  }

  static bool _attachTrailingMetadata(_RawParsedRow entry, String line) {
    // Only attach short standalone room/teacher lines right under a schedule row.
    if (_courseCodeWithDigitsPattern.hasMatch(line) && line.length > 18) {
      return false;
    }
    var attached = false;
    if (entry.teacherName.isEmpty) {
      final teacher = _extractTeacher(line);
      if (teacher != null) {
        entry.teacherName = teacher.value;
        attached = true;
      }
    }
    if (entry.classroom.isEmpty) {
      final room = _extractClassroom(line);
      if (room != null) {
        entry.classroom = room.value;
        attached = true;
      }
    }
    if (entry.section == null) {
      final sec = _explicitSectionPattern.firstMatch(line);
      if (sec != null) {
        entry.section = sec.group(1)!.toUpperCase();
        attached = true;
      }
    }
    return attached;
  }

  static _RawParsedRow? _parseCombinedRow(
    String combined,
    _TimeRangeMatch timeMatch,
  ) {
    var working = combined;

    // 1. Remove time range.
    working = working.replaceFirst(timeMatch.raw, ' | ');

    // 2. Extract session type hint before cleaning keywords.
    final sessionType = _detectSessionType(combined);

    // 3. Extract teacher name.
    var teacherName = '';
    final teacherMatch = _extractTeacher(working);
    if (teacherMatch != null) {
      teacherName = teacherMatch.value;
      working = working.replaceFirst(teacherMatch.raw, ' | ');
    }

    // 4. Extract classroom.
    var classroom = '';
    final roomMatch = _extractClassroom(working);
    if (roomMatch != null) {
      classroom = roomMatch.value;
      working = working.replaceFirst(roomMatch.raw, ' | ');
    }

    // 5. Extract days (Mon-Sat).
    final dayResult = _extractDays(working);
    final days = dayResult.days.isNotEmpty
        ? dayResult.days
        : const <int>[DateTime.monday];
    working = dayResult.remaining;

    // 6. Extract section letter (A-Z).
    String? section;
    final explicitSec = _explicitSectionPattern.firstMatch(working);
    if (explicitSec != null) {
      section = explicitSec.group(1)!.toUpperCase();
      working = working.replaceFirst(explicitSec.group(0)!, ' | ');
    } else {
      // Look for an isolated single-letter column (e.g., "... | B | ...").
      final segments = working.split('|').map((s) => s.trim()).toList();
      for (var i = 0; i < segments.length; i++) {
        if (RegExp(r'^[A-Za-z]$').hasMatch(segments[i])) {
          section = segments[i].toUpperCase();
          segments[i] = '';
          break;
        }
      }
      working = segments.join(' | ');
    }

    // 7. Extract separate Subject Acronym/Code and Subject Full Name.
    var subjectCode = '';
    final codeWithDigits = _findCourseCode(working);
    if (codeWithDigits != null) {
      subjectCode = codeWithDigits.value;
      working = working.replaceFirst(codeWithDigits.raw, ' | ');
    } else {
      final acronym = _findStandaloneAcronym(working);
      if (acronym != null) {
        subjectCode = acronym.value;
        working = working.replaceFirst(acronym.raw, ' | ');
      }
    }

    // 8. Clean remaining text to obtain Subject Full Name.
    final fullName = _cleanSubjectFullName(working, fallback: subjectCode);
    if (fullName.isEmpty && subjectCode.isEmpty) {
      return null;
    }

    return _RawParsedRow(
      subjectCode: subjectCode,
      subject: fullName.isNotEmpty ? fullName : subjectCode,
      section: section,
      classroom: classroom,
      teacherName: teacherName,
      sessionType: sessionType,
      days: days,
      timeIn: timeMatch.timeIn,
      timeOut: timeMatch.timeOut,
      sourceSnippet: combined,
    );
  }

  static SessionType _detectSessionType(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\b(online|zoom|gmeet|google\s*meet|ms\s*teams|synchronous|sync)\b')
        .hasMatch(lower)) {
      return SessionType.onlineTime;
    }
    if (RegExp(r'\b(laboratory|lab|comp\s*lab)\b').hasMatch(lower)) {
      return SessionType.laboratory;
    }
    return SessionType.lecture;
  }

  static _TimeRangeMatch? _extractTimeRange(String text) {
    final match = _timeRangePattern.firstMatch(text);
    if (match == null) return null;

    final startHourRaw = int.tryParse(match.group(1)!);
    final startMin = int.tryParse(match.group(2) ?? '0') ?? 0;
    final startMeridiem = _normalizeMeridiem(match.group(3));
    final endHourRaw = int.tryParse(match.group(4)!);
    final endMin = int.tryParse(match.group(5) ?? '0') ?? 0;
    final endMeridiem = _normalizeMeridiem(match.group(6));

    if (startHourRaw == null ||
        endHourRaw == null ||
        startMin < 0 ||
        startMin > 59 ||
        endMin < 0 ||
        endMin > 59 ||
        startHourRaw > 23 ||
        endHourRaw > 23) {
      return null;
    }

    int startHour;
    int endHour;

    if (startMeridiem != null && endMeridiem != null) {
      startHour = _to24Hour(startHourRaw, startMeridiem);
      endHour = _to24Hour(endHourRaw, endMeridiem);
    } else if (startMeridiem == null && endMeridiem != null) {
      endHour = _to24Hour(endHourRaw, endMeridiem);
      if (startHourRaw > 12) {
        startHour = startHourRaw;
      } else {
        final sameMeridiemStart = _to24Hour(startHourRaw, endMeridiem);
        final oppositeMeridiem = endMeridiem == 'PM' ? 'AM' : 'PM';
        final oppStart = _to24Hour(startHourRaw, oppositeMeridiem);
        final sameMinutes = sameMeridiemStart * 60 + startMin;
        final endMinutes = endHour * 60 + endMin;
        if (sameMinutes < endMinutes && (endMinutes - sameMinutes) <= 360) {
          startHour = sameMeridiemStart;
        } else {
          startHour = oppStart;
        }
      }
    } else if (startMeridiem != null && endMeridiem == null) {
      startHour = _to24Hour(startHourRaw, startMeridiem);
      if (endHourRaw > 12) {
        endHour = endHourRaw;
      } else {
        final sameEnd = _to24Hour(endHourRaw, startMeridiem);
        final oppEnd = _to24Hour(endHourRaw, startMeridiem == 'AM' ? 'PM' : 'AM');
        final startMinutes = startHour * 60 + startMin;
        if (sameEnd * 60 + endMin > startMinutes) {
          endHour = sameEnd;
        } else {
          endHour = oppEnd;
        }
      }
    } else {
      // Neither has AM/PM: use school-day heuristics (1..6 -> PM, 7..11 -> AM, 12..23 -> as-is).
      startHour = (startHourRaw >= 1 && startHourRaw <= 6)
          ? startHourRaw + 12
          : startHourRaw;
      endHour = (endHourRaw >= 1 && endHourRaw <= 6)
          ? endHourRaw + 12
          : endHourRaw;
      if (endHour * 60 + endMin <= startHour * 60 + startMin && endHour < 12) {
        endHour += 12;
      }
    }

    if (startHour < 0 || startHour > 23 || endHour < 0 || endHour > 23) {
      return null;
    }
    final timeIn = ScheduleTime(hour: startHour, minute: startMin);
    final timeOut = ScheduleTime(hour: endHour, minute: endMin);
    if (timeOut.totalMinutes <= timeIn.totalMinutes) {
      return null;
    }
    return _TimeRangeMatch(
      raw: match.group(0)!,
      timeIn: timeIn,
      timeOut: timeOut,
    );
  }

  static String? _normalizeMeridiem(String? raw) {
    if (raw == null) return null;
    final clean = raw.replaceAll('.', '').toUpperCase();
    return (clean == 'AM' || clean == 'PM') ? clean : null;
  }

  static int _to24Hour(int hour, String meridiem) {
    if (hour > 12) return hour;
    if (meridiem == 'AM') return hour == 12 ? 0 : hour;
    return hour == 12 ? 12 : hour + 12;
  }

  static ({List<int> days, String remaining}) _extractDays(String input) {
    final found = <int>{};
    var remaining = input;

    // 1. Named day ranges like "Mon-Fri", "M-F", "M-S".
    final rangeRegex = RegExp(
      r'\b(mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|[mtwfs])\s*(?:-|–|to)\s*(mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|[mtwfs])\b',
      caseSensitive: false,
    );
    for (final m in rangeRegex.allMatches(remaining).toList()) {
      final start = _singleDayNameToInt(m.group(1)!);
      final end = _singleDayNameToInt(m.group(2)!);
      if (start != null && end != null && start <= end) {
        for (var d = start; d <= end; d++) {
          found.add(d);
        }
        remaining = remaining.replaceFirst(m.group(0)!, ' | ');
      }
    }

    // 2. Full / abbreviated day words (Mon, Tue, Wed, Thu, Fri, Sat).
    final wordRegex = RegExp(
      r'\b(monday|mon\.?|tuesday|tues\.?|tue\.?|wednesday|wed\.?|thursday|thurs\.?|thur\.?|thu\.?|friday|fri\.?|saturday|sat\.?)\b',
      caseSensitive: false,
    );
    for (final m in wordRegex.allMatches(remaining).toList()) {
      final d = _singleDayNameToInt(m.group(1)!);
      if (d != null) {
        found.add(d);
        remaining = remaining.replaceFirst(m.group(0)!, ' ');
      }
    }

    // 3. Compact Filipino / university day codes: MWF, TTh, TTH, MW, WF, MTWThF, M/W/F, T/Th, Th.
    final compactRegex = RegExp(
      r'\b((?:(?:Th|TH|Th\.|[MTWFS])[/,\s]?){1,6})\b',
    );
    for (final m in compactRegex.allMatches(remaining).toList()) {
      final token = m.group(1)!.trim();
      final compact = token.replaceAll(RegExp(r'[/,\s.]'), '');
      if (compact.isEmpty) continue;
      // Avoid grabbing single-letter section tokens unless it's multi-day or "Th".
      if (compact.length == 1 && !RegExp(r'^[MWF]$').hasMatch(compact)) {
        continue;
      }
      // Require either mixed/upper case day codes (MWF, TTh, Th, T/Th, M/W/F).
      final parsedDays = _parseCompactDayCode(compact);
      if (parsedDays != null && parsedDays.isNotEmpty) {
        // Guard against plain English words or acronyms by checking strict pattern.
        if (compact.length >= 2 || found.isEmpty) {
          found.addAll(parsedDays);
          remaining = remaining.replaceFirst(m.group(0)!, ' | ');
        }
      }
    }

    final sorted = found.toList()..sort();
    return (days: sorted, remaining: remaining);
  }

  static int? _singleDayNameToInt(String token) {
    final lower = token.toLowerCase().replaceAll('.', '');
    if (lower.startsWith('mon') || lower == 'm') return DateTime.monday;
    if (lower.startsWith('tue') || lower == 't') return DateTime.tuesday;
    if (lower.startsWith('wed') || lower == 'w') return DateTime.wednesday;
    if (lower.startsWith('thu') || lower == 'th') return DateTime.thursday;
    if (lower.startsWith('fri') || lower == 'f') return DateTime.friday;
    if (lower.startsWith('sat') || lower == 's') return DateTime.saturday;
    return null;
  }

  static Set<int>? _parseCompactDayCode(String compact) {
    final upper = compact.toUpperCase();
    // Ensure every character is a valid day code letter (M, T, W, H, F, S) and
    // H only follows T (Th) or stands alone as H (rare US university Thu).
    if (!RegExp(r'^[MTWHFS]+$').hasMatch(upper)) return null;
    // Reject tokens like "MS" (Microsoft / Ms.) or "FM" or "SF".
    if (upper == 'MS' || upper == 'FM' || upper == 'SF' || upper == 'ST') {
      return null;
    }

    final days = <int>{};
    var i = 0;
    while (i < upper.length) {
      if (upper[i] == 'T' && i + 1 < upper.length && upper[i + 1] == 'H') {
        days.add(DateTime.thursday);
        i += 2;
      } else {
        switch (upper[i]) {
          case 'M':
            days.add(DateTime.monday);
          case 'T':
            days.add(DateTime.tuesday);
          case 'W':
            days.add(DateTime.wednesday);
          case 'H':
            days.add(DateTime.thursday);
          case 'F':
            days.add(DateTime.friday);
          case 'S':
            days.add(DateTime.saturday);
          default:
            return null;
        }
        i++;
      }
    }
    return days;
  }

  static ({String raw, String value})? _extractClassroom(String text) {
    final m = _classroomPattern.firstMatch(text);
    if (m == null) return null;
    final raw = m.group(0)!.trim();
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ');
    return (raw: raw, value: normalized);
  }

  static ({String raw, String value})? _extractTeacher(String text) {
    final prefixed = _teacherPrefixedPattern.firstMatch(text);
    if (prefixed != null) {
      var raw = prefixed.group(0)!.trim();
      raw = raw.replaceFirst(
        RegExp(r'^(?:instructor|teacher)\s*:\s*', caseSensitive: false),
        '',
      );
      return (raw: prefixed.group(0)!, value: raw.replaceAll(RegExp(r'\s+'), ' '));
    }
    final comma = _teacherCommaPattern.firstMatch(text);
    if (comma != null) {
      final val = comma.group(1)!.trim();
      return (raw: comma.group(0)!, value: val);
    }
    return null;
  }

  static ({String raw, String value})? _findCourseCode(String text) {
    for (final m in _courseCodeWithDigitsPattern.allMatches(text)) {
      final candidate = m.group(1)!.trim();
      final prefix = candidate.split(RegExp(r'[\s\d-]')).first.toUpperCase();
      if (_reservedUpperTokens.contains(prefix)) continue;
      return (raw: m.group(0)!, value: candidate.replaceAll(RegExp(r'\s+'), ' '));
    }
    return null;
  }

  static ({String raw, String value})? _findStandaloneAcronym(String text) {
    final segments = text.split('|').map((s) => s.trim()).toList();
    for (final seg in segments) {
      if (RegExp(r'^[A-Z]{2,6}$').hasMatch(seg) &&
          !_reservedUpperTokens.contains(seg)) {
        return (raw: seg, value: seg);
      }
    }
    for (final m in _acronymOnlyPattern.allMatches(text)) {
      final token = m.group(1)!;
      if (_reservedUpperTokens.contains(token)) continue;
      // Only treat as acronym if there is also descriptive full-name text present.
      final rest = text.replaceFirst(token, '').trim();
      if (RegExp(r'[a-z]{3,}').hasMatch(rest)) {
        return (raw: token, value: token);
      }
    }
    return null;
  }

  static String _cleanSubjectFullName(String text, {required String fallback}) {
    final segments = text
        .split('|')
        .map((seg) {
          var s = seg.trim();
          s = s.replaceAll(
            RegExp(
              r'\b(?:lec(?:ture)?|lab(?:oratory)?|online|sync|tba|tbd|units?)\b',
              caseSensitive: false,
            ),
            ' ',
          );
          // Drop pure numbers (e.g., unit count "3" or "3.0").
          s = s.replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), ' ');
          s = s.replaceAll(RegExp(r'^[\s\-–—:,./()]+|[\s\-–—:,./()]+$'), '');
          s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
          return s;
        })
        .where((s) => s.length >= 2)
        .toList();

    if (segments.isEmpty) return fallback;
    // Prefer the longest descriptive segment as the full subject title.
    segments.sort((a, b) => b.length.compareTo(a.length));
    return segments.first;
  }

  static List<ParsedScheduleDraft> _mergeEntries(List<_RawParsedRow> rows) {
    final merged = <String, ParsedScheduleDraft>{};
    for (final row in rows) {
      final sec = row.section ?? 'A';
      final keyBase = row.subjectCode.isNotEmpty
          ? row.subjectCode.toLowerCase()
          : row.subject.toLowerCase();
      final key = '$keyBase|$sec';

      final session = SessionSchedule(
        type: row.sessionType,
        days: row.days,
        timeIn: row.timeIn,
        timeOut: row.timeOut,
      );

      final existing = merged[key];
      if (existing != null && !existing.sessions.containsKey(row.sessionType)) {
        final nextSessions = Map<SessionType, SessionSchedule>.of(existing.sessions);
        nextSessions[row.sessionType] = session;
        existing.sessions = nextSessions;
        if (existing.classroom.isEmpty && row.classroom.isNotEmpty) {
          existing.classroom = row.classroom;
        }
        if (existing.teacherName.isEmpty && row.teacherName.isNotEmpty) {
          existing.teacherName = row.teacherName;
        }
        if (existing.subject == existing.subjectCode &&
            row.subject.length > existing.subject.length) {
          existing.subject = row.subject;
        }
        existing.sourceSnippet = '${existing.sourceSnippet}\n${row.sourceSnippet}';
      } else {
        final uniqueKey = merged.containsKey(key)
            ? '$key|${merged.length}'
            : key;
        merged[uniqueKey] = ParsedScheduleDraft(
          subjectCode: row.subjectCode,
          subject: row.subject,
          section: sec,
          classroom: row.classroom,
          teacherName: row.teacherName,
          sessions: <SessionType, SessionSchedule>{row.sessionType: session},
          sourceSnippet: row.sourceSnippet,
        );
      }
    }
    return merged.values.toList();
  }
}

class _TimeRangeMatch {
  const _TimeRangeMatch({
    required this.raw,
    required this.timeIn,
    required this.timeOut,
  });

  final String raw;
  final ScheduleTime timeIn;
  final ScheduleTime timeOut;
}

class _RawParsedRow {
  _RawParsedRow({
    required this.subjectCode,
    required this.subject,
    required this.section,
    required this.classroom,
    required this.teacherName,
    required this.sessionType,
    required this.days,
    required this.timeIn,
    required this.timeOut,
    required this.sourceSnippet,
  });

  String subjectCode;
  String subject;
  String? section;
  String classroom;
  String teacherName;
  SessionType sessionType;
  List<int> days;
  ScheduleTime timeIn;
  ScheduleTime timeOut;
  String sourceSnippet;
}
