import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../validators.dart';
import '../view_models/auth_view_model.dart';
import '../widgets/busy_button.dart';
import '../widgets/message_banner.dart';
import '../widgets/screen_shell.dart';
import 'reset_password_screen.dart';
import 'sign_up_screen.dart';

/// Sign-in form.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});

  final AuthViewModel auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Validate locally first, so errors show next to the field.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Dismiss the keyboard, so the result is not hidden behind it.
    FocusScope.of(context).unfocus();
    await widget.auth.signIn(email: _email.text, password: _password.text);
  }

  void _openSignUp() {
    widget.auth.clearMessages();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SignUpScreen(auth: widget.auth)));
  }

  Future<void> _openReset() async {
    widget.auth.clearMessages();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ResetPasswordScreen(auth: widget.auth, initialEmail: _email.text),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      // The address used for the reset is filled in and the old password cleared.
      _email.text = widget.auth.resetEmail;
      _password.clear();
    } else {
      // Reset abandoned: drop its messages.
      widget.auth.clearMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        final auth = widget.auth;
        return ScreenShell(
          title: 'Sign in',
          children: [
            const Text(
              'Track your noise exposure over time.',
              style: TextStyle(
                color: AppTheme.onSurfaceMuted,
                fontSize: 16,
                height: 1.4,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _email,
                      validator: Validators.email,
                      enabled: !auth.isBusy,
                      keyboardType: TextInputType.emailAddress,
                      // Email addresses are case-insensitive and never capitalised.
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      // Moves to the password field instead of closing the keyboard.
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    TextFormField(
                      controller: _password,
                      validator: Validators.existingPassword,
                      enabled: !auth.isBusy,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      // Submit from the keyboard, as Enter does elsewhere.
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          // Show-password toggle, so users can check what they typed.
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          color: AppTheme.onSurfaceMuted,
                          // Labelled for screen readers.
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
              label: 'Sign in',
              isBusy: auth.isBusy,
              onPressed: _submit,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            TextButton(
              onPressed: auth.isBusy ? null : _openReset,
              child: const Text('Forgotten your password?'),
            ),
            TextButton(
              onPressed: auth.isBusy ? null : _openSignUp,
              child: const Text('Create an account'),
            ),
          ],
        );
      },
    );
  }
}
