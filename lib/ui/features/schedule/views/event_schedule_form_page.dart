import 'package:flutter/material.dart';

import '../../../../domain/models/schedule_models.dart';

class EventScheduleFormPage extends StatefulWidget {
  const EventScheduleFormPage({
    super.key,
    required this.initialWeekday,
    required this.existingSchedules,
    this.existingEvent,
  });

  final int initialWeekday;
  final List<SubjectSchedule> existingSchedules;
  final EventSchedule? existingEvent;

  @override
  State<EventScheduleFormPage> createState() => _EventScheduleFormPageState();
}

class _EventScheduleFormPageState extends State<EventScheduleFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late Set<int> _selectedDays;
  late EventPeriod _period;
  late ScheduleTime _morningTimeIn;
  late ScheduleTime _morningTimeOut;
  late ScheduleTime _afternoonTimeIn;
  late ScheduleTime _afternoonTimeOut;
  late bool _hasEvening;
  late ScheduleTime _eveningTimeIn;
  late int _reminderMinutesBefore;
  late bool _reminderEnabled;
  String? _validationError;

  bool get _isEditing => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    _titleController = TextEditingController(text: existing?.title ?? '');
    final defaultDay = widget.initialWeekday >= DateTime.monday &&
            widget.initialWeekday <= DateTime.friday
        ? widget.initialWeekday
        : DateTime.monday;
    _selectedDays = existing?.days.toSet() ?? <int>{defaultDay};
    _period = existing?.period ?? EventPeriod.morning;
    _morningTimeIn = existing?.morningTimeIn ?? EventPeriod.defaultMorningIn;
    _morningTimeOut = existing?.morningTimeOut ?? EventPeriod.defaultMorningOut;
    _afternoonTimeIn =
        existing?.afternoonTimeIn ?? EventPeriod.defaultAfternoonIn;
    _afternoonTimeOut =
        existing?.afternoonTimeOut ?? EventPeriod.defaultAfternoonOut;
    _hasEvening = existing?.eveningTimeIn != null;
    _eveningTimeIn = existing?.eveningTimeIn ?? EventPeriod.defaultEveningIn;
    _reminderMinutesBefore = existing?.reminderMinutesBefore ?? 10;
    _reminderEnabled = existing?.reminderEnabled ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  ScheduleTime? get _activeMorningIn =>
      _period.hasMorning ? _morningTimeIn : null;
  ScheduleTime? get _activeMorningOut =>
      _period.hasMorning ? _morningTimeOut : null;
  ScheduleTime? get _activeAfternoonIn =>
      _period.hasAfternoon ? _afternoonTimeIn : null;
  ScheduleTime? get _activeAfternoonOut =>
      _period.hasAfternoon ? _afternoonTimeOut : null;
  ScheduleTime? get _activeEveningIn => _hasEvening ? _eveningTimeIn : null;

  Future<void> _pickTime({
    required ScheduleTime initial,
    required ValueChanged<ScheduleTime> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (picked == null) return;
    setState(() {
      onPicked(ScheduleTime(hour: picked.hour, minute: picked.minute));
      _validationError = null;
    });
  }

  List<DaySessionItem> _previewAffectedSessions() {
    if (_selectedDays.isEmpty) return const <DaySessionItem>[];
    final slots = <EventTimeSlot>[
      if (_period.hasMorning &&
          _morningTimeOut.totalMinutes > _morningTimeIn.totalMinutes)
        EventTimeSlot(
          key: 'morning',
          label: 'Morning',
          timeIn: _morningTimeIn,
          timeOut: _morningTimeOut,
        ),
      if (_period.hasAfternoon &&
          _afternoonTimeOut.totalMinutes > _afternoonTimeIn.totalMinutes)
        EventTimeSlot(
          key: 'afternoon',
          label: 'Afternoon',
          timeIn: _afternoonTimeIn,
          timeOut: _afternoonTimeOut,
        ),
      if (_hasEvening)
        EventTimeSlot(
          key: 'evening',
          label: 'Evening',
          timeIn: _eveningTimeIn,
        ),
    ];
    if (slots.isEmpty) return const <DaySessionItem>[];

    final affected = <DaySessionItem>[];
    final sortedDays = _selectedDays.toList()..sort();
    for (final day in sortedDays) {
      for (final item in sessionsForWeekday(widget.existingSchedules, day)) {
        if (slots.any((slot) => slot.overlapsSession(item.session))) {
          affected.add(item);
        }
      }
    }
    return affected;
  }

  void _save() {
    final formValid = _formKey.currentState?.validate() ?? false;
    final fieldError = EventSchedule.validateFields(
      title: _titleController.text,
      days: _selectedDays,
      period: _period,
      morningTimeIn: _activeMorningIn,
      morningTimeOut: _activeMorningOut,
      afternoonTimeIn: _activeAfternoonIn,
      afternoonTimeOut: _activeAfternoonOut,
      eveningTimeIn: _activeEveningIn,
      reminderMinutesBefore: _reminderMinutesBefore,
    );

    setState(() {
      _validationError = fieldError;
    });

    if (!formValid || fieldError != null) return;

    final event = EventSchedule(
      id: widget.existingEvent?.id ??
          'evt_${DateTime.now().microsecondsSinceEpoch}',
      title: _titleController.text.trim(),
      days: _selectedDays,
      period: _period,
      morningTimeIn: _activeMorningIn,
      morningTimeOut: _activeMorningOut,
      afternoonTimeIn: _activeAfternoonIn,
      afternoonTimeOut: _activeAfternoonOut,
      eveningTimeIn: _activeEveningIn,
      reminderMinutesBefore: _reminderMinutesBefore,
      reminderEnabled: _reminderEnabled,
    );

    Navigator.of(context).pop(event);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final affected = _previewAffectedSessions();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Event Schedule' : 'Add Event Schedule'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: <Widget>[
            Text(
              '1. Event Details',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('event_title_field'),
              controller: _titleController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Event Title',
                hintText: 'e.g., Foundation Day, Intramurals, Faculty Meeting',
                prefixIcon: Icon(Icons.campaign_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter an event title';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text(
              '2. Event Days (Monday – Friday)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Events run Monday to Friday and announce class cancellations whenever they overlap a subject.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: kEventWeekdays.map((day) {
                final selected = _selectedDays.contains(day);
                return FilterChip(
                  key: Key('event_day_$day'),
                  label: Text(weekdayShortLabel(day)),
                  selected: selected,
                  onSelected: (isSelected) {
                    setState(() {
                      if (isSelected) {
                        _selectedDays.add(day);
                      } else {
                        _selectedDays.remove(day);
                      }
                      _validationError = null;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              '3. Schedule Coverage & Times',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: EventPeriod.values.map((period) {
                return ChoiceChip(
                  key: Key('event_period_${period.key}'),
                  label: Text(period.label),
                  selected: _period == period,
                  onSelected: (_) {
                    setState(() {
                      _period = period;
                      _validationError = null;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              _period.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_period.hasMorning)
              _EventRangeCard(
                icon: Icons.wb_sunny_outlined,
                title: 'Morning',
                subtitle: 'Ends by 12:00 PM',
                timeInKey: const Key('event_morning_in'),
                timeOutKey: const Key('event_morning_out'),
                timeIn: _morningTimeIn,
                timeOut: _morningTimeOut,
                onPickTimeIn: () => _pickTime(
                  initial: _morningTimeIn,
                  onPicked: (t) => _morningTimeIn = t,
                ),
                onPickTimeOut: () => _pickTime(
                  initial: _morningTimeOut,
                  onPicked: (t) => _morningTimeOut = t,
                ),
              ),
            if (_period.hasAfternoon)
              _EventRangeCard(
                icon: Icons.wb_twilight_outlined,
                title: 'Afternoon',
                subtitle: 'Starts 12:00 PM or later',
                timeInKey: const Key('event_afternoon_in'),
                timeOutKey: const Key('event_afternoon_out'),
                timeIn: _afternoonTimeIn,
                timeOut: _afternoonTimeOut,
                onPickTimeIn: () => _pickTime(
                  initial: _afternoonTimeIn,
                  onPicked: (t) => _afternoonTimeIn = t,
                ),
                onPickTimeOut: () => _pickTime(
                  initial: _afternoonTimeOut,
                  onPicked: (t) => _afternoonTimeOut = t,
                ),
              ),
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    key: const Key('event_evening_toggle'),
                    secondary: const Icon(Icons.nights_stay_outlined),
                    title: const Text(
                      'Evening (Optional)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _hasEvening
                          ? 'Time In ${_eveningTimeIn.format12Hour()} (no Time Out)'
                          : 'Off — enable for evening Time In only (5:00 PM+)',
                    ),
                    value: _hasEvening,
                    onChanged: (value) {
                      setState(() {
                        _hasEvening = value;
                        _validationError = null;
                      });
                    },
                  ),
                  if (_hasEvening)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: _TimeSlotButton(
                        key: const Key('event_evening_in'),
                        label: 'Evening Time In (Optional · No Time Out)',
                        timeText: _eveningTimeIn.format12Hour(),
                        onTap: () => _pickTime(
                          initial: _eveningTimeIn,
                          onPicked: (t) => _eveningTimeIn = t,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_validationError != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _validationError!,
                key: const Key('event_validation_error'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Card(
              color: affected.isNotEmpty
                  ? theme.colorScheme.errorContainer.withValues(alpha: 0.7)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          affected.isNotEmpty
                              ? Icons.event_busy
                              : Icons.event_available,
                          color: affected.isNotEmpty
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            affected.isNotEmpty
                                ? 'Will announce classes canceled (${affected.length} hit)'
                                : 'No overlapping subjects during this time',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: affected.isNotEmpty
                                  ? theme.colorScheme.onErrorContainer
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (affected.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      ...affected.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${weekdayShortLabel(item.weekday)}: ${item.shortSummary} (${item.session.formatTimeRange()})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '4. Cancellation Announcement Alarm',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Announce via loud silent-bypass alarm'),
                      value: _reminderEnabled,
                      onChanged: (value) {
                        setState(() => _reminderEnabled = value);
                      },
                    ),
                    if (_reminderEnabled)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: kReminderLeadOptions.map((minutes) {
                          return ChoiceChip(
                            label: Text(formatReminderLead(minutes)),
                            selected: _reminderMinutesBefore == minutes,
                            onSelected: (_) {
                              setState(() => _reminderMinutesBefore = minutes);
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const Key('save_event_button'),
            onPressed: _save,
            icon: const Icon(Icons.campaign),
            label: Text(_isEditing ? 'Update Event' : 'Save Event'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ),
      ),
    );
  }
}

class _EventRangeCard extends StatelessWidget {
  const _EventRangeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.timeInKey,
    required this.timeOutKey,
    required this.timeIn,
    required this.timeOut,
    required this.onPickTimeIn,
    required this.onPickTimeOut,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Key timeInKey;
  final Key timeOutKey;
  final ScheduleTime timeIn;
  final ScheduleTime timeOut;
  final VoidCallback onPickTimeIn;
  final VoidCallback onPickTimeOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _TimeSlotButton(
                    key: timeInKey,
                    label: '$title Time In',
                    timeText: timeIn.format12Hour(),
                    onTap: onPickTimeIn,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeSlotButton(
                    key: timeOutKey,
                    label: '$title Time Out',
                    timeText: timeOut.format12Hour(),
                    onTap: onPickTimeOut,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSlotButton extends StatelessWidget {
  const _TimeSlotButton({
    super.key,
    required this.label,
    required this.timeText,
    required this.onTap,
  });

  final String label;
  final String timeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.access_time, size: 20),
        ),
        child: Text(
          timeText,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
