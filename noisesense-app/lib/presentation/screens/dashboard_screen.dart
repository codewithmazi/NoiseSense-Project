import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../view_models/dashboard_view_model.dart';
import '../view_models/measurement_view_model.dart';
import '../widgets/measurement_card.dart';
import '../widgets/exposure_summary_card.dart';
import '../widgets/message_banner.dart';
import '../widgets/reading_tile.dart';
import '../widgets/screen_shell.dart';
import '../widgets/threshold_card.dart';

/// The signed-in home screen: cumulative exposure, alert threshold, history.
///
/// Information is ordered by what the user came for. The dose answers "how
/// much noise have I been exposed to", which is the question the product
/// exists to answer, so it is first and largest. The threshold is the one
/// control that changes how the dose is interpreted, so it comes next.
/// History is the supporting detail and comes last.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.viewModel,
    required this.measurement,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final MeasurementViewModel measurement;
  final Future<void> Function() onSignOut;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Loaded here rather than in `build`, which runs again on every rebuild
    // and would re-request on each one.
    widget.viewModel.load();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: const Text('Sign out?'),
        content: const Text(
          'Your readings stay in your account. You will need to sign in again '
          'to see them.',
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
    // Confirmed because signing out is easy to trigger by accident from an
    // app bar icon and, until the Week 4 local store exists, it is the one
    // action that cannot be undone from inside the app (Nielsen, 1994: error
    // prevention).
    if (confirmed == true) await widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return ScreenShell(
          title: 'Your exposure',
          onRefresh: vm.load,
          actions: [
            IconButton(
              onPressed: vm.isLoading ? null : vm.load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
            IconButton(
              onPressed: _confirmSignOut,
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
            ),
          ],
          children: [
            if (vm.errorMessage != null) ...[
              MessageBanner(message: vm.errorMessage),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            // Shown only before the first load has finished. Afterwards a
            // refresh leaves the existing figures in place rather than
            // replacing the screen with a spinner, so the user is not made to
            // watch content they already had disappear.
            if (vm.isLoading && !vm.hasLoadedOnce)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppTheme.spaceXl),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              ExposureSummaryCard(
                dose: vm.dose,
                thresholdDbA: vm.settings?.thresholdDbA,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              MeasurementCard(viewModel: widget.measurement),
              const SizedBox(height: AppTheme.spaceMd),
              ThresholdCard(
                settings: vm.settings,
                isSaving: vm.isSaving,
                onChanged: vm.updateThreshold,
              ),
              const SizedBox(height: AppTheme.spaceLg),
              _HistorySection(viewModel: vm),
            ],
          ],
        );
      },
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final readings = viewModel.readings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          readings.isEmpty
              ? 'Recent readings'
              : 'Recent readings (${readings.length})',
          style: const TextStyle(
            color: AppTheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.spaceSm),
        if (readings.isEmpty)
          const Text(
            'Nothing recorded yet.',
            style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 15),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spaceMd,
                vertical: AppTheme.spaceSm,
              ),
              // A Column rather than a nested ListView. The whole page already
              // scrolls, and a scrollable inside a scrollable traps the
              // gesture and confuses the screen reader's reading order. The
              // back end caps `GET /history` at 100 items, so the cost of
              // building them all is bounded and small.
              child: Column(
                children: [
                  for (var i = 0; i < readings.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ReadingTile(
                      reading: readings[i],
                      thresholdDbA: viewModel.settings?.thresholdDbA,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
