import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/noise_reading.dart';
import '../theme/app_theme.dart';
import '../view_models/dashboard_view_model.dart';
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
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
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
              ThresholdCard(
                settings: vm.settings,
                isSaving: vm.isSaving,
                onChanged: vm.updateThreshold,
              ),
              const SizedBox(height: AppTheme.spaceLg),
              _HistorySection(viewModel: vm),
              const SizedBox(height: AppTheme.spaceLg),
              _MeasurementPlaceholder(viewModel: vm),
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

/// Temporary control that submits one synthetic reading.
///
/// This is scaffolding, not a feature, and it is labelled as such on screen so
/// a demonstration cannot mistake it for one. It exists because the write path
/// (sign-in, token, `POST /metrics`, idempotency, history) is complete before
/// the Week 3 measurement engine is, and being able to exercise it end to end
/// now is what lets the two be debugged separately rather than together.
///
/// It is also useful afterwards: it is the simplest way to put known values
/// into the system when checking the dose arithmetic against the unit tests'
/// golden figures on a real device.
///
/// It must be removed, or hidden behind a debug flag, before the final build.
class _MeasurementPlaceholder extends StatelessWidget {
  const _MeasurementPlaceholder({required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.construction,
                  size: 18,
                  color: AppTheme.onSurfaceMuted,
                  semanticLabel: '',
                ),
                SizedBox(width: AppTheme.spaceSm),
                Text(
                  'Development tool',
                  style: TextStyle(
                    color: AppTheme.onSurfaceMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceXs),
            const Text(
              'Sends one synthetic reading, so the upload path can be tested '
              'before the microphone engine is built.',
              style: TextStyle(
                color: AppTheme.onSurfaceMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _submitSynthetic(context),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add a synthetic reading'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitSynthetic(BuildContext context) async {
    // A plausible urban level, varied so repeated taps do not all land in the
    // same second and collide on the backend's second-precision sort key.
    final random = math.Random();
    final level = 55 + random.nextDouble() * 30;
    final reading = NoiseReading(
      timestamp: DateTime.now().toUtc(),
      dbA: double.parse(level.toStringAsFixed(1)),
      laeq: double.parse((level - 1.5).toStringAsFixed(1)),
      classLabel: 'road_traffic',
      // A deliberately unimpressive confidence: this is a fabricated label,
      // and a synthetic reading should not look more certain than a real one.
      confidence: 0.5,
    );

    final messenger = ScaffoldMessenger.of(context);
    final sent = await viewModel.submitReading(reading);
    if (!sent) return; // The view model has already set an error message.
    messenger.showSnackBar(const SnackBar(content: Text('Reading sent.')));
  }
}
