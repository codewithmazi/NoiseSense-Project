import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Severity of a message shown to the user.
enum MessageTone { error, info }

/// The app's single banner for errors and confirmations.
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
          // Edge colour and icon give two non-colour cues to severity.
          border: Border(left: BorderSide(color: colour, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: colour,
              size: 22,
              // The icon duplicates what the text already says.
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
