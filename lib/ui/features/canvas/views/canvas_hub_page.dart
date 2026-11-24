import 'package:flutter/material.dart';

import '../../../../domain/models/canvas_token_models.dart';
import '../../../core/app_routes.dart';
import '../../schedule/view_models/schedule_view_model.dart';
import '../view_models/canvas_settings_view_model.dart';

/// Dedicated Canvas section with General, Announcements, Activities, and Reminders tabs.
/// Announcements stay in memory for today only; ONLY Activities are temporarily stored
/// in SQLite until their deadline expires.
class CanvasHubPage extends StatefulWidget {
  const CanvasHubPage({
    super.key,
    required this.scheduleViewModel,
    required this.canvasViewModel,
  });

  final ScheduleViewModel scheduleViewModel;
  final CanvasSettingsViewModel canvasViewModel;

  @override
  State<CanvasHubPage> createState() => _CanvasHubPageState();
}

class _CanvasHubPageState extends State<CanvasHubPage> {
  Future<void> _refresh() async {
    await widget.canvasViewModel.syncTodayUpdates();
  }

  String _formatDateTime(DateTime utc) {
    final local = utc.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.year}-$m-$d · $hh:$mm $period';
  }

  String _formatDeadlineCountdown(DateTime expiresAtUtc) {
    final remaining = expiresAtUtc.toUtc().difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return 'Deadline passed';
    if (remaining.inHours < 1) {
      return 'Due in ${remaining.inMinutes.clamp(1, 59)}m';
    }
    if (remaining.inHours < 24) {
      final mins = remaining.inMinutes.remainder(60);
      return mins == 0
          ? 'Due in ${remaining.inHours}h'
          : 'Due in ${remaining.inHours}h ${mins}m';
    }
    final days = remaining.inDays;
    return 'Due in $days ${days == 1 ? 'day' : 'days'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DefaultTabController(
      length: 4,
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          widget.scheduleViewModel,
          widget.canvasViewModel,
        ]),
        builder: (context, _) {
          final svm = widget.scheduleViewModel;
          final cvm = widget.canvasViewModel;

          final general = svm.canvasGeneralItems;
          final announcements = svm.canvasAnnouncements;
          final activities = svm.canvasActivities;
          final reminders = svm.canvasReminders;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Canvas Hub'),
              actions: <Widget>[
                if (cvm.isConnected && cvm.canSyncTodayUpdates)
                  IconButton(
                    key: const Key('canvas_hub_refresh_button'),
                    tooltip: 'Sync Canvas announcements & activities',
                    onPressed: svm.isSyncingCanvas || cvm.isBusy
                        ? null
                        : _refresh,
                    icon: svm.isSyncingCanvas
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                IconButton(
                  key: const Key('canvas_hub_settings_button'),
                  tooltip: 'Canvas Token Settings',
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.canvasSettings);
                  },
                  icon: const Icon(Icons.vpn_key_outlined),
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: <Widget>[
                  Tab(
                    key: const Key('canvas_tab_general'),
                    text: 'General (${general.length})',
                  ),
                  Tab(
                    key: const Key('canvas_tab_announcements'),
                    text: 'Announcements (${announcements.length})',
                  ),
                  Tab(
                    key: const Key('canvas_tab_activities'),
                    text: 'Activities (${activities.length})',
                  ),
                  Tab(
                    key: const Key('canvas_tab_reminders'),
                    text: 'Reminders (${reminders.length})',
                  ),
                ],
              ),
            ),
            body: Column(
              children: <Widget>[
                if (!cvm.isConnected)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Card(
                      color: cs.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Canvas is not connected yet',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Connect your Canvas API token to sync announcements, activities, and deadline reminders.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              key: const Key('canvas_hub_connect_button'),
                              onPressed: () {
                                Navigator.of(context)
                                    .pushNamed(AppRoutes.canvasSettings);
                              },
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('Connect Canvas Token'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.storage_outlined,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Announcements are live for today only (not stored in SQLite). Only Activities are saved temporarily in SQLite until their deadline expires.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (svm.canvasSyncMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        svm.canvasSyncMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      _CanvasFeedList(
                        items: general,
                        emptyIcon: Icons.inbox_outlined,
                        emptyTitle: 'No Canvas updates right now',
                        emptySubtitle:
                            'Tap Refresh to load today\'s announcements and active activities.',
                        formatDateTime: _formatDateTime,
                        formatCountdown: _formatDeadlineCountdown,
                        showReminderCountdown: false,
                      ),
                      _CanvasFeedList(
                        items: announcements,
                        emptyIcon: Icons.campaign_outlined,
                        emptyTitle: 'No announcements posted today',
                        emptySubtitle:
                            'Only current-day announcements appear here and are never saved to SQLite.',
                        formatDateTime: _formatDateTime,
                        formatCountdown: _formatDeadlineCountdown,
                        showReminderCountdown: false,
                      ),
                      _CanvasFeedList(
                        items: activities,
                        emptyIcon: Icons.assignment_outlined,
                        emptyTitle: 'No active Canvas activities',
                        emptySubtitle:
                            'Activities stay temporarily in SQLite only until their deadline is up.',
                        formatDateTime: _formatDateTime,
                        formatCountdown: _formatDeadlineCountdown,
                        showReminderCountdown: false,
                      ),
                      _CanvasFeedList(
                        items: reminders,
                        emptyIcon: Icons.alarm_outlined,
                        emptyTitle: 'No upcoming deadline reminders',
                        emptySubtitle:
                            'Active activities appear here sorted by soonest deadline.',
                        formatDateTime: _formatDateTime,
                        formatCountdown: _formatDeadlineCountdown,
                        showReminderCountdown: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CanvasFeedList extends StatelessWidget {
  const _CanvasFeedList({
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.formatDateTime,
    required this.formatCountdown,
    required this.showReminderCountdown,
  });

  final List<CanvasDailyItem> items;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final String Function(DateTime utc) formatDateTime;
  final String Function(DateTime utc) formatCountdown;
  final bool showReminderCountdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(emptyIcon, size: 52, color: cs.outline),
              const SizedBox(height: 12),
              Text(
                emptyTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isActivity = item.kind == CanvasDailyItemKind.activity;
        final deadlineText = item.hasExplicitDeadline
            ? 'Deadline: ${formatDateTime(item.dueAt!)}'
            : 'Temporary until end of day';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isActivity
                            ? cs.secondaryContainer
                            : cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        showReminderCountdown ? 'Reminder' : item.kind.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isActivity
                              ? cs.onSecondaryContainer
                              : cs.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.courseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isActivity)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          formatCountdown(item.effectiveExpiresAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.message.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    item.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  isActivity
                      ? '$deadlineText · Stored temporarily in SQLite'
                      : 'Posted ${formatDateTime(item.postedAt)} · Live only (not stored)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
