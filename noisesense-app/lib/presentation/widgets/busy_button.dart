import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Primary action button with a busy state.
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
