import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_routes.dart';
import '../../../core/majestic_chrome.dart';
import '../../legal/legal_documents_page.dart';
import '../view_models/auth_view_model.dart';

String? _validateEmail(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'Enter your email address';
  if (!trimmed.contains('@') || !trimmed.contains('.')) {
    return 'Enter a valid email address';
  }
  return null;
}

String? _validateSixDigitCode(String? value) {
  final trimmed = value?.trim() ?? '';
  if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) {
    return 'Enter the 6-digit verification code';
  }
  return null;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.viewModel});

  final AuthViewModel viewModel;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await widget.viewModel.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  Future<void> _openPasswordRecovery() async {
    widget.viewModel.clearMessages();
    final recoveredEmail = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ForgotPasswordOtpDialog(
        viewModel: widget.viewModel,
        initialEmail: _emailController.text.trim(),
      ),
    );
    if (!mounted || recoveredEmail == null) return;
    _emailController.text = recoveredEmail;
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        CelestialHorizonBanner(
                          borderRadius: BorderRadius.circular(16),
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                          child: Column(
                            children: <Widget>[
                              const SeiRemindsEmblem(size: 54),
                              const SizedBox(height: 12),
                              Text(
                                'SeiReminds',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sign in with a verified account (online) to access Canvas token settings & updates. Schedules, events, history, and alarms work offline.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (vm.errorMessage != null)
                          _AuthBanner(
                            message: vm.errorMessage!,
                            isError: true,
                          ),
                        if (vm.infoMessage != null)
                          _AuthBanner(
                            message: vm.infoMessage!,
                            isError: false,
                          ),
                        TextFormField(
                          key: const Key('auth_email_field'),
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const <String>[AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('auth_password_field'),
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const <String>[AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter your password';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const Key('auth_forgot_password_button'),
                            onPressed: vm.isBusy ? null : _openPasswordRecovery,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          key: const Key('auth_sign_in_button'),
                          onPressed: vm.isBusy ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: vm.isBusy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sign In'),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            const Text('New to SeiReminds?'),
                            TextButton(
                              key: const Key('go_to_sign_up_button'),
                              onPressed: vm.isBusy
                                  ? null
                                  : () {
                                      vm.clearMessages();
                                      Navigator.of(context)
                                          .pushNamed(AppRoutes.signUp);
                                    },
                              child: const Text('Create Account'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('continue_offline_button'),
                          onPressed: vm.isBusy
                              ? null
                              : () {
                                  vm.clearMessages();
                                  Navigator.of(context).pushNamedAndRemoveUntil(
                                    AppRoutes.home,
                                    (_) => false,
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          icon: const Icon(Icons.cloud_off_outlined, size: 18),
                          label: const Text('Continue Offline (Schedules & Alarms)'),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 4,
                          children: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const LegalDocumentPage.privacyPolicy(),
                                  ),
                                );
                              },
                              child: const Text('Privacy Policy'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const LegalDocumentPage.termsOfService(),
                                  ),
                                );
                              },
                              child: const Text('Terms of Service'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ForgotPasswordOtpDialog extends StatefulWidget {
  const _ForgotPasswordOtpDialog({
    required this.viewModel,
    required this.initialEmail,
  });

  final AuthViewModel viewModel;
  final String initialEmail;

  @override
  State<_ForgotPasswordOtpDialog> createState() =>
      _ForgotPasswordOtpDialogState();
}

class _ForgotPasswordOtpDialogState extends State<_ForgotPasswordOtpDialog> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _codeSent = false;
  bool _obscurePassword = true;
  int _resendsRemaining = AuthViewModel.maxOtpResends;
  String? _localMessage;
  bool _localIsError = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _sendCode({required bool isResend}) async {
    if (!isResend && !(_emailFormKey.currentState?.validate() ?? false)) return;
    if (isResend && _resendsRemaining <= 0) return;

    final result = await widget.viewModel.requestPasswordRecoveryCode(
      _emailController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _localMessage = result.message;
      _localIsError = !result.succeeded;
      if (result.succeeded) {
        _codeSent = true;
        _resendsRemaining = result.resendsRemaining ??
            (isResend
                ? (_resendsRemaining - 1).clamp(0, AuthViewModel.maxOtpResends)
                : AuthViewModel.maxOtpResends);
      } else if (result.resendsRemaining != null) {
        _resendsRemaining = result.resendsRemaining!;
      }
    });
  }

  Future<void> _confirmReset() async {
    if (!(_resetFormKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim().toLowerCase();
    final result = await widget.viewModel.verifyPasswordRecoveryCode(
      email: email,
      code: _codeController.text.trim(),
      newPassword: _passwordController.text,
    );
    if (!mounted) return;
    if (result.succeeded) {
      Navigator.of(context).pop(email);
      return;
    }
    setState(() {
      _localMessage = result.message;
      _localIsError = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final busy = widget.viewModel.isBusy;
        return AlertDialog(
          title: Text(_codeSent ? 'Enter 6-Digit Recovery Code' : 'Password Recovery'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_localMessage != null)
                    _AuthBanner(
                      message: _localMessage!,
                      isError: _localIsError,
                    ),
                  if (!_codeSent)
                    Form(
                      key: _emailFormKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Text(
                            'We will send a 6-digit recovery code directly to your registered email.',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('recovery_email_field'),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Account Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: _validateEmail,
                          ),
                        ],
                      ),
                    )
                  else
                    Form(
                      key: _resetFormKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Code sent to ${_emailController.text.trim().toLowerCase()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('recovery_otp_field'),
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: '6-Digit Recovery Code',
                              prefixIcon: Icon(Icons.pin_outlined),
                            ),
                            validator: _validateSixDigitCode,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            key: const Key('recovery_new_password_field'),
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'New Password',
                              helperText: 'At least 6 characters',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            key: const Key('recovery_confirm_password_field'),
                            controller: _confirmController,
                            obscureText: _obscurePassword,
                            decoration: const InputDecoration(
                              labelText: 'Confirm New Password',
                              prefixIcon: Icon(Icons.lock_reset_outlined),
                            ),
                            validator: (value) {
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const Key('resend_recovery_code_button'),
                              onPressed: busy || _resendsRemaining <= 0
                                  ? null
                                  : () => _sendCode(isResend: true),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text(
                                _resendsRemaining > 0
                                    ? 'Resend Code ($_resendsRemaining left)'
                                    : 'Resend Limit Reached (0 left)',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (!_codeSent)
              FilledButton(
                key: const Key('send_recovery_code_button'),
                onPressed: busy ? null : () => _sendCode(isResend: false),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send 6-Digit Code'),
              )
            else
              FilledButton(
                key: const Key('confirm_recovery_reset_button'),
                onPressed: busy ? null : _confirmReset,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Reset Password'),
              ),
          ],
        );
      },
    );
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key, required this.viewModel});

  final AuthViewModel viewModel;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _otpController = TextEditingController();

  bool _obscurePassword = true;
  bool _awaitingVerificationCode = false;
  bool _acceptedLegalTerms = false;
  String? _consentError;
  int _resendsRemaining = AuthViewModel.maxOtpResends;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendVerificationCode({required bool isResend}) async {
    if (!isResend) {
      final formValid = _formKey.currentState?.validate() ?? false;
      if (!_acceptedLegalTerms) {
        setState(() {
          _consentError =
              'You must agree to the Privacy Policy and Terms of Service to create an account.';
        });
        return;
      }
      if (!formValid) return;
      if (_consentError != null) {
        setState(() => _consentError = null);
      }
    }
    if (isResend && _resendsRemaining <= 0) return;

    final result = await widget.viewModel.requestSignUpCode(
      email: _emailController.text,
      displayName: _nameController.text,
    );
    if (!mounted) return;
    setState(() {
      if (result.succeeded) {
        _awaitingVerificationCode = true;
        _resendsRemaining = result.resendsRemaining ??
            (isResend
                ? (_resendsRemaining - 1).clamp(0, AuthViewModel.maxOtpResends)
                : AuthViewModel.maxOtpResends);
      } else if (result.resendsRemaining != null) {
        _resendsRemaining = result.resendsRemaining!;
      }
    });
  }

  Future<void> _verifyAndCreateAccount() async {
    if (!(_otpFormKey.currentState?.validate() ?? false)) return;
    await widget.viewModel.verifySignUpCode(
      email: _emailController.text,
      code: _otpController.text,
      password: _passwordController.text,
      displayName: _nameController.text,
      legalConsentVersion: kLegalPolicyVersion,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return Scaffold(
          appBar: AppBar(title: const Text('Create Account')),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      CelestialHorizonBanner(
                        borderRadius: BorderRadius.circular(16),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: <Widget>[
                            const SeiRemindsEmblem(size: 46),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    _awaitingVerificationCode
                                        ? 'Verify your email'
                                        : 'Create your SeiReminds account',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _awaitingVerificationCode
                                        ? 'Enter the 6-digit verification code sent to ${_emailController.text.trim().toLowerCase()} to complete signup and unlock Canvas token setup.'
                                        : 'We send a 6-digit verification code directly to your email. A verified account is required to connect your Canvas token.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (vm.errorMessage != null)
                        _AuthBanner(
                          message: vm.errorMessage!,
                          isError: true,
                        ),
                      if (vm.infoMessage != null)
                        _AuthBanner(
                          message: vm.infoMessage!,
                          isError: false,
                        ),
                      if (!_awaitingVerificationCode)
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextFormField(
                                key: const Key('signup_name_field'),
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Display Name (optional)',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                key: const Key('signup_email_field'),
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: _validateEmail,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                key: const Key('signup_password_field'),
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  helperText: 'At least 6 characters',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      );
                                    },
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                key: const Key('signup_confirm_password_field'),
                                controller: _confirmController,
                                obscureText: _obscurePassword,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm Password',
                                  prefixIcon: Icon(Icons.lock_reset_outlined),
                                ),
                                validator: (value) {
                                  if (value != _passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                key: const Key('signup_legal_consent_checkbox'),
                                value: _acceptedLegalTerms,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: vm.isBusy
                                    ? null
                                    : (checked) {
                                        setState(() {
                                          _acceptedLegalTerms =
                                              checked ?? false;
                                          if (_acceptedLegalTerms) {
                                            _consentError = null;
                                          }
                                        });
                                      },
                                title: Text(
                                  'I have read and agree to the Privacy Policy and Terms of Service (v$kLegalPolicyVersion).',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Wrap(
                                spacing: 4,
                                children: <Widget>[
                                  TextButton(
                                    key: const Key('signup_open_privacy_link'),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const LegalDocumentPage
                                                  .privacyPolicy(),
                                        ),
                                      );
                                    },
                                    child: const Text('Read Privacy Policy'),
                                  ),
                                  TextButton(
                                    key: const Key('signup_open_terms_link'),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const LegalDocumentPage
                                                  .termsOfService(),
                                        ),
                                      );
                                    },
                                    child: const Text('Read Terms'),
                                  ),
                                ],
                              ),
                              if (_consentError != null) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  _consentError!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              FilledButton(
                                key: const Key('auth_sign_up_button'),
                                onPressed: vm.isBusy
                                    ? null
                                    : () => _sendVerificationCode(
                                          isResend: false,
                                        ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                child: vm.isBusy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Send 6-Digit Code'),
                              ),
                            ],
                          ),
                        )
                      else
                        Form(
                          key: _otpFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextFormField(
                                key: const Key('signup_otp_field'),
                                controller: _otpController,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: '6-Digit Verification Code',
                                  prefixIcon: Icon(Icons.pin_outlined),
                                ),
                                validator: _validateSixDigitCode,
                                onFieldSubmitted: (_) =>
                                    _verifyAndCreateAccount(),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                key: const Key('verify_signup_code_button'),
                                onPressed: vm.isBusy
                                    ? null
                                    : _verifyAndCreateAccount,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                child: vm.isBusy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Verify & Create Account'),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                key: const Key('resend_signup_code_button'),
                                onPressed: vm.isBusy || _resendsRemaining <= 0
                                    ? null
                                    : () => _sendVerificationCode(
                                          isResend: true,
                                        ),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text(
                                  _resendsRemaining > 0
                                      ? 'Resend Code ($_resendsRemaining left)'
                                      : 'Resend Limit Reached (0 left)',
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                key: const Key('edit_signup_details_button'),
                                onPressed: vm.isBusy
                                    ? null
                                    : () {
                                        vm.clearMessages();
                                        _otpController.clear();
                                        setState(() {
                                          _awaitingVerificationCode = false;
                                        });
                                      },
                                child: const Text('Change email or details'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: vm.isBusy
                            ? null
                            : () {
                                vm.clearMessages();
                                Navigator.of(context).pop();
                              },
                        child: const Text('Already have an account? Sign In'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AuthBanner extends StatelessWidget {
  const _AuthBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isError ? cs.errorContainer : cs.secondaryContainer;
    final fg = isError ? cs.onErrorContainer : cs.onSecondaryContainer;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: fg,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: fg, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
