import 'package:flutter/material.dart';

import '../../../../domain/models/schedule_models.dart';
import '../../../core/app_theme.dart';
import '../view_models/schedule_view_model.dart';
import 'alarm_setup_sheet.dart';
import 'subject_schedule_form_page.dart';

class ScheduleHomePage extends StatefulWidget {
  const ScheduleHomePage({super.key, required this.viewModel});

  final ScheduleViewModel viewModel;

  @override
  State<ScheduleHomePage> createState() => _ScheduleHomePageState();
}

class _ScheduleHomePageState extends State<ScheduleHomePage> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.initialize();
  }

  Future<void> _openForm({SubjectSchedule? existing}) async {
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
          '${result.subject} (Sec ${result.section}) saved offline.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(SubjectSchedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete class schedule?'),
        content: Text(
          'Remove ${schedule.subject} (Sec ${schedule.section}) and cancel its weekly reminders?',
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
      await widget.viewModel.deleteSchedule(schedule.id);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final daySessions = vm.selectedDaySessions;

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Beta · Offline',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              IconButton(
                key: const Key('alarm_setup_button'),
                tooltip: 'Alarm & Silent-Bypass Setup',
                onPressed: _openAlarmSetup,
                icon: Badge(
                  isLabelVisible: vm.permissionStatus.needsAttention,
                  child: const Icon(Icons.notifications_active_outlined),
                ),
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
                        message:
                            'Grant alarm permissions so reminders bypass silent mode while unused.',
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
                      countForDay: vm.sessionCountForDay,
                      onSelect: vm.selectWeekday,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: <Widget>[
                          Text(
                            weekdayFullLabel(vm.selectedWeekday),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${daySessions.length} ${daySessions.length == 1 ? 'session' : 'sessions'} · ${vm.totalActiveAlarmCount} alarms',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
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
                          : daySessions.isEmpty
                              ? _EmptyDayView(
                                  weekday: vm.selectedWeekday,
                                  onAddPressed: () => _openForm(),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    96,
                                  ),
                                  itemCount: daySessions.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final item = daySessions[index];
                                    return _SessionCard(
                                      item: item,
                                      onEdit: () =>
                                          _openForm(existing: item.schedule),
                                      onDelete: () =>
                                          _confirmDelete(item.schedule),
                                      onToggleReminder: (enabled) =>
                                          vm.toggleReminder(
                                        item.schedule.id,
                                        enabled,
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('add_schedule_fab'),
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add Class'),
          ),
        );
      },
    );
  }
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip({
    required this.selectedWeekday,
    required this.countForDay,
    required this.onSelect,
  });

  final int selectedWeekday;
  final int Function(int weekday) countForDay;
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
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                button: true,
                selected: selected,
                label: '${weekdayFullLabel(day)}, $count classes',
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

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReminder,
  });

  final DaySessionItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleReminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.sessionColor(item.session.type, theme.brightness);
    final schedule = item.schedule;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
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
                      SizedBox(
                        width: 78,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.session.timeIn.format12Hour(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.session.timeOut.format12Hour(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    schedule.subject,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
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
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        AppTheme.sessionIcon(item.session.type),
                                        size: 14,
                                        color: accent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        item.session.type.label,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: accent,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      schedule.reminderEnabled
                                          ? Icons.notifications_active
                                          : Icons.notifications_off_outlined,
                                      size: 14,
                                      color: schedule.reminderEnabled
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      schedule.reminderEnabled
                                          ? formatReminderLead(
                                              schedule.reminderMinutesBefore,
                                            )
                                          : 'Muted',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Class actions',
                        onSelected: (value) {
                          if (value == 'edit') {
                            onEdit();
                          } else if (value == 'toggle') {
                            onToggleReminder(!schedule.reminderEnabled);
                          } else if (value == 'delete') {
                            onDelete();
                          }
                        },
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
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
                            child: Text('Delete subject'),
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

class _EmptyDayView extends StatelessWidget {
  const _EmptyDayView({
    required this.weekday,
    required this.onAddPressed,
  });

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
