import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Common page frame: title, padding, scrolling and width constraint.
///
/// Every screen is built inside this, which is why navigation and spacing feel
/// the same throughout without each screen repeating the decision.
///
/// The content always scrolls, even when it currently fits. Two situations
/// make a fixed layout overflow on a real device: the keyboard appearing over
/// a form, and the user having raised the system font size. Flutter reports
/// both as a rendering error, so making every page scrollable removes a whole
/// class of defect rather than fixing each instance (WCAG 2.2 SC 1.4.4 Resize
/// Text, and SC 1.4.10 Reflow).
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

  /// Pull-to-refresh handler, or null on screens where there is nothing to
  /// refresh.
  ///
  /// Offered in addition to, not instead of, an explicit refresh: the gesture
  /// is undiscoverable and inaccessible to a user navigating by screen reader
  /// or switch control, so a screen that depends on it alone excludes them.
  final Future<void> Function()? onRefresh;

  /// Whether to offer a way back. Shown on screens reached by a deliberate
  /// push, such as sign-up, and withheld where going back is meaningless,
  /// such as the dashboard. An inoperative back arrow is worse than none
  /// (Nielsen, 1994: user control and freedom).
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
        // Top-aligned, not centred. With Center, a page shorter than the
        // screen was pushed down to the middle, which left a large empty band
        // above the Summary tab on the S9+.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            // Caps line length on a tablet or a landscape phone. Text set
            // across the full width of a wide screen is measurably harder to
            // track from line to line.
            constraints: const BoxConstraints(maxWidth: 520),
            child: _maybeRefreshable(
              SingleChildScrollView(
                // Always scrollable, so the pull gesture works even when the
                // content is shorter than the screen.
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
