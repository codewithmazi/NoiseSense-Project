import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Severity of a message shown to the user.
enum MessageTone { error, info }

/// The app's one way of telling the user something went wrong, or went right.
///
/// Having a single widget for this is the point. Every screen reports failure
/// in the same place, with the same shape and the same wording conventions, so
/// the user learns where to look once (Nielsen, 1994: consistency and
/// standards).
///
/// Three accessibility decisions are deliberate:
///
/// * An icon accompanies the colour. Colour alone must not be the only way
///   information is conveyed (WCAG 2.2 SC 1.4.1 Use of Colour), which matters
///   for the roughly 1 in 12 men with a colour vision deficiency, and in
///   bright sunlight where hue discrimination drops for everybody.
/// * The text is wrapped in a live region, so a screen reader announces a new
///   message instead of leaving a blind user to discover it by exploring
///   (SC 4.1.3 Status Messages).
/// * The banner occupies layout space only when there is something to say,
///   rather than being permanently present and empty.
class MessageBanner extends StatelessWidget {
  const MessageBanner({
    super.key,
    required this.message,
    this.tone = MessageTone.error,
  });

  /// The message, or null to show nothing.
  final String? message;

  final MessageTone tone;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final isError = tone == MessageTone.error;
    final colour = isError ? AppTheme.error : AppTheme.primary;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: AppTheme.radius,
          // A 2px edge in the tone colour, plus the icon, gives two
          // non-colour cues to severity.
          border: Border(left: BorderSide(color: colour, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: colour,
              size: 22,
              // The icon duplicates what the text already says, so naming it
              // for a screen reader would only make it repeat itself.
              semanticLabel: '',
            ),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppTheme.onSurface,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
