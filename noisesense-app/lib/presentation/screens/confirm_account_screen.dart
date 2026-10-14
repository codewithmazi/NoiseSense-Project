import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../validators.dart';
import '../view_models/auth_view_model.dart';
import '../widgets/busy_button.dart';
import '../widgets/message_banner.dart';
import '../widgets/screen_shell.dart';

/// Entry of the six-digit code Cognito emails after registration.
///
/// This screen is the one most likely to trap a user, so it is built to offer
/// a way out of every dead end: the code can be resent, and the address can be
/// abandoned if it was mistyped. A confirmation screen with no escape is a
/// common reason accounts are created and never used.
///
/// Pasting is explicitly permitted and `AutofillHints.oneTimeCode` lets
/// Android offer the code straight from the SMS or notification. Forcing a
/// user to read six digits from another app and retype them from memory is
/// exactly the transcription step WCAG 2.2 SC 3.3.8 Accessible Authentication
/// exists to remove.
class ConfirmAccountScreen extends StatefulWidget {
  const ConfirmAccountScreen({super.key, required this.auth});

  final AuthViewModel auth;

  @override
  State<ConfirmAccountScreen> createState() => _ConfirmAccountScreenState();
}

class _ConfirmAccountScreenState extends State<ConfirmAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await widget.auth.confirm(code: _code.text);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        final auth = widget.auth;
        return ScreenShell(
          title: 'Confirm your email',
          children: [
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: AppTheme.onSurfaceMuted,
                  fontSize: 16,
                  height: 1.4,
                ),
                children: [
                  const TextSpan(text: 'Enter the six-digit code we sent to '),
                  // The address is shown back to the user, because a mistyped
                  // one is the most likely reason the email never arrives and
                  // they cannot diagnose that without seeing it.
                  TextSpan(
                    text: auth.pendingEmail,
                    style: const TextStyle(
                      color: AppTheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            MessageBanner(message: auth.errorMessage),
            if (auth.errorMessage != null)
              const SizedBox(height: AppTheme.spaceMd),
            MessageBanner(message: auth.notice, tone: MessageTone.info),
            if (auth.notice != null) const SizedBox(height: AppTheme.spaceMd),
            Form(
              key: _formKey,
              child: AutofillGroup(
                child: TextFormField(
                  controller: _code,
                  validator: Validators.confirmationCode,
                  enabled: !auth.isBusy,
                  autofocus: true,
                  // A numeric keypad, because the code is always digits.
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  maxLength: 6,
                  // Strips anything that cannot be part of a code, including
                  // the spaces that come with a pasted value. Filtering is
                  // used rather than rejecting the paste, so the user is
                  // helped instead of corrected.
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 24,
                    // Even digit spacing, so a six-digit code can be checked
                    // against the email at a glance.
                    letterSpacing: 8,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Confirmation code',
                    counterText: '',
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            BusyButton(
              label: 'Confirm',
              isBusy: auth.isBusy,
              onPressed: _submit,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            TextButton(
              onPressed: auth.isBusy ? null : () => widget.auth.resendCode(),
              child: const Text('Send a new code'),
            ),
            // The way out. Without this, a user who mistyped their address is
            // stuck on a screen waiting for an email that will never arrive
            // (Nielsen, 1994: user control and freedom).
            TextButton(
              onPressed: auth.isBusy ? null : () => widget.auth.signOut(),
              child: const Text('Use a different email address'),
            ),
          ],
        );
      },
    );
  }
}
