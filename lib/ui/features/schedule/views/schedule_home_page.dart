import 'package:flutter/material.dart';

import '../../../../domain/models/schedule_models.dart';
import '../../../core/app_routes.dart';
import '../../../core/app_theme.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../canvas/view_models/canvas_settings_view_model.dart';
import '../view_models/schedule_view_model.dart';
import 'alarm_setup_sheet.dart';
import 'event_schedule_form_page.dart';
import 'subject_schedule_form_page.dart';

class ScheduleHomePage extends StatefulWidget {
  const ScheduleHomePage({
    super.key,
    required this.viewModel,
    this.canvasViewModel,
    this.authViewModel,
  });

  final ScheduleViewModel viewModel;
  final CanvasSettingsViewModel? canvasViewModel;
  final AuthViewModel? authViewModel;

  @override
  State<ScheduleHomePage> createState() => _ScheduleHomePageState();
}

class _ScheduleHomePageState extends State<ScheduleHomePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.viewModel.hasInitialized) {
      Future.microtask(widget.viewModel.initialize);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.viewModel.checkDailyRolloverCleanup();
    }
  }

  Future<void> _openClassForm({SubjectSchedule? existing}) async {
    final result = await Navigator.of(context).push<SubjectSchedule>(
      MaterialPageRoute<SubjectSchedule>(
        builder: (_) => SubjectScheduleFormPage(
          initialWeekday: widget.viewModel.selectedWeekday,
          existingSchedule: existing,
          knownSubjects: widget.viewModel.knownSubjects,
        ),
      ),
    );

    if (result == null) return;
    final saved = await widget.viewModel.saveSchedule(result);
    if (!mounted || !saved) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.subject} (Sec ${result.section}) saved in SQLite.',
        ),
      ),
    );
  }

  Future<void> _openEventForm({EventSchedule? existing}) async {
    final result = await Navigator.of(context).push<EventSchedule>(
      MaterialPageRoute<EventSchedule>(
        builder: (_) => EventScheduleFormPage(
          initialWeekday: widget.viewModel.selectedWeekday,
          existingSchedules: widget.viewModel.schedules,
          existingEvent: existing,
        ),
      ),
    );

    if (result == null) return;
    final affected = await widget.viewModel.saveEvent(result);
    if (!mounted || affected == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(buildCancellationAnnouncement(result, affected))),
    );
  }

  Future<void> _confirmDeleteSchedule(SubjectSchedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from schedule?'),
        content: Text(
          'Remove ${schedule.subject} (Sec ${schedule.section}) from your timetable and cancel its weekly reminders?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.viewModel.deleteScheduleFromScheduleScreen(schedule.id);
    }
  }

  Future<void> _confirmDeleteEvent(EventSchedule event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event schedule?'),
        content: Text(
          'Remove "${event.title}"? Overlapping classes will resume normal alarms.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.viewModel.deleteEvent(event.id);
    }
  }

  void _openAlarmSetup() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AlarmSetupSheet(viewModel: widget.viewModel),
    );
  }

  void _openSubjectDetails(SubjectSchedule schedule, int weekday) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _SubjectDetailSheet(
        schedule: schedule,
        weekday: weekday,
        conflictingEventsForSession: (session) =>
            widget.viewModel.conflictingEventsForSessionOnDay(weekday, session),
        onEdit: () {
          Navigator.of(sheetContext).pop();
          _openClassForm(existing: schedule);
        },
        onToggleReminder: () {
          Navigator.of(sheetContext).pop();
          widget.viewModel.toggleReminder(schedule.id, !schedule.reminderEnabled);
        },
        onDelete: () {
          Navigator.of(sheetContext).pop();
          _confirmDeleteSchedule(schedule);
        },
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).pushNamed(AppRoutes.settings);
  }

  void _openCanvasHub() {
    Navigator.of(context).pushNamed(AppRoutes.canvasHub);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listenables = <Listenable>[
      widget.viewModel,
      if (widget.canvasViewModel != null) widget.canvasViewModel!,
      if (widget.authViewModel != null) widget.authViewModel!,
    ];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final vm = widget.viewModel;
        final dayEvents = vm.selectedDayEvents;
        final daySubjects = vm.selectedDaySubjects;
        final nextUp = vm.nextUpcomingSession;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'SeiReminds',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const Key('official_version_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'v1.1-beta.5',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              if (widget.canvasViewModel != null)
                IconButton(
                  key: const Key('open_canvas_hub_button'),
                  tooltip: 'Canvas Hub (Announcements, Activities & Reminders)',
                  onPressed: _openCanvasHub,
                  icon: Badge(
                    isLabelVisible: vm.canvasActivities.isNotEmpty,
                    label: Text('${vm.canvasActivities.length}'),
                    child: const Icon(Icons.school_outlined),
                  ),
                ),
              IconButton(
                key: const Key('alarm_setup_button'),
                tooltip: 'Alarm & Silent-Bypass Setup',
                onPressed: _openAlarmSetup,
                icon: Badge(
                  isLabelVisible: vm.permissionStatus.needsAttention,
                  child: const Icon(Icons.notifications_active_outlined),
                ),
              ),
              IconButton(
                key: const Key('settings_button'),
                tooltip: 'Settings & History',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          body: vm.isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: <Widget>[
                    if (vm.permissionStatus.needsAttention)
                      _AlertStrip(
                        icon: Icons.warning_amber_rounded,
                        message: 'Grant alarm permissions so vibration reminders fire on time while unused.',
                        actionLabel: 'Setup',
                        onAction: _openAlarmSetup,
                      ),
                    if (vm.bannerMessage != null)
                      _AlertStrip(
                        icon: Icons.info_outline,
                        message: vm.bannerMessage!,
                        actionLabel: 'Dismiss',
                        onAction: vm.clearBanner,
                      ),
                    _WeekdayStrip(
                      selectedWeekday: vm.selectedWeekday,
                      countForDay: vm.subjectCountForDay,
                      eventCountForDay: vm.eventCountForDay,
                      onSelect: vm.selectWeekday,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  weekdayFullLabel(vm.selectedWeekday),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${daySubjects.length} ${daySubjects.length == 1 ? 'subject' : 'subjects'} · ${dayEvents.length} ${dayEvents.length == 1 ? 'event' : 'events'} · ${vm.totalActiveAlarmCount} alarms',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('add_event_button'),
                            onPressed: () => _openEventForm(),
                            icon: const Icon(Icons.campaign_outlined, size: 18),
                            label: const Text('Add Event'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: vm.errorMessage != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  vm.errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            )
                          : (daySubjects.isEmpty && dayEvents.isEmpty)
                          ? _EmptyDayView(
                              weekday: vm.selectedWeekday,
                              onAddPressed: () => _openClassForm(),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                              children: <Widget>[
                                if (nextUp != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _NextClassSummaryCard(
                                      item: nextUp.item,
                                      isInProgress: nextUp.isInProgress,
                                      minutesUntilStart:
                                          nextUp.minutesUntilStart,
                                    ),
                                  ),
                                ...dayEvents.map((event) {
                                  final affected = vm
                                      .affectedSessionsForDayEvent(
                                        event,
                                        vm.selectedWeekday,
                                      );
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _EventAnnouncementCard(
                                      event: event,
                                      affectedSessions: affected,
                                      onEdit: () =>
                                          _openEventForm(existing: event),
                                      onDelete: () =>
                                          _confirmDeleteEvent(event),
                                      onToggleReminder: (enabled) =>
                                          vm.toggleEventReminder(
                                            event.id,
                                            enabled,
                                          ),
                                    ),
                                  );
                                }),
                                ...daySubjects.map((group) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _SubjectDayCard(
                                      group: group,
                                      conflictingEventsForSession: (session) =>
                                          vm.conflictingEventsForSessionOnDay(
                                            group.weekday,
                                            session,
                                          ),
                                      onTap: () => _openSubjectDetails(
                                        group.schedule,
                                        group.weekday,
                                      ),
                                      onEdit: () => _openClassForm(
                                        existing: group.schedule,
                                      ),
                                      onDelete: () => _confirmDeleteSchedule(
                                        group.schedule,
                                      ),
                                      onToggleReminder: (enabled) =>
                                          vm.toggleReminder(
                                            group.schedule.id,
                                            enabled,
                                          ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                    ),
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('add_schedule_fab'),
            onPressed: () => _openClassForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add Class'),
          ),
        );
      },
    );
  }
}

class _EventAnnouncementCard extends StatelessWidget {
  const _EventAnnouncementCard({
    required this.event,
    required this.affectedSessions,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReminder,
  });

  final EventSchedule event;
  final List<DaySessionItem> affectedSessions;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleReminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCancellation = affectedSessions.isNotEmpty;
    final bg = hasCancellation
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final fg = hasCancellation
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;

    return Card(
      color: bg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(hasCancellation ? Icons.campaign : Icons.event, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      hasCancellation
                          ? 'CLASSES CANCELED · ${event.title}'
                          : 'EVENT · ${event.title}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${event.period.label} · ${event.formatTimeSummary()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasCancellation) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        'Affected: ${affectedSessions.map((s) => s.shortSummary).join(', ')}',
                        style: theme.textTheme.bodySmall?.copyWith(color: fg),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                iconColor: fg,
                tooltip: 'Event actions',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'toggle') {
                    onToggleReminder(!event.reminderEnabled);
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit event'),
                  ),
                  PopupMenuItem<String>(
                    value: 'toggle',
                    child: Text(
                      event.reminderEnabled ? 'Mute alarm' : 'Enable alarm',
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete event'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip({
    required this.selectedWeekday,
    required this.countForDay,
    required this.eventCountForDay,
    required this.onSelect,
  });

  final int selectedWeekday;
  final int Function(int weekday) countForDay;
  final int Function(int weekday) eventCountForDay;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: kSchoolWeekdays.map((day) {
          final selected = day == selectedWeekday;
          final count = countForDay(day);
          final hasEvent = eventCountForDay(day) > 0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                button: true,
                selected: selected,
                label:
                    '${weekdayFullLabel(day)}, $count classes${hasEvent ? ', has event' : ''}',
                child: InkWell(
                  key: Key('weekday_tab_$day'),
                  onTap: () => onSelect(day),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              weekdayShortLabel(day),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            if (hasEvent) ...<Widget>[
                              const SizedBox(width: 3),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? colorScheme.onPrimary
                                      : colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? colorScheme.onPrimary.withValues(alpha: 0.2)
                                : colorScheme.surface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SubjectDayCard extends StatelessWidget {
  const _SubjectDayCard({
    required this.group,
    required this.conflictingEventsForSession,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReminder,
  });

  final DaySubjectGroup group;
  final List<EventSchedule> Function(SessionSchedule session)
      conflictingEventsForSession;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleReminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schedule = group.schedule;
    final allCanceled = group.sessions
        .every((s) => conflictingEventsForSession(s).isNotEmpty);
    final accent = allCanceled
        ? theme.colorScheme.error
        : AppTheme.sessionColor(group.sessions.first.type, theme.brightness);

    return Card(
      key: Key('subject_card_${schedule.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 6, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    schedule.subject,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          decoration: allCanceled
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Sec ${schedule.section}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${schedule.formatSharedDaysSummary()} · Tap to view Online, Lecture & Lab',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...group.sessions.map((session) {
                              final conflicts =
                                  conflictingEventsForSession(session);
                              final canceled = conflicts.isNotEmpty;
                              final sessionAccent = canceled
                                  ? theme.colorScheme.error
                                  : AppTheme.sessionColor(
                                      session.type,
                                      theme.brightness,
                                    );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: sessionAccent.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(
                                            AppTheme.sessionIcon(session.type),
                                            size: 13,
                                            color: sessionAccent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            session.type.label,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: sessionAccent,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      session.formatTimeRange(),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        decoration: canceled
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    if (canceled)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              theme.colorScheme.errorContainer,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          'CANCELED · ${conflicts.first.title}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onErrorContainer,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  schedule.reminderEnabled
                                      ? Icons.vibration
                                      : Icons.notifications_off_outlined,
                                  size: 14,
                                  color: schedule.reminderEnabled
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  schedule.reminderEnabled
                                      ? 'Vibrate ${formatReminderLead(schedule.reminderMinutesBefore)}'
                                      : 'Muted',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Class actions',
                        onSelected: (value) {
                          if (value == 'view') {
                            onTap();
                          } else if (value == 'edit') {
                            onEdit();
                          } else if (value == 'toggle') {
                            onToggleReminder(!schedule.reminderEnabled);
                          } else if (value == 'delete') {
                            onDelete();
                          }
                        },
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'view',
                            child: Text('View Online, Lecture & Lab'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('Edit schedule'),
                          ),
                          PopupMenuItem<String>(
                            value: 'toggle',
                            child: Text(
                              schedule.reminderEnabled
                                  ? 'Mute alarm'
                                  : 'Enable alarm',
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Remove from schedule'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectDetailSheet extends StatelessWidget {
  const _SubjectDetailSheet({
    required this.schedule,
    required this.weekday,
    required this.conflictingEventsForSession,
    required this.onEdit,
    required this.onToggleReminder,
    required this.onDelete,
  });

  final SubjectSchedule schedule;
  final int weekday;
  final List<EventSchedule> Function(SessionSchedule session)
      conflictingEventsForSession;
  final VoidCallback onEdit;
  final VoidCallback onToggleReminder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('subject_detail_sheet'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        schedule.subject,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Section ${schedule.section} · ${schedule.formatSharedDaysSummary()}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Sec ${schedule.section}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...SessionType.values.map((type) {
              final session = schedule.sessions[type];
              final conflicts = session != null
                  ? conflictingEventsForSession(session)
                  : const <EventSchedule>[];
              final isCanceled = conflicts.isNotEmpty;
              final accent = session == null
                  ? cs.outline
                  : (isCanceled
                      ? cs.error
                      : AppTheme.sessionColor(type, theme.brightness));

              return Card(
                key: Key('detail_session_${type.key}'),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: accent.withValues(alpha: 0.14),
                    foregroundColor: accent,
                    child: Icon(AppTheme.sessionIcon(type)),
                  ),
                  title: Text(
                    type.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: session == null
                      ? Text(
                          'Not scheduled',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              session.formatTimeRange(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: isCanceled
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (isCanceled)
                              Text(
                                'CANCELED on ${weekdayShortLabel(weekday)} · ${conflicts.first.title}',
                                style: TextStyle(
                                  color: cs.error,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                ),
              );
            }),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(
                  schedule.reminderEnabled
                      ? Icons.vibration
                      : Icons.notifications_off_outlined,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    schedule.reminderEnabled
                        ? 'Silent vibration alarm · ${formatReminderLead(schedule.reminderMinutesBefore)} (no audio, vibrates until Stop)'
                        : 'Vibration alarm muted',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  key: const Key('detail_edit_schedule_button'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit Schedule'),
                ),
                OutlinedButton.icon(
                  onPressed: onToggleReminder,
                  icon: Icon(
                    schedule.reminderEnabled
                        ? Icons.notifications_off_outlined
                        : Icons.vibration,
                    size: 18,
                  ),
                  label: Text(
                    schedule.reminderEnabled ? 'Mute Alarm' : 'Enable Alarm',
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDayView extends StatelessWidget {
  const _EmptyDayView({required this.weekday, required this.onAddPressed});

  final int weekday;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.event_note_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No classes on ${weekdayFullLabel(weekday)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a subject with Section A–Z and Online Time, Lecture, or Laboratory times.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add),
              label: Text('Add for ${weekdayShortLabel(weekday)}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertStrip extends StatelessWidget {
  const _AlertStrip({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextClassSummaryCard extends StatelessWidget {
  const _NextClassSummaryCard({
    required this.item,
    required this.isInProgress,
    required this.minutesUntilStart,
  });

  final DaySessionItem item;
  final bool isInProgress;
  final int minutesUntilStart;

  String _formatLead() {
    if (isInProgress) return 'In progress now';
    if (minutesUntilStart < 60) return 'Starts in $minutesUntilStart min';
    final hours = minutesUntilStart ~/ 60;
    final mins = minutesUntilStart % 60;
    return mins == 0 ? 'Starts in ${hours}h' : 'Starts in ${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      key: const Key('next_class_card'),
      color: cs.primaryContainer.withValues(alpha: 0.72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              child: Icon(
                isInProgress ? Icons.play_arrow_rounded : Icons.schedule,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${isInProgress ? 'NOW' : 'UP NEXT'} · ${_formatLead()}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.schedule.subject} · Sec ${item.schedule.section}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${item.session.type.label} · ${item.session.formatTimeRange()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
