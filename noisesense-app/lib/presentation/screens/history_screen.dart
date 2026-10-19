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
///
/// The wireframe's Day/Week toggle is not built. The service returns at most
/// the latest 100 readings, which is under two hours at one a minute, so a
/// "Week" view would be drawn from data the app does not have. The chart is
/// labelled with the span it actually covers instead.
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
                  // A Column rather than a nested ListView: the page already
                  // scrolls, and a scrollable inside a scrollable traps the
                  // gesture and confuses the screen reader's reading order.
                  // The list is capped at 100 by the service, so building it
                  // all is cheap.
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
