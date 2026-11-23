const List<int> kSchoolWeekdays = <int>[1, 2, 3, 4, 5, 6];
const List<int> kEventWeekdays = <int>[1, 2, 3, 4, 5];
const List<int> kReminderLeadOptions = <int>[0, 5, 10, 15, 30];
const int kNoonMinutes = 12 * 60;
const int kEveningMinMinutes = 17 * 60;

final RegExp _singleLetterPattern = RegExp(r'^[A-Za-z]$');

class ScheduleProtectionException implements Exception {
  const ScheduleProtectionException(this.message);
  final String message;

  @override
  String toString() => 'ScheduleProtectionException: $message';
}

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

enum EventPeriod {
  morning('morning', 'Morning', 'Morning Time In & Time Out (ends by 12:00 PM)'),
  afternoon('afternoon', 'Afternoon', 'Afternoon Time In & Time Out (12:00 PM onward)'),
  wholeDay(
    'whole_day',
    'Whole Day',
    'Separate Morning & Afternoon Time In/Out (+ optional Evening Time In)',
  );

  const EventPeriod(this.key, this.label, this.hint);

  final String key;
  final String label;
  final String hint;

  bool get hasMorning => this == EventPeriod.morning || this == EventPeriod.wholeDay;

  bool get hasAfternoon =>
      this == EventPeriod.afternoon || this == EventPeriod.wholeDay;

  static const ScheduleTime defaultMorningIn = ScheduleTime(hour: 8, minute: 0);
  static const ScheduleTime defaultMorningOut = ScheduleTime(hour: 12, minute: 0);
  static const ScheduleTime defaultAfternoonIn = ScheduleTime(hour: 13, minute: 0);
  static const ScheduleTime defaultAfternoonOut = ScheduleTime(hour: 17, minute: 0);
  static const ScheduleTime defaultEveningIn = ScheduleTime(hour: 18, minute: 0);

  static EventPeriod fromKey(String key) {
    return switch (key) {
      'morning' => EventPeriod.morning,
      'afternoon' => EventPeriod.afternoon,
      'whole_day' || 'both' => EventPeriod.wholeDay,
      _ => throw FormatException('Unknown event period: $key'),
    };
  }
}

class ScheduleTime implements Comparable<ScheduleTime> {
  const ScheduleTime({required this.hour, required this.minute})
      : assert(hour >= 0 && hour <= 23),
        assert(minute >= 0 && minute <= 59);

  factory ScheduleTime.fromTotalMinutes(int totalMinutes) {
    if (totalMinutes < 0 || totalMinutes >= 24 * 60) {
      throw RangeError.range(totalMinutes, 0, 24 * 60 - 1, 'totalMinutes');
    }
    return ScheduleTime(
      hour: totalMinutes ~/ 60,
      minute: totalMinutes % 60,
    );
  }

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

bool timesOverlap(
  ScheduleTime startA,
  ScheduleTime endA,
  ScheduleTime startB,
  ScheduleTime endB,
) {
  return startA.totalMinutes < endB.totalMinutes &&
      startB.totalMinutes < endA.totalMinutes;
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

  String formatTimeRange() =>
      '${timeIn.format12Hour()} – ${timeOut.format12Hour()}';

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
        throw const FormatException(
          'Session map key does not match session type',
        );
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

class EventTimeSlot {
  const EventTimeSlot({
    required this.key,
    required this.label,
    required this.timeIn,
    this.timeOut,
  });

  final String key;
  final String label;
  final ScheduleTime timeIn;

  /// Null for optional Evening events (Time In only; active through end of day).
  final ScheduleTime? timeOut;

  bool overlapsSession(SessionSchedule session) {
    final end = timeOut;
    if (end != null) {
      return timesOverlap(timeIn, end, session.timeIn, session.timeOut);
    }
    // Evening Time In is open-ended from timeIn through 11:59 PM.
    return session.timeOut.totalMinutes > timeIn.totalMinutes;
  }

  String formatRange() {
    final end = timeOut;
    if (end == null) {
      return '$label In ${timeIn.format12Hour()}';
    }
    return '$label ${timeIn.format12Hour()} – ${end.format12Hour()}';
  }
}

class EventSchedule {
  EventSchedule({
    required this.id,
    required String title,
    required Iterable<int> days,
    required this.period,
    this.morningTimeIn,
    this.morningTimeOut,
    this.afternoonTimeIn,
    this.afternoonTimeOut,
    this.eveningTimeIn,
    this.reminderMinutesBefore = 10,
    this.reminderEnabled = true,
    DateTime? updatedAt,
  })  : title = title.trim(),
        days = List<int>.unmodifiable((days.toSet().toList()..sort())),
        updatedAt = (updatedAt ?? DateTime.now()).toUtc() {
    final error = validate();
    if (error != null) {
      throw FormatException(error);
    }
  }

  final String id;
  final String title;
  final List<int> days;
  final EventPeriod period;
  final ScheduleTime? morningTimeIn;
  final ScheduleTime? morningTimeOut;
  final ScheduleTime? afternoonTimeIn;
  final ScheduleTime? afternoonTimeOut;

  /// Optional evening Time In only (no Time Out).
  final ScheduleTime? eveningTimeIn;
  final int reminderMinutesBefore;
  final bool reminderEnabled;
  final DateTime updatedAt;

  static String? validateFields({
    required String title,
    required Iterable<int> days,
    required EventPeriod period,
    ScheduleTime? morningTimeIn,
    ScheduleTime? morningTimeOut,
    ScheduleTime? afternoonTimeIn,
    ScheduleTime? afternoonTimeOut,
    ScheduleTime? eveningTimeIn,
    int reminderMinutesBefore = 10,
  }) {
    if (title.trim().isEmpty) {
      return 'Enter an event title';
    }
    final dayList = days.toSet().toList();
    if (dayList.isEmpty) {
      return 'Pick at least one day (Monday–Friday)';
    }
    if (dayList.any((d) => d < DateTime.monday || d > DateTime.friday)) {
      return 'Event schedules must be Monday to Friday only';
    }
    if (reminderMinutesBefore < 0 || reminderMinutesBefore > 120) {
      return 'Reminder lead time must be 0–120 minutes';
    }

    if (period.hasMorning) {
      if (morningTimeIn == null || morningTimeOut == null) {
        return 'Set Morning Time In and Time Out';
      }
      if (morningTimeOut.totalMinutes <= morningTimeIn.totalMinutes) {
        return 'Morning Time Out must be after Morning Time In';
      }
      if (morningTimeIn.totalMinutes >= kNoonMinutes ||
          morningTimeOut.totalMinutes > kNoonMinutes) {
        return 'Morning event time must end by 12:00 PM';
      }
    } else if (morningTimeIn != null || morningTimeOut != null) {
      return 'Morning times only apply to Morning or Whole Day events';
    }

    if (period.hasAfternoon) {
      if (afternoonTimeIn == null || afternoonTimeOut == null) {
        return 'Set Afternoon Time In and Time Out';
      }
      if (afternoonTimeOut.totalMinutes <= afternoonTimeIn.totalMinutes) {
        return 'Afternoon Time Out must be after Afternoon Time In';
      }
      if (afternoonTimeIn.totalMinutes < kNoonMinutes) {
        return 'Afternoon event time must start at 12:00 PM or later';
      }
    } else if (afternoonTimeIn != null || afternoonTimeOut != null) {
      return 'Afternoon times only apply to Afternoon or Whole Day events';
    }

    if (eveningTimeIn != null) {
      if (eveningTimeIn.totalMinutes < kEveningMinMinutes) {
        return 'Evening Time In must be 5:00 PM or later';
      }
      if (afternoonTimeOut != null &&
          eveningTimeIn.totalMinutes < afternoonTimeOut.totalMinutes) {
        return 'Evening Time In cannot be before Afternoon Time Out';
      }
    }

    return null;
  }

  String? validate() => validateFields(
        title: title,
        days: days,
        period: period,
        morningTimeIn: morningTimeIn,
        morningTimeOut: morningTimeOut,
        afternoonTimeIn: afternoonTimeIn,
        afternoonTimeOut: afternoonTimeOut,
        eveningTimeIn: eveningTimeIn,
        reminderMinutesBefore: reminderMinutesBefore,
      );

  List<EventTimeSlot> get timeSlots => <EventTimeSlot>[
        if (morningTimeIn != null && morningTimeOut != null)
          EventTimeSlot(
            key: 'morning',
            label: 'Morning',
            timeIn: morningTimeIn!,
            timeOut: morningTimeOut,
          ),
        if (afternoonTimeIn != null && afternoonTimeOut != null)
          EventTimeSlot(
            key: 'afternoon',
            label: 'Afternoon',
            timeIn: afternoonTimeIn!,
            timeOut: afternoonTimeOut,
          ),
        if (eveningTimeIn != null)
          EventTimeSlot(
            key: 'evening',
            label: 'Evening',
            timeIn: eveningTimeIn!,
          ),
      ];

  ScheduleTime get firstStartTime => timeSlots.first.timeIn;

  bool overlapsSession(SessionSchedule session) {
    return timeSlots.any((slot) => slot.overlapsSession(session));
  }

  String formatTimeSummary() =>
      timeSlots.map((slot) => slot.formatRange()).join(' · ');

  String formatDaysSummary() => days.map(weekdayShortLabel).join(', ');

  EventSchedule copyWith({
    String? id,
    String? title,
    Iterable<int>? days,
    EventPeriod? period,
    ScheduleTime? morningTimeIn,
    ScheduleTime? morningTimeOut,
    ScheduleTime? afternoonTimeIn,
    ScheduleTime? afternoonTimeOut,
    ScheduleTime? eveningTimeIn,
    bool clearEvening = false,
    int? reminderMinutesBefore,
    bool? reminderEnabled,
    DateTime? updatedAt,
  }) {
    final nextPeriod = period ?? this.period;
    return EventSchedule(
      id: id ?? this.id,
      title: title ?? this.title,
      days: days ?? this.days,
      period: nextPeriod,
      morningTimeIn:
          nextPeriod.hasMorning ? (morningTimeIn ?? this.morningTimeIn) : null,
      morningTimeOut:
          nextPeriod.hasMorning ? (morningTimeOut ?? this.morningTimeOut) : null,
      afternoonTimeIn: nextPeriod.hasAfternoon
          ? (afternoonTimeIn ?? this.afternoonTimeIn)
          : null,
      afternoonTimeOut: nextPeriod.hasAfternoon
          ? (afternoonTimeOut ?? this.afternoonTimeOut)
          : null,
      eveningTimeIn: clearEvening ? null : (eveningTimeIn ?? this.eveningTimeIn),
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'days': days,
        'period': period.key,
        'morningTimeIn': morningTimeIn?.toJson(),
        'morningTimeOut': morningTimeOut?.toJson(),
        'afternoonTimeIn': afternoonTimeIn?.toJson(),
        'afternoonTimeOut': afternoonTimeOut?.toJson(),
        'eveningTimeIn': eveningTimeIn?.toJson(),
        'reminderMinutesBefore': reminderMinutesBefore,
        'reminderEnabled': reminderEnabled,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.details,
    required this.isArchived,
    required this.createdAt,
    this.snapshotJson,
  });

  final int id;
  final String action;
  final String entityType;
  final String entityId;
  final String title;
  final String details;
  final String? snapshotJson;
  final bool isArchived;
  final DateTime createdAt;
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

  String get shortSummary =>
      '${schedule.subject} (Sec ${schedule.section} · ${session.type.shortLabel})';

  @override
  int compareTo(DaySessionItem other) {
    final byStart = session.timeIn.compareTo(other.session.timeIn);
    if (byStart != 0) return byStart;
    final byEnd = session.timeOut.compareTo(other.session.timeOut);
    if (byEnd != 0) return byEnd;
    final bySubject = schedule.subject
        .toLowerCase()
        .compareTo(other.schedule.subject.toLowerCase());
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

List<EventSchedule> eventsForWeekday(
  List<EventSchedule> events,
  int weekday,
) {
  final items = events.where((e) => e.days.contains(weekday)).toList()
    ..sort((a, b) {
      final byStart = a.firstStartTime.compareTo(b.firstStartTime);
      if (byStart != 0) return byStart;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  return items;
}

List<EventSchedule> conflictingEventsForSession(
  List<EventSchedule> events,
  int weekday,
  SessionSchedule session,
) {
  return eventsForWeekday(events, weekday)
      .where((event) => event.overlapsSession(session))
      .toList();
}

List<DaySessionItem> affectedSessionsForEventOnDay(
  EventSchedule event,
  List<SubjectSchedule> schedules,
  int weekday,
) {
  if (!event.days.contains(weekday)) return const <DaySessionItem>[];
  return sessionsForWeekday(schedules, weekday)
      .where((item) => event.overlapsSession(item.session))
      .toList();
}

List<DaySessionItem> affectedSessionsForEvent(
  EventSchedule event,
  List<SubjectSchedule> schedules,
) {
  final affected = <DaySessionItem>[];
  for (final day in event.days) {
    affected.addAll(affectedSessionsForEventOnDay(event, schedules, day));
  }
  return affected;
}

String buildCancellationAnnouncement(
  EventSchedule event,
  List<DaySessionItem> affectedSessions,
) {
  if (affectedSessions.isEmpty) {
    return '${event.title} (${event.period.label}: ${event.formatTimeSummary()}) has no overlapping classes.';
  }
  final names = affectedSessions.map((item) => item.shortSummary).join(', ');
  return 'Classes canceled due to ${event.title}: $names.';
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
  final int classMinuteOfWeek =
      (weekday - 1) * minutesPerDay + timeIn.totalMinutes;
  final int triggerMinuteOfWeek =
      (classMinuteOfWeek - minutesBefore) % minutesPerWeek;
  final int triggerWeekday = (triggerMinuteOfWeek ~/ minutesPerDay) + 1;
  final int minuteOfDay = triggerMinuteOfWeek % minutesPerDay;
  return (
    weekday: triggerWeekday,
    hour: minuteOfDay ~/ 60,
    minute: minuteOfDay % 60,
  );
}

int _fnv1aAlarmId(String key) {
  var hash = 0x811C9DC5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  // Keep positive 30-bit IDs above reserved test alarm ID range (0..999).
  return (hash & 0x3FFFFFFF) + 1000;
}

int stableAlarmId(String scheduleId, SessionType type, int weekday) {
  return _fnv1aAlarmId('$scheduleId|${type.key}|$weekday');
}

int stableEventAlarmId(String eventId, int weekday, String slotKey) {
  return _fnv1aAlarmId('event|$eventId|$weekday|$slotKey');
}

List<ScheduledAlarmPayload> buildAlarmPayloads(
  List<SubjectSchedule> schedules, {
  List<EventSchedule> events = const <EventSchedule>[],
}) {
  final payloads = <ScheduledAlarmPayload>[];
  final usedIds = <int>{};

  for (final schedule in schedules) {
    if (!schedule.reminderEnabled) continue;

    for (final session in schedule.sessions.values) {
      for (final day in session.days) {
        // Suppress class alarm on days/times canceled by a school event.
        if (conflictingEventsForSession(events, day, session).isNotEmpty) {
          continue;
        }

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
            body:
                '${session.type.label} $timingPhrase · ${session.formatTimeRange()}',
            sessionLabel: session.type.label,
          ),
        );
      }
    }
  }

  for (final event in events) {
    if (!event.reminderEnabled) continue;

    for (final day in event.days) {
      final daySessions = sessionsForWeekday(schedules, day);
      for (final slot in event.timeSlots) {
        final trigger = computeAlarmTrigger(
          weekday: day,
          timeIn: slot.timeIn,
          minutesBefore: event.reminderMinutesBefore,
        );
        var id = stableEventAlarmId(event.id, day, slot.key);
        while (!usedIds.add(id)) {
          id++;
        }

        final affected = daySessions
            .where((item) => slot.overlapsSession(item.session))
            .toList();
        final title = affected.isNotEmpty
            ? 'Classes Canceled · ${event.title} (${slot.label})'
            : 'Event · ${event.title} (${slot.label})';
        final body = affected.isNotEmpty
            ? 'Classes canceled due to ${event.title}: ${affected.map((s) => s.shortSummary).join(', ')} (${slot.formatRange()})'
            : '${event.period.label} event (${slot.formatRange()})';

        payloads.add(
          ScheduledAlarmPayload(
            id: id,
            scheduleId: event.id,
            weekday: trigger.weekday,
            hour: trigger.hour,
            minute: trigger.minute,
            title: title,
            body: body,
            sessionLabel: 'Event',
          ),
        );
      }
    }
  }

  return payloads;
}

/// Finds the current or next non-canceled class session for today (Mon–Sat).
({DaySessionItem item, bool isInProgress, int minutesUntilStart})?
findNextUpcomingSession(
  List<SubjectSchedule> schedules,
  List<EventSchedule> events, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  if (current.weekday < DateTime.monday ||
      current.weekday > DateTime.saturday) {
    return null;
  }

  final nowMinutes = current.hour * 60 + current.minute;
  for (final item in sessionsForWeekday(schedules, current.weekday)) {
    if (conflictingEventsForSession(events, current.weekday, item.session)
        .isNotEmpty) {
      continue;
    }
    if (item.session.timeOut.totalMinutes > nowMinutes) {
      final isInProgress = item.session.timeIn.totalMinutes <= nowMinutes;
      final minutesUntilStart =
          isInProgress ? 0 : item.session.timeIn.totalMinutes - nowMinutes;
      return (
        item: item,
        isInProgress: isInProgress,
        minutesUntilStart: minutesUntilStart,
      );
    }
  }
  return null;
}
