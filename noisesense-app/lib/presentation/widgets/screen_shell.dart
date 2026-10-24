import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Common page frame: title, padding, scrolling and width constraint.
class ScreenShell extends StatelessWidget {
  const ScreenShell({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.showBackButton = false,
    this.onRefresh,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  /// Pull-to-refresh handler, or null on screens where there is nothing to refresh.
  final Future<void> Function()? onRefresh;

  /// Whether to offer a way back.
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: showBackButton,
        actions: actions,
      ),
      body: SafeArea(
        // Top-aligned, not centred.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            // Caps line length on a tablet or a landscape phone.
            constraints: const BoxConstraints(maxWidth: 520),
            child: _maybeRefreshable(
              SingleChildScrollView(
                // Always scrollable, so pull-to-refresh works on short pages.
                physics: onRefresh == null
                    ? null
                    : const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _maybeRefreshable(Widget child) {
    final refresh = onRefresh;
    if (refresh == null) return child;
    return RefreshIndicator(
      onRefresh: refresh,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceContainer,
      child: child,
    );
  }
}
