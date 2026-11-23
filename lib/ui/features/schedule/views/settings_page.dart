import 'package:flutter/material.dart';

import '../../../core/app_routes.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../canvas/view_models/canvas_settings_view_model.dart';
import '../view_models/schedule_view_model.dart';
import 'alarm_setup_sheet.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.viewModel,
    this.canvasViewModel,
    this.authViewModel,
  });

  final ScheduleViewModel viewModel;
  final CanvasSettingsViewModel? canvasViewModel;
  final AuthViewModel? authViewModel;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _showArchived = false;

  Future<void> _handleSoftClear() async {
    final ok = await widget.viewModel.clearHistory();
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'History cleared from view. Data is preserved in SQLite until cleared permanently — your schedules are untouched.',
        ),
      ),
    );
  }

  Future<void> _handleRestore() async {
    final ok = await widget.viewModel.restoreArchivedHistory();
    if (!mounted || !ok) return;
    setState(() => _showArchived = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared history restored.')),
    );
  }

  Future<void> _handleDailyCleanup() async {
    final result = await widget.viewModel.runDailyStorageCleanup();
    if (!mounted || result == null) return;
    final msg = result.clearedItemsCount == 0
        ? 'Daily cleanup checked (${result.dateKey}). Storage is already clean — schedules & history are untouched.'
        : 'Cleared ${result.clearedItemsCount} stale item(s) from previous days (${result.dateKey}). Schedules & history remain protected.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _handlePermanentClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history permanently?'),
        content: const Text(
          'This permanently deletes all history logs (including cleared/preserved history) from SQLite.\n\n'
          'Schedule Protection Validation: Your saved class schedules and events will NOT be deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_permanent_clear_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final ok = await widget.viewModel.permanentlyClearHistory();
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'History permanently deleted from SQLite. All active schedules remain safe.',
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime utc) {
    final local = utc.toLocal();
    final hh = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} · $hh:$mm $period';
  }

  IconData _iconForAction(String action) {
    return switch (action) {
      'schedule_added' => Icons.add_circle_outline,
      'schedule_updated' => Icons.edit_outlined,
      'schedule_deleted' => Icons.delete_outline,
      'event_added' || 'event_updated' => Icons.campaign_outlined,
      'event_deleted' => Icons.event_busy_outlined,
      'reminder_toggled' => Icons.notifications_outlined,
      _ => Icons.history,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final active = vm.activeHistory;
        final archived = vm.archivedHistory;
        final visibleList = _showArchived ? archived : active;
        final totalHistoryCount = active.length + archived.length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings & History'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              if (widget.authViewModel != null) ...<Widget>[
                ListenableBuilder(
                  listenable: widget.authViewModel!,
                  builder: (context, _) {
                    final authVm = widget.authViewModel!;
                    final user = authVm.currentUser;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: user != null
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            user != null
                                ? Icons.person_outline
                                : Icons.cloud_off_outlined,
                          ),
                        ),
                        title: Text(
                          user?.label ?? 'Offline Mode',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          user?.email ??
                              'Schedules, events, history & alarms work offline. Sign in for Canvas.',
                        ),
                        trailing: user != null
                            ? TextButton.icon(
                                key: const Key('sign_out_button'),
                                onPressed:
                                    authVm.isBusy ? null : authVm.signOut,
                                icon: const Icon(Icons.logout, size: 18),
                                label: const Text('Sign Out'),
                              )
                            : FilledButton.tonalIcon(
                                key: const Key('go_to_sign_in_from_settings'),
                                onPressed: () {
                                  Navigator.of(context)
                                      .pushNamed(AppRoutes.login);
                                },
                                icon: const Icon(Icons.login, size: 18),
                                label: const Text('Sign In'),
                              ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.storage_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Offline SQLite Database',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${vm.schedules.length} saved classes · ${vm.events.length} events · ${active.length} visible history · ${archived.length} preserved',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) => AlarmSetupSheet(viewModel: vm),
                          );
                        },
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Alarm & Silent-Bypass Setup'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                key: const Key('daily_cleanup_card'),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.auto_delete_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Daily Storage Cleanup',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Automatically clears previous days\' Canvas cache daily so storage stays light and yesterday\'s posts are never re-notified. Saved schedules & history stay protected.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        vm.lastDailyCleanupDate != null
                            ? 'Last daily cleanup: ${vm.lastDailyCleanupDate} (${vm.lastDailyCleanupRemoved} cleared today · ${vm.todayCanvasItems.length} cached for today)'
                            : 'Scheduled automatically each day',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('run_daily_cleanup_button'),
                        onPressed: _handleDailyCleanup,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Run Daily Cleanup Now'),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.canvasViewModel != null) ...<Widget>[
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: Listenable.merge(<Listenable>[
                    widget.canvasViewModel!,
                    if (widget.authViewModel != null) widget.authViewModel!,
                  ]),
                  builder: (context, _) {
                    final cvm = widget.canvasViewModel!;
                    final isSignedIn =
                        widget.authViewModel?.isAuthenticated ?? true;
                    return Card(
                      child: ListTile(
                        key: const Key('open_canvas_settings_tile'),
                        leading: Icon(
                          Icons.school_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text(
                          'Canvas Settings',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          isSignedIn
                              ? '${cvm.displayedStatus.label} · ${cvm.baseUrl}'
                              : 'Sign in required · ${cvm.baseUrl}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context)
                              .pushNamed(AppRoutes.canvasSettings);
                        },
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.secondaryContainer.withValues(
                  alpha: 0.65,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.verified_user_outlined,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Schedule Protection Active: Clearing history hides logs without deleting them until you choose Clear Permanently. Your saved class schedules will never be removed unless you delete them from your timetable.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'History',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Visible (${active.length})'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Preserved (${archived.length})'),
                      ),
                    ],
                    selected: <bool>{_showArchived},
                    onSelectionChanged: (selection) {
                      setState(() => _showArchived = selection.first);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    key: const Key('soft_clear_history_button'),
                    onPressed: active.isEmpty ? null : _handleSoftClear,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Clear History'),
                  ),
                  if (archived.isNotEmpty)
                    OutlinedButton.icon(
                      key: const Key('restore_history_button'),
                      onPressed: _handleRestore,
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore Preserved'),
                    ),
                  OutlinedButton.icon(
                    key: const Key('permanent_clear_history_button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed:
                        totalHistoryCount == 0 ? null : _handlePermanentClear,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Clear Permanently'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (visibleList.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _showArchived
                          ? 'No preserved (soft-cleared) history entries.'
                          : archived.isNotEmpty
                              ? 'History view is clear. ${archived.length} record(s) are still preserved in SQLite under "Preserved".'
                              : 'No history recorded yet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ...visibleList.map(
                  (entry) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: entry.isArchived
                            ? theme.colorScheme.surfaceContainerHighest
                            : theme.colorScheme.primaryContainer,
                        child: Icon(
                          _iconForAction(entry.action),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        entry.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(entry.details),
                          const SizedBox(height: 2),
                          Text(
                            '${_formatTimestamp(entry.createdAt)}${entry.isArchived ? ' · Preserved' : ''}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
