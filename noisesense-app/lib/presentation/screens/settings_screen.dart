import 'package:flutter/material.dart';

import '../formatters.dart';
import '../theme/app_theme.dart';
import '../view_models/dashboard_view_model.dart';
import '../view_models/measurement_view_model.dart';
import '../widgets/screen_shell.dart';
import '../widgets/section_label.dart';
import '../widgets/sync_status_view.dart';
import '../widgets/threshold_card.dart';

/// Tab 4, "Settings", after the wireframe.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.dashboard,
    required this.measurement,
    required this.email,
    required this.onSignOut,
  });

  final DashboardViewModel dashboard;
  final MeasurementViewModel measurement;
  final String? email;
  final Future<void> Function() onSignOut;

  Future<void> _confirmSignOut(BuildContext context) async {
    final pending = dashboard.syncStatus.pendingCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: const Text('Sign out?'),
        content: Text(
          pending == 0
              ? 'Your readings stay in your account. You will need to sign in '
                    'again to see them.'
              // Said explicitly, because the outbox is per user.
              : '$pending ${pending == 1 ? 'reading has' : 'readings have'} '
                    'not uploaded yet. They stay on this phone and upload '
                    'when you sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([dashboard, measurement]),
      builder: (context, _) {
        final status = dashboard.syncStatus;
        final last = status.lastSyncedAt;
        return ScreenShell(
          title: 'Settings',
          children: [
            const SectionLabel('Alert threshold'),
            ThresholdCard(
              settings: dashboard.settings,
              isSaving: dashboard.isSaving,
              onChanged: dashboard.updateThreshold,
            ),
            const SizedBox(height: AppTheme.spaceXs),
            // Shown as guidance next to the control, not imposed as the default.
            const Text(
              'For comparison, WHO suggests 53 dB Lden for road traffic noise.',
              style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 13),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Measuring'),
            Card(
              child: SwitchListTile(
                value: measurement.backgroundEnabled,
                onChanged: measurement.setBackgroundEnabled,
                title: const Text(
                  'Background monitoring',
                  style: TextStyle(color: AppTheme.onSurface, fontSize: 16),
                ),
                subtitle: const Text(
                  'Keep measuring with the screen off. A notification shows '
                  'while it runs.',
                  style: TextStyle(
                    color: AppTheme.onSurfaceMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Card(
              child: SwitchListTile(
                value: measurement.classificationEnabled,
                onChanged: measurement.setClassificationEnabled,
                title: const Text(
                  'Classify noise source',
                  style: TextStyle(color: AppTheme.onSurface, fontSize: 16),
                ),
                subtitle: const Text(
                  'Label each minute as traffic, speech, construction or '
                  'other, on this phone. Uses more battery.',
                  style: TextStyle(
                    color: AppTheme.onSurfaceMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Sync'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        // Avoids showing 'Not synced' when nothing is waiting.
                        if (status.pendingCount == 0)
                          'Everything is uploaded'
                        else
                          '${status.pendingCount} waiting to upload',
                        if (last != null)
                          'last upload ${Formatters.timestamp(last.toUtc())}',
                      ].join(' · '),
                      style: const TextStyle(
                        color: AppTheme.onSurface,
                        fontSize: 15,
                      ),
                    ),
                    SyncLine(status: status),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            OutlinedButton(
              onPressed: status.isSyncing ? null : dashboard.syncNow,
              child: Text(status.isSyncing ? 'Syncing\u2026' : 'Sync now'),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            const SectionLabel('Account'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                child: Text(
                  email ?? 'Signed in',
                  style: const TextStyle(
                    color: AppTheme.onSurface,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            OutlinedButton(
              onPressed: () => _confirmSignOut(context),
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );
  }
}
