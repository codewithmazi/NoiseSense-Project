import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../view_models/dashboard_view_model.dart';
import '../widgets/level_chart.dart';
import '../widgets/message_banner.dart';
import '../widgets/reading_tile.dart';
import '../widgets/screen_shell.dart';
import '../widgets/section_label.dart';
import '../widgets/sync_status_view.dart';

/// Tab 2, "History": a chart over the itemised readings, after the wireframe.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.dashboard});

  final DashboardViewModel dashboard;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dashboard,
      builder: (context, _) {
        final vm = dashboard;
        final readings = vm.readings;
        final limit = vm.settings?.thresholdDbA;
        return ScreenShell(
          title: 'History',
          onRefresh: vm.load,
          actions: [
            IconButton(
              onPressed: vm.isLoading ? null : vm.load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
          children: [
            if (vm.errorMessage != null) ...[
              MessageBanner(message: vm.errorMessage),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            if (vm.isLoading && !vm.hasLoadedOnce)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppTheme.spaceXl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (readings.isEmpty)
              const Text(
                'Nothing recorded yet.',
                style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 15),
              )
            else ...[
              SectionLabel('Last ${readings.length} readings'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceMd),
                  child: LevelChart(readings: readings, limitDb: limit),
                ),
              ),
              SyncLine(status: vm.syncStatus),
              const SizedBox(height: AppTheme.spaceMd),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceMd,
                    vertical: AppTheme.spaceSm,
                  ),
                  // A Column rather than a nested ListView.
                  child: Column(
                    children: [
                      for (var i = 0; i < readings.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ReadingTile(
                          reading: readings[i],
                          thresholdDbA: limit,
                          isPending: vm.isPending(readings[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
