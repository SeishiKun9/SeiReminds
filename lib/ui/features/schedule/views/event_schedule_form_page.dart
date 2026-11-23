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
  late ScheduleTime _timeIn;
  late ScheduleTime _timeOut;
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
    _timeIn = existing?.timeIn ?? _period.defaultTimeIn;
    _timeOut = existing?.timeOut ?? _period.defaultTimeOut;
    _reminderMinutesBefore = existing?.reminderMinutesBefore ?? 10;
    _reminderEnabled = existing?.reminderEnabled ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _selectPeriod(EventPeriod period) {
    setState(() {
      _period = period;
      _timeIn = period.defaultTimeIn;
      _timeOut = period.defaultTimeOut;
      _validationError = null;
    });
  }

  Future<void> _pickTime({required bool isTimeIn}) async {
    final current = isTimeIn ? _timeIn : _timeOut;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    setState(() {
      final updated = ScheduleTime(hour: picked.hour, minute: picked.minute);
      if (isTimeIn) {
        _timeIn = updated;
      } else {
        _timeOut = updated;
      }
      _validationError = null;
    });
  }

  List<DaySessionItem> _previewAffectedSessions() {
    if (_selectedDays.isEmpty || _timeOut.totalMinutes <= _timeIn.totalMinutes) {
      return const <DaySessionItem>[];
    }
    final affected = <DaySessionItem>[];
    final sortedDays = _selectedDays.toList()..sort();
    for (final day in sortedDays) {
      for (final item in sessionsForWeekday(widget.existingSchedules, day)) {
        if (timesOverlap(_timeIn, _timeOut, item.session.timeIn, item.session.timeOut)) {
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
      timeIn: _timeIn,
      timeOut: _timeOut,
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
      timeIn: _timeIn,
      timeOut: _timeOut,
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
              '3. Time Period & Range',
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
                  onSelected: (_) => _selectPeriod(period),
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
            Row(
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    key: const Key('event_time_in'),
                    onTap: () => _pickTime(isTimeIn: true),
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Time In',
                        suffixIcon: Icon(Icons.access_time, size: 20),
                      ),
                      child: Text(
                        _timeIn.format12Hour(),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    key: const Key('event_time_out'),
                    onTap: () => _pickTime(isTimeIn: false),
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Time Out',
                        suffixIcon: Icon(Icons.access_time, size: 20),
                      ),
                      child: Text(
                        _timeOut.format12Hour(),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_validationError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _validationError!,
                key: const Key('event_validation_error'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 18),
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
