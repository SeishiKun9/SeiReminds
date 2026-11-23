import 'package:flutter/material.dart';

import '../../../../domain/models/schedule_models.dart';
import '../../../core/app_theme.dart';

class _SessionDraft {
  _SessionDraft({
    required this.enabled,
    required this.days,
    required this.timeIn,
    required this.timeOut,
  });

  bool enabled;
  Set<int> days;
  ScheduleTime timeIn;
  ScheduleTime timeOut;
}

class SubjectScheduleFormPage extends StatefulWidget {
  const SubjectScheduleFormPage({
    super.key,
    required this.initialWeekday,
    this.existingSchedule,
    this.knownSubjects = const <String>[],
  });

  final int initialWeekday;
  final SubjectSchedule? existingSchedule;
  final List<String> knownSubjects;

  @override
  State<SubjectScheduleFormPage> createState() =>
      _SubjectScheduleFormPageState();
}

class _SubjectScheduleFormPageState extends State<SubjectScheduleFormPage> {
  static final List<String> _alphabet = List<String>.generate(
    26,
    (index) => String.fromCharCode(65 + index),
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _subjectController;
  late final TextEditingController _sectionController;

  late final Map<SessionType, _SessionDraft> _drafts;
  late int _reminderMinutesBefore;
  late bool _reminderEnabled;
  bool _showAlphabetGrid = false;
  String? _sessionsError;

  bool get _isEditing => widget.existingSchedule != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSchedule;
    _subjectController = TextEditingController(text: existing?.subject ?? '');
    _sectionController = TextEditingController(text: existing?.section ?? '');
    _reminderMinutesBefore = existing?.reminderMinutesBefore ?? 10;
    _reminderEnabled = existing?.reminderEnabled ?? true;

    _drafts = <SessionType, _SessionDraft>{
      SessionType.onlineTime: _initialDraft(
        existing?.sessions[SessionType.onlineTime],
        defaultStart: const ScheduleTime(hour: 8, minute: 0),
        defaultEnd: const ScheduleTime(hour: 9, minute: 30),
        defaultEnabled: existing == null,
      ),
      SessionType.lecture: _initialDraft(
        existing?.sessions[SessionType.lecture],
        defaultStart: const ScheduleTime(hour: 10, minute: 0),
        defaultEnd: const ScheduleTime(hour: 11, minute: 30),
        defaultEnabled: false,
      ),
      SessionType.laboratory: _initialDraft(
        existing?.sessions[SessionType.laboratory],
        defaultStart: const ScheduleTime(hour: 13, minute: 0),
        defaultEnd: const ScheduleTime(hour: 15, minute: 0),
        defaultEnabled: false,
      ),
    };
  }

  _SessionDraft _initialDraft(
    SessionSchedule? existing, {
    required ScheduleTime defaultStart,
    required ScheduleTime defaultEnd,
    required bool defaultEnabled,
  }) {
    if (existing != null) {
      return _SessionDraft(
        enabled: true,
        days: existing.days.toSet(),
        timeIn: existing.timeIn,
        timeOut: existing.timeOut,
      );
    }
    return _SessionDraft(
      enabled: defaultEnabled,
      days: <int>{widget.initialWeekday},
      timeIn: defaultStart,
      timeOut: defaultEnd,
    );
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({
    required SessionType type,
    required bool isTimeIn,
  }) async {
    final draft = _drafts[type]!;
    final current = isTimeIn ? draft.timeIn : draft.timeOut;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;

    setState(() {
      final updated = ScheduleTime(hour: picked.hour, minute: picked.minute);
      if (isTimeIn) {
        draft.timeIn = updated;
        // Keep Time Out ahead of Time In by default when user adjusts Time In.
        if (draft.timeOut.totalMinutes <= updated.totalMinutes) {
          final nextEndMinutes = (updated.totalMinutes + 90).clamp(0, 23 * 60 + 59);
          draft.timeOut = ScheduleTime(
            hour: nextEndMinutes ~/ 60,
            minute: nextEndMinutes % 60,
          );
        }
      } else {
        draft.timeOut = updated;
      }
      _sessionsError = null;
    });
  }

  void _save() {
    final formValid = _formKey.currentState?.validate() ?? false;

    final builtSessions = <SessionType, SessionSchedule>{};
    String? sessionValidationError;

    for (final type in SessionType.values) {
      final draft = _drafts[type]!;
      if (!draft.enabled) continue;
      final session = SessionSchedule(
        type: type,
        days: draft.days,
        timeIn: draft.timeIn,
        timeOut: draft.timeOut,
      );
      final error = session.validate();
      if (error != null) {
        sessionValidationError ??= error;
      } else {
        builtSessions[type] = session;
      }
    }

    if (sessionValidationError == null && builtSessions.isEmpty) {
      sessionValidationError =
          'Select at least one: Online Time, Lecture, or Laboratory.';
    }

    setState(() {
      _sessionsError = sessionValidationError;
    });

    if (!formValid || sessionValidationError != null) {
      return;
    }

    final schedule = SubjectSchedule(
      id: widget.existingSchedule?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      subject: _subjectController.text.trim(),
      section: normalizeSectionLetter(_sectionController.text),
      sessions: builtSessions,
      reminderMinutesBefore: _reminderMinutesBefore,
      reminderEnabled: _reminderEnabled,
    );

    Navigator.of(context).pop(schedule);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubject = _subjectController.text.trim().isNotEmpty;
    final currentSectionUpper = _sectionController.text.trim().toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Class Schedule' : 'Add Class Schedule'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: <Widget>[
            _SectionHeader(
              step: '1',
              title: 'Subject',
              subtitle: 'Choose an existing subject or type a new one.',
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('subject_field'),
              controller: _subjectController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Subject Name',
                hintText: 'e.g., Data Structures, Calculus 1',
                prefixIcon: Icon(Icons.book_outlined),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter or choose a subject';
                }
                return null;
              },
            ),
            if (widget.knownSubjects.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: widget.knownSubjects.map((name) {
                  return ActionChip(
                    label: Text(name),
                    onPressed: () {
                      setState(() {
                        _subjectController.text = name;
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 20),
            _SectionHeader(
              step: '2',
              title: 'Section (A–Z)',
              subtitle: hasSubject
                  ? 'Type 1 letter (A–Z) or tap Pick A–Z for ${_subjectController.text.trim()}.'
                  : 'Once you enter a subject, pick or type a single section letter (A–Z).',
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: const Key('section_field'),
                    controller: _sectionController,
                    textCapitalization: TextCapitalization.characters,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      labelText: 'Section Letter (A–Z)',
                      hintText: 'Type A–Z (1 letter)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: validateSectionLetter,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.tonalIcon(
                    key: const Key('toggle_az_picker'),
                    onPressed: () {
                      setState(() => _showAlphabetGrid = !_showAlphabetGrid);
                    },
                    icon: Icon(
                      _showAlphabetGrid ? Icons.expand_less : Icons.grid_view,
                    ),
                    label: const Text('A–Z'),
                  ),
                ),
              ],
            ),
            if (_showAlphabetGrid || (hasSubject && currentSectionUpper.isEmpty)) ...<Widget>[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _alphabet.map((letter) {
                      final selected = currentSectionUpper == letter;
                      return ChoiceChip(
                        key: Key('section_chip_$letter'),
                        label: Text(letter),
                        selected: selected,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() {
                            _sectionController.text = letter;
                            _showAlphabetGrid = false;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            const _SectionHeader(
              step: '3',
              title: 'Class Sessions (Mon–Sat)',
              subtitle:
                  'Select Online Time, Lecture, and/or Laboratory — you can enable all three with their own days, Time In, and Time Out.',
            ),
            if (_sessionsError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _sessionsError!,
                key: const Key('sessions_error_text'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            ...SessionType.values.map((type) {
              return _buildSessionCard(context, type);
            }),
            const SizedBox(height: 16),
            const _SectionHeader(
              step: '4',
              title: 'Loud Silent-Bypass Alarm',
              subtitle:
                  'Rings on Alarm volume & vibrates hard even when phone is silent or app is closed.',
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
                      title: const Text('Enable alarm reminder'),
                      value: _reminderEnabled,
                      onChanged: (value) {
                        setState(() => _reminderEnabled = value);
                      },
                    ),
                    if (_reminderEnabled) ...<Widget>[
                      Text(
                        'Remind me:',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
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
            key: const Key('save_schedule_button'),
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(_isEditing ? 'Update Schedule' : 'Save Schedule'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context, SessionType type) {
    final theme = Theme.of(context);
    final draft = _drafts[type]!;
    final accent = AppTheme.sessionColor(type, theme.brightness);
    final timeInvalid =
        draft.enabled && draft.timeOut.totalMinutes <= draft.timeIn.totalMinutes;
    final daysEmpty = draft.enabled && draft.days.isEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: draft.enabled ? accent : theme.colorScheme.outlineVariant,
          width: draft.enabled ? 1.6 : 1,
        ),
      ),
      child: Column(
        children: <Widget>[
          SwitchListTile(
            key: Key('session_toggle_${type.key}'),
            secondary: CircleAvatar(
              backgroundColor: accent.withValues(alpha: 0.14),
              foregroundColor: accent,
              child: Icon(AppTheme.sessionIcon(type)),
            ),
            title: Text(
              type.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              draft.enabled
                  ? '${draft.timeIn.format12Hour()} – ${draft.timeOut.format12Hour()}'
                  : 'Off — toggle to set days, Time In & Time Out',
            ),
            value: draft.enabled,
            onChanged: (value) {
              setState(() {
                draft.enabled = value;
                if (value && draft.days.isEmpty) {
                  draft.days.add(widget.initialWeekday);
                }
                _sessionsError = null;
              });
            },
          ),
          if (draft.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Divider(height: 12),
                  Text(
                    'Days (Monday – Saturday)',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: kSchoolWeekdays.map((day) {
                      final selected = draft.days.contains(day);
                      return FilterChip(
                        key: Key('day_${type.key}_$day'),
                        label: Text(weekdayShortLabel(day)),
                        selected: selected,
                        onSelected: (isSelected) {
                          setState(() {
                            if (isSelected) {
                              draft.days.add(day);
                            } else {
                              draft.days.remove(day);
                            }
                            _sessionsError = null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  if (daysEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Select at least one day (Mon–Sat).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _TimePickerField(
                          key: Key('time_in_${type.key}'),
                          label: 'Time In',
                          timeText: draft.timeIn.format12Hour(),
                          onTap: () => _pickTime(type: type, isTimeIn: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimePickerField(
                          key: Key('time_out_${type.key}'),
                          label: 'Time Out',
                          timeText: draft.timeOut.format12Hour(),
                          isError: timeInvalid,
                          onTap: () => _pickTime(type: type, isTimeIn: false),
                        ),
                      ),
                    ],
                  ),
                  if (timeInvalid) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Time Out must be after Time In.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final String step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 13,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(
            step,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimePickerField extends StatelessWidget {
  const _TimePickerField({
    super.key,
    required this.label,
    required this.timeText,
    required this.onTap,
    this.isError = false,
  });

  final String label;
  final String timeText;
  final VoidCallback onTap;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        isError ? theme.colorScheme.error : theme.colorScheme.outline;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.access_time, size: 20),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
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
