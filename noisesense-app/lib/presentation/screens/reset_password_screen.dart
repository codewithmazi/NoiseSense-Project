import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_config.dart';
import '../theme/app_theme.dart';
import '../validators.dart';
import '../view_models/auth_view_model.dart';
import '../widgets/busy_button.dart';
import '../widgets/message_banner.dart';
import '../widgets/screen_shell.dart';

/// Password reset in two steps on one screen: ask for a code, then use it.
///
/// One screen rather than two, so the back button always means "abandon the
/// reset and return to sign-in". With two pushed screens, back from step two
/// would land on step one, a form the user has already completed, which is a
/// step backwards that looks like a step sideways.
///
/// Pops with `true` when the password has been changed, so the sign-in screen
/// can fill in the address and the user only has to type the new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.auth,
    this.initialEmail = '',
  });

  final AuthViewModel auth;

  /// Whatever was already typed on the sign-in screen, so the user does not
  /// enter their address twice.
  final String initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _requestForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _codeRequested = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!(_requestForm.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final sent = await widget.auth.requestPasswordReset(email: _email.text);
    if (sent && mounted) setState(() => _codeRequested = true);
  }

  Future<void> _resendCode() async {
    await widget.auth.requestPasswordReset(email: widget.auth.resetEmail);
  }

  Future<void> _setPassword() async {
    if (!(_resetForm.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final changed = await widget.auth.confirmPasswordReset(
      code: _code.text,
      newPassword: _password.text,
    );
    if (changed && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        final auth = widget.auth;
        return ScreenShell(
          title: 'Reset password',
          showBackButton: true,
          children: [
            MessageBanner(message: auth.errorMessage),
            if (auth.errorMessage != null)
              const SizedBox(height: AppTheme.spaceMd),
            MessageBanner(message: auth.notice, tone: MessageTone.info),
            if (auth.notice != null) const SizedBox(height: AppTheme.spaceMd),
            if (!_codeRequested) ..._requestStep(auth) else ..._resetStep(auth),
          ],
        );
      },
    );
  }

  List<Widget> _requestStep(AuthViewModel auth) => [
    const Text(
      'Enter the email address you registered with and we will send a code '
      'to reset your password.',
      style: TextStyle(
        color: AppTheme.onSurfaceMuted,
        fontSize: 16,
        height: 1.4,
      ),
    ),
    const SizedBox(height: AppTheme.spaceLg),
    Form(
      key: _requestForm,
      child: TextFormField(
        controller: _email,
        validator: Validators.email,
        enabled: !auth.isBusy,
        keyboardType: TextInputType.emailAddress,
        textCapitalization: TextCapitalization.none,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _requestCode(),
        decoration: const InputDecoration(labelText: 'Email address'),
      ),
    ),
    const SizedBox(height: AppTheme.spaceLg),
    BusyButton(
      label: 'Send reset code',
      isBusy: auth.isBusy,
      onPressed: _requestCode,
    ),
  ];

  List<Widget> _resetStep(AuthViewModel auth) => [
    Form(
      key: _resetForm,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _code,
              validator: Validators.confirmationCode,
              enabled: !auth.isBusy,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.next,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                labelText: 'Reset code',
                counterText: '',
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            TextFormField(
              controller: _password,
              // The same rules as registration, because Cognito applies the
              // same policy to a reset as to a new account.
              validator: Validators.newPassword,
              enabled: !auth.isBusy,
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _setPassword(),
              decoration: InputDecoration(
                labelText: 'New password',
                helperText:
                    'At least ${AppConfig.passwordMinLength} characters, '
                    'with a capital letter, a lower-case letter and a number.',
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  color: AppTheme.onSurfaceMuted,
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: AppTheme.spaceLg),
    BusyButton(
      label: 'Set new password',
      isBusy: auth.isBusy,
      onPressed: _setPassword,
    ),
    const SizedBox(height: AppTheme.spaceSm),
    TextButton(
      onPressed: auth.isBusy ? null : _resendCode,
      child: const Text('Send a new code'),
    ),
    // The escape for a mistyped address. Without it the only way to correct
    // one is to leave the screen and start again.
    TextButton(
      onPressed: auth.isBusy
          ? null
          : () {
              auth.clearMessages();
              setState(() => _codeRequested = false);
            },
      child: const Text('Use a different email address'),
    ),
  ];
}
