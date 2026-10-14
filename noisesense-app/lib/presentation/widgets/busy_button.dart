import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's primary action button, with one defined behaviour while work is
/// in progress.
///
/// Network calls in this app can take seconds: a Lambda cold start measured in
/// experiment M2 is added to ordinary mobile latency. A button that looks
/// unchanged for that long invites a second tap, and a second tap on "Sign up"
/// is a second account attempt. So while [isBusy]:
///
/// * the callback is detached, which prevents the duplicate submission rather
///   than relying on the user not to try;
/// * a spinner replaces the label, so the wait is visibly the app's and not
///   the user's mistake (Nielsen, 1994: visibility of system status);
/// * the label is still announced to a screen reader as busy, so the state is
///   not conveyed only by an animation nobody can hear.
///
/// The button keeps its size while busy, so the layout does not jump.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isBusy = false,
  });

  final String label;

  /// The action, or null to disable the button outright.
  final VoidCallback? onPressed;

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !isBusy && onPressed != null,
      label: isBusy ? '$label, in progress' : label,
      excludeSemantics: true,
      child: FilledButton(
        onPressed: isBusy ? null : onPressed,
        child: isBusy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.onPrimary,
                ),
              )
            : Text(label),
      ),
    );
  }
}
