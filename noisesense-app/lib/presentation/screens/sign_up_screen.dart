import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../theme/app_theme.dart';
import '../validators.dart';
import '../view_models/auth_view_model.dart';
import '../widgets/busy_button.dart';
import '../widgets/message_banner.dart';
import '../widgets/screen_shell.dart';

/// Registration form.
///
/// Reached by a deliberate push from sign-in, so it offers a way back. On
/// success it pops itself and the gate shows the confirmation step, which
/// keeps a dead screen off the navigation stack.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.auth});

  final AuthViewModel auth;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  // No "confirm password" field. An earlier build had one, as compensation
  // for the lack of a password reset: with no way to recover, a mistyped
  // password was permanent. Now that reset exists the mistake costs one email,
  // and the field's own cost, extra typing on a form where every field is a
  // point of abandonment, is no longer paid for. The show-password toggle
  // lets the user check what they typed, which catches the same error at
  // the moment it is made.

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final created = await widget.auth.signUp(
      email: _email.text,
      password: _password.text,
    );
    // `mounted` is checked because the await above spans a network call, and
    // the user may have navigated away before it returned. Using a
    // BuildContext after its widget is gone is a crash.
    if (!created || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        final auth = widget.auth;
        return ScreenShell(
          title: 'Create an account',
          showBackButton: true,
          children: [
            const Text(
              'Your readings are stored against your account so you can see '
              'how your exposure changes over time.',
              style: TextStyle(
                color: AppTheme.onSurfaceMuted,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            // Stated up front rather than discovered after submitting. The
            // app records aggregated numbers only, and saying so at the point
            // of asking for an email address is where it carries weight.
            const Text(
              'NoiseSense measures sound levels on your phone and keeps only '
              'the numbers. Recordings are discarded on the device and never '
              'uploaded.',
              style: TextStyle(
                color: AppTheme.onSurfaceMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            MessageBanner(message: auth.errorMessage),
            if (auth.errorMessage != null)
              const SizedBox(height: AppTheme.spaceMd),
            Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _email,
                      validator: Validators.email,
                      enabled: !auth.isBusy,
                      keyboardType: TextInputType.emailAddress,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        helperText:
                            'We send a confirmation code to this address.',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    TextFormField(
                      controller: _password,
                      validator: Validators.newPassword,
                      enabled: !auth.isBusy,
                      obscureText: !_showPassword,
                      // `newPassword` rather than `password`, so Android
                      // offers to generate and save one instead of trying to
                      // fill an existing credential.
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        // The rules are shown before the user types, not
                        // revealed as failures afterwards (WCAG 2.2 SC 3.3.2
                        // Labels or Instructions).
                        helperText:
                            'At least ${AppConfig.passwordMinLength} characters, '
                            'with a capital letter, a lower-case letter and a number.',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          color: AppTheme.onSurfaceMuted,
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            BusyButton(
              label: 'Create account',
              isBusy: auth.isBusy,
              onPressed: _submit,
            ),
          ],
        );
      },
    );
  }
}
