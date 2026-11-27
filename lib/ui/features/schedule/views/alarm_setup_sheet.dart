import 'package:flutter/material.dart';

import '../../../../data/services/alarm_service.dart';
import '../view_models/schedule_view_model.dart';

class AlarmSetupSheet extends StatefulWidget {
  const AlarmSetupSheet({super.key, required this.viewModel});

  final ScheduleViewModel viewModel;

  @override
  State<AlarmSetupSheet> createState() => _AlarmSetupSheetState();
}

class _AlarmSetupSheetState extends State<AlarmSetupSheet>
    with WidgetsBindingObserver {
  bool _testTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.viewModel.refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.viewModel.refreshPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final AlarmPermissionStatus status = widget.viewModel.permissionStatus;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.notifications_active,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Alarms & Notifications Setup',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'All SeiReminds alerts bypass Silent Mode and Do Not Disturb while keeping alarms and pop-ups strictly separate:\n'
                  '• Class Schedules use a repeating vibration alarm with a Stop button.\n'
                  '• Canvas updates use a brief notification pop-up only (never an alarm).',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (!status.isAndroidSupported)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.info_outline),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Native silent-bypass alarms run on Android devices. Schedules still save offline here.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...<Widget>[
                  _PermissionTile(
                    title: 'Notifications',
                    subtitle:
                        'Shows the floating heads-up alarm banner & Stop button over your homescreen or any app.',
                    granted: status.notificationsGranted,
                    actionLabel: 'Allow',
                    onAction: widget.viewModel.requestNotificationPermission,
                  ),
                  _PermissionTile(
                    title: 'Pop-Up Alarm Banners',
                    subtitle:
                        'Keeps the priority alarm banner pinned over other apps & homescreen without opening SeiReminds.',
                    granted: status.fullScreenIntentAllowed,
                    actionLabel: 'Enable',
                    onAction: widget.viewModel.openFullScreenIntentSettings,
                  ),
                  _PermissionTile(
                    title: 'Exact Class Alarms',
                    subtitle: 'Fires on time even if the app is unused or in Doze.',
                    granted: status.exactAlarmsAllowed,
                    actionLabel: 'Enable',
                    onAction: widget.viewModel.openExactAlarmSettings,
                  ),
                  _PermissionTile(
                    title: 'Unrestricted Battery',
                    subtitle: 'Stops Android from blocking reminders when app is idle.',
                    granted: status.ignoringBatteryOptimizations,
                    actionLabel: 'Allow',
                    onAction: widget.viewModel.openBatteryOptimizationSettings,
                  ),
                  _PermissionTile(
                    title: 'Bypass Do Not Disturb (All Notifications & Alarms)',
                    subtitle:
                        'Required by Android so both Class Schedule alarms and Canvas notification pop-ups bypass strict Do Not Disturb and Silent Mode.',
                    granted: status.dndAccessGranted,
                    actionLabel: 'Allow',
                    onAction: widget.viewModel.openDndSettings,
                  ),
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        Icons.alarm_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: const Text('Class Alarm Channel Settings'),
                      subtitle: const Text(
                        'Verify Floating / Pop on screen & Override Do Not Disturb for Class Schedule alarms.',
                      ),
                      trailing: TextButton(
                        onPressed: widget.viewModel.openAlarmChannelSettings,
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        Icons.notifications_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: const Text('Canvas Pop-up Channel Settings'),
                      subtitle: const Text(
                        'Separate notification pop-up channel for Canvas announcements & activities (bypasses DND without ringing as an alarm).',
                      ),
                      trailing: TextButton(
                        onPressed: widget.viewModel.openCanvasChannelSettings,
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: status.isAndroidSupported
                            ? () async {
                                await widget.viewModel.triggerTestAlarm();
                                if (mounted) {
                                  setState(() => _testTriggered = true);
                                }
                              }
                            : null,
                        icon: const Icon(Icons.vibration),
                        label: const Text('Test Class Alarm'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: status.isAndroidSupported
                          ? () async {
                              await widget.viewModel.stopActiveAlarm();
                              if (mounted) {
                                setState(() => _testTriggered = false);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('test_canvas_popup_button'),
                  onPressed: status.isAndroidSupported
                      ? () async {
                          await widget.viewModel.triggerTestCanvasNotification();
                        }
                      : null,
                  icon: const Icon(Icons.notifications_none_rounded),
                  label: const Text('Test Canvas Pop-up (Not an Alarm)'),
                ),
                if (_testTriggered) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'Priority vibration alarm active (no audio). Tap Stop right on the notification banner (or here) to stop vibrating.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final bool granted;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final readyColor = theme.brightness == Brightness.dark
        ? const Color(0xFF86EFAC)
        : const Color(0xFF15803D);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          granted ? Icons.check_circle : Icons.warning_amber_rounded,
          color: granted ? readyColor : colorScheme.error,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: granted
            ? Text(
                'Ready',
                style: TextStyle(
                  color: readyColor,
                  fontWeight: FontWeight.w600,
                ),
              )
            : TextButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
      ),
    );
  }
}
