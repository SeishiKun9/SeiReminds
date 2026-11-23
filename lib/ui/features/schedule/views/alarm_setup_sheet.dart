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
                        'Alarm & Silent-Bypass Setup',
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
                  'SeiReminds uses Android Alarm audio & Alarm vibration channels so reminders ring and vibrate hard even when your phone is on Silent and the app is closed.',
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
                    subtitle: 'Shows the lock-screen alarm card & Stop button.',
                    granted: status.notificationsGranted,
                    actionLabel: 'Allow',
                    onAction: widget.viewModel.requestNotificationPermission,
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
                    title: 'Do Not Disturb Override (Optional)',
                    subtitle: 'Normal Silent/Vibrate is already bypassed; enable this for strict DND.',
                    granted: status.dndAccessGranted,
                    actionLabel: 'Settings',
                    onAction: widget.viewModel.openDndSettings,
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
                        label: const Text('Test Loud Alarm'),
                      ),
                    ),
                    const SizedBox(width: 12),
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
                if (_testTriggered) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'Test alarm active. Try flipping your phone to Silent mode to verify sound & hard vibration, then tap Stop.',
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
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          granted ? Icons.check_circle : Icons.warning_amber_rounded,
          color: granted ? Colors.green.shade600 : colorScheme.error,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: granted
            ? Text(
                'Ready',
                style: TextStyle(
                  color: Colors.green.shade700,
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
