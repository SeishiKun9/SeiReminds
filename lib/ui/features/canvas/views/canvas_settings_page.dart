import 'package:flutter/material.dart';

import '../../../../domain/models/canvas_token_models.dart';
import '../view_models/canvas_settings_view_model.dart';

class CanvasSettingsPage extends StatefulWidget {
  const CanvasSettingsPage({super.key, required this.viewModel});

  final CanvasSettingsViewModel viewModel;

  @override
  State<CanvasSettingsPage> createState() => _CanvasSettingsPageState();
}

class _CanvasSettingsPageState extends State<CanvasSettingsPage> {
  final _connectFormKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  final TextEditingController _connectTokenController = TextEditingController();
  DateTime? _connectManualExpiry;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.viewModel.baseUrl);
    Future.microtask(() async {
      await widget.viewModel.load();
      if (mounted) {
        _urlController.text = widget.viewModel.baseUrl;
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _connectTokenController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickOptionalExpirationDate(DateTime? initial) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
      helpText: 'Optional: Token expiration date from Canvas',
    );
    if (pickedDate == null) return null;
    // End of picked calendar day in local time, stored as UTC.
    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      23,
      59,
    ).toUtc();
  }

  Future<void> _submitConnect() async {
    if (!(_connectFormKey.currentState?.validate() ?? false)) return;
    final token = _connectTokenController.text;
    final result = await widget.viewModel.connectToken(
      baseUrl: _urlController.text,
      token: token,
      manualExpiresAt: _connectManualExpiry,
    );
    if (result.succeeded) {
      // Clear raw token from controller memory immediately after secure save.
      _connectTokenController.clear();
      setState(() => _connectManualExpiry = null);
    }
  }

  Future<void> _openReplaceDialog() async {
    final payload = await showDialog<
        ({String baseUrl, String token, DateTime? manualExpiresAt})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReplaceCanvasTokenDialog(
        initialBaseUrl:
            widget.viewModel.metadata?.baseUrl ?? widget.viewModel.baseUrl,
        pickOptionalDate: _pickOptionalExpirationDate,
        formatDate: _formatDate,
      ),
    );

    if (payload == null) return;

    await widget.viewModel.replaceToken(
      baseUrl: payload.baseUrl,
      replacementToken: payload.token,
      manualExpiresAt: payload.manualExpiresAt,
    );
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Canvas?'),
        content: const Text(
          'This removes your saved Canvas API token from SeiReminds encrypted storage. '
          'It will NOT revoke the token on Canvas itself.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_disconnect_canvas_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.viewModel.disconnect();
    }
  }

  String _formatDate(DateTime utc) {
    final local = utc.toLocal();
    final y = local.year.toString();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$y-$m-$d $hh:$mm $ampm';
  }

  ({Color bg, Color fg, IconData icon}) _statusStyle(
    BuildContext context,
    CanvasConnectionStatus status,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return switch (status) {
      CanvasConnectionStatus.connected ||
      CanvasConnectionStatus.replacementSuccessful =>
        (
          bg: isDark ? const Color(0xFF143824) : const Color(0xFFDFF5E3),
          fg: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF0F5132),
          icon: Icons.check_circle_outline,
        ),
      CanvasConnectionStatus.expiringSoon => (
          bg: isDark ? const Color(0xFF423007) : const Color(0xFFFFF3CD),
          fg: isDark ? const Color(0xFFFDE68A) : const Color(0xFF664D03),
          icon: Icons.schedule_outlined,
        ),
      CanvasConnectionStatus.expired ||
      CanvasConnectionStatus.invalidToken ||
      CanvasConnectionStatus.replacementValidationFailed =>
        (
          bg: cs.errorContainer,
          fg: cs.onErrorContainer,
          icon: Icons.error_outline,
        ),
      CanvasConnectionStatus.notConnected => (
          bg: cs.surfaceContainerHighest,
          fg: cs.onSurfaceVariant,
          icon: Icons.link_off,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final meta = vm.metadata;
        final status = vm.displayedStatus;
        final style = _statusStyle(context, status);
        final assessment = vm.expirationAssessment;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Canvas Settings'),
          ),
          body: vm.isLoading
              ? const Center(child: CircularProgressIndicator())
              : !vm.isOnline
                  ? Center(
                      key: const Key('canvas_offline_guard'),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 52,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Online Connection Required',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                CanvasSettingsViewModel.offlineCanvasMessage,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                key: const Key('canvas_retry_online_button'),
                                onPressed: vm.load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry Connection'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: <Widget>[
                    // Connection Status Card
                    Card(
                      color: style.bg,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(style.icon, color: style.fg),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    status.label,
                                    key: const Key('canvas_status_label'),
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: style.fg,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (vm.feedbackMessage != null) ...<Widget>[
                                    const SizedBox(height: 4),
                                    Text(
                                      vm.feedbackMessage!,
                                      key: const Key('canvas_feedback_message'),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: style.fg,
                                      ),
                                    ),
                                  ],
                                  if (status ==
                                          CanvasConnectionStatus
                                              .replacementValidationFailed &&
                                      meta != null) ...<Widget>[
                                    const SizedBox(height: 8),
                                    FilledButton.tonalIcon(
                                      key: const Key('retry_replace_button'),
                                      onPressed:
                                          vm.isBusy ? null : _openReplaceDialog,
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Retry Replacement'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Expiration Warning Card (7-day, 3-day, 24-hour, Expired, or Unverified)
                    if (assessment != null) ...<Widget>[
                      _ExpirationBanner(assessment: assessment),
                      const SizedBox(height: 12),
                    ],

                    if (vm.isBusy) ...<Widget>[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                    ],

                    if (meta != null) ...<Widget>[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Saved Canvas Connection',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _DetailRow(
                                label: 'Canvas URL',
                                value: meta.baseUrl,
                              ),
                              _DetailRow(
                                label: 'Account',
                                value:
                                    '${meta.userName} (${meta.coursesAccessibleCount} active courses)',
                              ),
                              _DetailRow(
                                label: 'Connection State',
                                value: vm.connectionStatus.label,
                              ),
                              _DetailRow(
                                label: 'Current API Token',
                                value: meta.maskedToken,
                                valueKey: const Key('canvas_masked_token'),
                              ),
                              _DetailRow(
                                label: 'Token Expiration',
                                value: meta.expiresAt != null
                                    ? '${_formatDate(meta.expiresAt!)} (${meta.expirationSource.label})'
                                    : 'Cannot be verified from Canvas API',
                                valueKey: const Key('canvas_expiration_value'),
                              ),
                              _DetailRow(
                                label: 'Last Verified',
                                value: _formatDate(meta.lastVerifiedAt),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (vm.canSyncTodayUpdates) ...<Widget>[
                        FilledButton.tonalIcon(
                          key: const Key('sync_today_canvas_from_settings_button'),
                          onPressed: vm.isBusy ? null : vm.syncTodayUpdates,
                          icon: const Icon(Icons.campaign_outlined),
                          label: const Text(
                            'Sync Today\'s Announcements & Activities',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Only activity notifications are stored temporarily in SQLite until their deadline expires. Announcements stay live for today only.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton.icon(
                        key: const Key('replace_canvas_token_button'),
                        onPressed: vm.isBusy ? null : _openReplaceDialog,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Replace API Token'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('verify_canvas_button'),
                              onPressed:
                                  vm.isBusy ? null : vm.verifyConnection,
                              icon: const Icon(Icons.verified_outlined),
                              label: const Text('Verify Token'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('disconnect_canvas_button'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                              ),
                              onPressed: vm.isBusy ? null : _confirmDisconnect,
                              icon: const Icon(Icons.link_off),
                              label: const Text('Disconnect Canvas'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...<Widget>[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Form(
                            key: _connectFormKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text(
                                  'Connect Canvas Account',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tokens are validated over HTTPS and stored only in hardware-backed encrypted storage — never in plain-text SharedPreferences or SQLite.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  key: const Key('connect_canvas_url_field'),
                                  controller: _urlController,
                                  decoration: InputDecoration(
                                    labelText: 'Canvas URL',
                                    prefixIcon: const Icon(Icons.school_outlined),
                                    suffixIcon: IconButton(
                                      tooltip: 'Reset to default HNU URL',
                                      onPressed: () {
                                        _urlController.text =
                                            kDefaultCanvasBaseUrl;
                                      },
                                      icon: const Icon(Icons.restart_alt),
                                    ),
                                  ),
                                  validator: (value) {
                                    try {
                                      normalizeCanvasBaseUrl(value ?? '');
                                      return null;
                                    } on FormatException catch (e) {
                                      return e.message;
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  key: const Key('connect_canvas_token_field'),
                                  controller: _connectTokenController,
                                  obscureText: true,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Canvas API Token',
                                    hintText: 'Paste your Canvas access token',
                                    prefixIcon: Icon(Icons.vpn_key_outlined),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Enter a Canvas API token';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        _connectManualExpiry == null
                                            ? 'Expiration: auto-checked from Canvas API (optional date if API hides it)'
                                            : 'Recorded expiration: ${_formatDate(_connectManualExpiry!)}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final picked =
                                            await _pickOptionalExpirationDate(
                                          _connectManualExpiry,
                                        );
                                        if (picked != null && mounted) {
                                          setState(
                                            () => _connectManualExpiry = picked,
                                          );
                                        }
                                      },
                                      child: Text(
                                        _connectManualExpiry == null
                                            ? 'Optional Date'
                                            : 'Change',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  key: const Key('connect_canvas_button'),
                                  onPressed: vm.isBusy ? null : _submitConnect,
                                  icon: const Icon(Icons.lock_outline),
                                  label: const Text('Validate & Connect'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ExpirationBanner extends StatelessWidget {
  const _ExpirationBanner({required this.assessment});

  final TokenExpirationAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final ({Color bg, Color fg, IconData icon}) palette =
        switch (assessment.level) {
      TokenExpirationWarningLevel.expired ||
      TokenExpirationWarningLevel.twentyFourHours =>
        (
          bg: cs.errorContainer,
          fg: cs.onErrorContainer,
          icon: Icons.warning_rounded,
        ),
      TokenExpirationWarningLevel.threeDays ||
      TokenExpirationWarningLevel.sevenDays =>
        (
          bg: isDark ? const Color(0xFF423007) : const Color(0xFFFFF3CD),
          fg: isDark ? const Color(0xFFFDE68A) : const Color(0xFF664D03),
          icon: Icons.warning_amber_rounded,
        ),
      TokenExpirationWarningLevel.unverified => (
          bg: cs.surfaceContainerHighest,
          fg: cs.onSurfaceVariant,
          icon: Icons.info_outline,
        ),
      TokenExpirationWarningLevel.none => (
          bg: isDark ? const Color(0xFF143824) : const Color(0xFFDFF5E3),
          fg: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF0F5132),
          icon: Icons.verified_user_outlined,
        ),
    };

    return Card(
      color: palette.bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(palette.icon, color: palette.fg, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                assessment.message,
                key: const Key('canvas_expiration_warning'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.fg,
                  fontWeight:
                      assessment.isWarning ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            key: valueKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplaceCanvasTokenDialog extends StatefulWidget {
  const _ReplaceCanvasTokenDialog({
    required this.initialBaseUrl,
    required this.pickOptionalDate,
    required this.formatDate,
  });

  final String initialBaseUrl;
  final Future<DateTime?> Function(DateTime? initial) pickOptionalDate;
  final String Function(DateTime utc) formatDate;

  @override
  State<_ReplaceCanvasTokenDialog> createState() =>
      _ReplaceCanvasTokenDialogState();
}

class _ReplaceCanvasTokenDialogState extends State<_ReplaceCanvasTokenDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  final TextEditingController _tokenController = TextEditingController();
  DateTime? _manualExpiry;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.clear();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Replace API Token'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Your existing Canvas token stays untouched until the new token is validated, encrypted, saved, and confirmed working.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('replace_canvas_url_field'),
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Canvas URL',
                  prefixIcon: Icon(Icons.link),
                ),
                validator: (value) {
                  try {
                    normalizeCanvasBaseUrl(value ?? '');
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('replace_canvas_token_field'),
                controller: _tokenController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'New Canvas API Token',
                  hintText: 'Paste replacement token',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a replacement Canvas API token';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _manualExpiry == null
                          ? 'Expiration date: auto-detect from Canvas API (optional fallback)'
                          : 'Recorded expiry: ${widget.formatDate(_manualExpiry!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await widget.pickOptionalDate(
                        _manualExpiry,
                      );
                      if (picked != null && mounted) {
                        setState(() => _manualExpiry = picked);
                      }
                    },
                    child: Text(_manualExpiry == null ? 'Set Date' : 'Change'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm_replace_token_button'),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop((
              baseUrl: _urlController.text,
              token: _tokenController.text,
              manualExpiresAt: _manualExpiry,
            ));
          },
          child: const Text('Validate & Replace'),
        ),
      ],
    );
  }
}
