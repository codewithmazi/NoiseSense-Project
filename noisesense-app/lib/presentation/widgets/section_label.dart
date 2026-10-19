import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small muted heading above a group of content, as the wireframes use for
/// "Today's cumulative dose", "Sync" and "Account".
///
/// Marked as a header so a screen reader can jump between groups rather than
/// reading every line in order.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.onSurfaceMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
