const List<int> kSchoolWeekdays = <int>[1, 2, 3, 4, 5, 6];
const List<int> kReminderLeadOptions = <int>[0, 5, 10, 15, 30];

final RegExp _singleLetterPattern = RegExp(r'^[A-Za-z]$');

String weekdayShortLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => throw RangeError.range(weekday, 1, 7, 'weekday'),
  };
}

String weekdayFullLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => throw RangeError.range(weekday, 1, 7, 'weekday'),
  };
}

String formatReminderLead(int minutes) {
  if (minutes <= 0) return 'At Time In';
  return '$minutes min before';
}

/// Validates a single ASCII section letter (A–Z, case-insensitive).
String? validateSectionLetter(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Pick or type a section letter (A–Z)';
  }
  if (trimmed.length > 1) {
    return 'Enter only 1 letter (A–Z)';
  }
  if (!_singleLetterPattern.hasMatch(trimmed)) {
    return 'Section must be a letter from A to Z';
  }
  return null;
}

String normalizeSectionLetter(String value) {
  final error = validateSectionLetter(value);
  if (error != null) {
    throw FormatException(error);
  }
  return value.trim().toUpperCase();
}

enum SessionType {
  onlineTime('online_time', 'Online Time', 'Online'),
  lecture('lecture', 'Lecture', 'Lecture'),
  laboratory('laboratory', 'Laboratory', 'Lab');

  const SessionType(this.key, this.label, this.shortLabel);

  final String key;
  final String label;
  final String shortLabel;

  static SessionType fromKey(String key) {
    return switch (key) {
      'online_time' => SessionType.onlineTime,
      'lecture' => SessionType.lecture,
      'laboratory' => SessionType.laboratory,
      _ => throw FormatException('Unknown session type: $key'),
    };
  }
}

class ScheduleTime implements Comparable<ScheduleTime> {
  const ScheduleTime({required this.hour, required this.minute})
      : assert(hour >= 0 && hour <= 23),
        assert(minute >= 0 && minute <= 59);

  final int hour;
  final int minute;

  int get totalMinutes => hour * 60 + minute;

  String format12Hour() {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final displayMinute = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMinute $period';
  }

  factory ScheduleTime.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {'hour': final int hour, 'minute': final int minute}
          when hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 =>
        ScheduleTime(hour: hour, minute: minute),
      _ => throw const FormatException('Invalid ScheduleTime JSON'),
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hour': hour,
        'minute': minute,
      };

  @override
  int compareTo(ScheduleTime other) => totalMinutes.compareTo(other.totalMinutes);

  @override
  bool operator ==(Object other) =>
      other is ScheduleTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => format12Hour();
}

class SessionSchedule {
  SessionSchedule({
    required this.type,
    required Iterable<int> days,
    required this.timeIn,
    required this.timeOut,
  }) : days = List<int>.unmodifiable(
          (days.toSet().toList()..sort()),
        );

  final SessionType type;
  final List<int> days;
  final ScheduleTime timeIn;
  final ScheduleTime timeOut;

  String? validate() {
    if (days.isEmpty) {
      return 'Pick at least one day (Mon–Sat) for ${type.label}';
    }
    if (days.any((d) => d < DateTime.monday || d > DateTime.saturday)) {
      return '${type.label} days must be Monday to Saturday';
    }
    if (timeOut.totalMinutes <= timeIn.totalMinutes) {
      return '${type.label} Time Out must be after Time In';
    }
    return null;
  }

  String formatTimeRange() => '${timeIn.format12Hour()} – ${timeOut.format12Hour()}';

  String formatDaysSummary() => days.map(weekdayShortLabel).join(', ');

  factory SessionSchedule.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'type': final String typeKey,
        'days': final List<dynamic> rawDays,
        'timeIn': final Map<String, dynamic> rawTimeIn,
        'timeOut': final Map<String, dynamic> rawTimeOut,
      } =>
        () {
          final days = rawDays.map((dynamic d) {
            if (d is! int || d < DateTime.monday || d > DateTime.saturday) {
              throw const FormatException('Session weekday must be 1..6');
            }
            return d;
          }).toList();
          final session = SessionSchedule(
            type: SessionType.fromKey(typeKey),
            days: days,
            timeIn: ScheduleTime.fromJson(rawTimeIn),
            timeOut: ScheduleTime.fromJson(rawTimeOut),
          );
          final error = session.validate();
          if (error != null) {
            throw FormatException(error);
          }
          return session;
        }(),
      _ => throw const FormatException('Invalid SessionSchedule JSON'),
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.key,
        'days': days,
        'timeIn': timeIn.toJson(),
        'timeOut': timeOut.toJson(),
      };
}

class SubjectSchedule {
  SubjectSchedule({
    required this.id,
    required String subject,
    required String section,
    required Map<SessionType, SessionSchedule> sessions,
    this.reminderMinutesBefore = 10,
    this.reminderEnabled = true,
    DateTime? updatedAt,
  })  : subject = subject.trim(),
        section = normalizeSectionLetter(section),
        sessions = Map<SessionType, SessionSchedule>.unmodifiable(sessions),
        updatedAt = (updatedAt ?? DateTime.now()).toUtc() {
    if (this.subject.isEmpty) {
      throw const FormatException('Subject name cannot be empty');
    }
    if (this.sessions.isEmpty) {
      throw const FormatException(
        'Select at least one session (Online Time, Lecture, or Laboratory)',
      );
    }
    if (reminderMinutesBefore < 0 || reminderMinutesBefore > 120) {
      throw const FormatException('Reminder lead time must be 0–120 minutes');
    }
    for (final entry in this.sessions.entries) {
      if (entry.key != entry.value.type) {
        throw const FormatException('Session map key does not match session type');
      }
      final error = entry.value.validate();
      if (error != null) {
        throw FormatException(error);
      }
    }
  }

  final String id;
  final String subject;
  final String section;
  final Map<SessionType, SessionSchedule> sessions;
  final int reminderMinutesBefore;
  final bool reminderEnabled;
  final DateTime updatedAt;

  SubjectSchedule copyWith({
    String? id,
    String? subject,
    String? section,
    Map<SessionType, SessionSchedule>? sessions,
    int? reminderMinutesBefore,
    bool? reminderEnabled,
    DateTime? updatedAt,
  }) {
    return SubjectSchedule(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      section: section ?? this.section,
      sessions: sessions ?? this.sessions,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  factory SubjectSchedule.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': final String id,
        'subject': final String subject,
        'section': final String section,
        'sessions': final List<dynamic> rawSessions,
        'reminderMinutesBefore': final int reminderMinutesBefore,
        'reminderEnabled': final bool reminderEnabled,
        'updatedAt': final String updatedAtRaw,
      } =>
        () {
          final parsedSessions = <SessionType, SessionSchedule>{};
          for (final dynamic item in rawSessions) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid session entry');
            }
            final session = SessionSchedule.fromJson(item);
            parsedSessions[session.type] = session;
          }
          return SubjectSchedule(
            id: id,
            subject: subject,
            section: section,
            sessions: parsedSessions,
            reminderMinutesBefore: reminderMinutesBefore,
            reminderEnabled: reminderEnabled,
            updatedAt: DateTime.parse(updatedAtRaw),
          );
        }(),
      _ => throw const FormatException('Invalid SubjectSchedule JSON'),
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'subject': subject,
        'section': section,
        'sessions': sessions.values.map((s) => s.toJson()).toList(),
        'reminderMinutesBefore': reminderMinutesBefore,
        'reminderEnabled': reminderEnabled,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class DaySessionItem implements Comparable<DaySessionItem> {
  const DaySessionItem({
    required this.schedule,
    required this.session,
    required this.weekday,
  });

  final SubjectSchedule schedule;
  final SessionSchedule session;
  final int weekday;

  @override
  int compareTo(DaySessionItem other) {
    final byStart = session.timeIn.compareTo(other.session.timeIn);
    if (byStart != 0) return byStart;
    final byEnd = session.timeOut.compareTo(other.session.timeOut);
    if (byEnd != 0) return byEnd;
    final bySubject =
        schedule.subject.toLowerCase().compareTo(other.schedule.subject.toLowerCase());
    if (bySubject != 0) return bySubject;
    return session.type.index.compareTo(other.session.type.index);
  }
}

List<DaySessionItem> sessionsForWeekday(
  List<SubjectSchedule> schedules,
  int weekday,
) {
  final items = <DaySessionItem>[];
  for (final schedule in schedules) {
    for (final session in schedule.sessions.values) {
      if (session.days.contains(weekday)) {
        items.add(
          DaySessionItem(
            schedule: schedule,
            session: session,
            weekday: weekday,
          ),
        );
      }
    }
  }
  items.sort();
  return items;
}

class ScheduledAlarmPayload {
  const ScheduledAlarmPayload({
    required this.id,
    required this.scheduleId,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.title,
    required this.body,
    required this.sessionLabel,
  });

  final int id;
  final String scheduleId;

  /// ISO weekday: 1 = Monday .. 7 = Sunday (Sunday can occur via midnight wrap).
  final int weekday;
  final int hour;
  final int minute;
  final String title;
  final String body;
  final String sessionLabel;

  Map<String, Object> toMap() => <String, Object>{
        'id': id,
        'scheduleId': scheduleId,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'title': title,
        'body': body,
        'sessionLabel': sessionLabel,
      };
}

/// Computes the exact ISO weekday (1..7) and clock time after subtracting lead minutes.
({int weekday, int hour, int minute}) computeAlarmTrigger({
  required int weekday,
  required ScheduleTime timeIn,
  required int minutesBefore,
}) {
  const int minutesPerDay = 24 * 60;
  const int minutesPerWeek = 7 * minutesPerDay;
  final int classMinuteOfWeek = (weekday - 1) * minutesPerDay + timeIn.totalMinutes;
  final int triggerMinuteOfWeek = (classMinuteOfWeek - minutesBefore) % minutesPerWeek;
  final int triggerWeekday = (triggerMinuteOfWeek ~/ minutesPerDay) + 1;
  final int minuteOfDay = triggerMinuteOfWeek % minutesPerDay;
  return (
    weekday: triggerWeekday,
    hour: minuteOfDay ~/ 60,
    minute: minuteOfDay % 60,
  );
}

int stableAlarmId(String scheduleId, SessionType type, int weekday) {
  var hash = 0x811C9DC5;
  final key = '$scheduleId|${type.key}|$weekday';
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  // Keep positive 30-bit IDs above reserved test alarm ID range (0..999).
  return (hash & 0x3FFFFFFF) + 1000;
}

List<ScheduledAlarmPayload> buildAlarmPayloads(List<SubjectSchedule> schedules) {
  final payloads = <ScheduledAlarmPayload>[];
  final usedIds = <int>{};

  for (final schedule in schedules) {
    if (!schedule.reminderEnabled) continue;

    for (final session in schedule.sessions.values) {
      for (final day in session.days) {
        final trigger = computeAlarmTrigger(
          weekday: day,
          timeIn: session.timeIn,
          minutesBefore: schedule.reminderMinutesBefore,
        );
        var id = stableAlarmId(schedule.id, session.type, day);
        while (!usedIds.add(id)) {
          id++;
        }

        final timingPhrase = schedule.reminderMinutesBefore == 0
            ? 'starts now'
            : 'starts in ${schedule.reminderMinutesBefore} min (${session.timeIn.format12Hour()})';

        payloads.add(
          ScheduledAlarmPayload(
            id: id,
            scheduleId: schedule.id,
            weekday: trigger.weekday,
            hour: trigger.hour,
            minute: trigger.minute,
            title: '${schedule.subject} · Sec ${schedule.section}',
            body: '${session.type.label} $timingPhrase · ${session.formatTimeRange()}',
            sessionLabel: session.type.label,
          ),
        );
      }
    }
  }

  return payloads;
}
