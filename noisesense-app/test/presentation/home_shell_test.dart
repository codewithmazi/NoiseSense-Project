import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/acoustics/pcm_source.dart';
import 'package:noise_sense/domain/models/exposure_settings.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/domain/repositories/noise_repository.dart';
import 'package:noise_sense/domain/services/sync_engine.dart';
import 'package:noise_sense/presentation/screens/home_shell.dart';
import 'package:noise_sense/presentation/theme/app_theme.dart';
import 'package:noise_sense/presentation/view_models/dashboard_view_model.dart';
import 'package:noise_sense/presentation/view_models/measurement_view_model.dart';

import '../support/memory_outbox_store.dart';

class _Repo implements NoiseRepository {
  _Repo(this.readings);
  final List<NoiseReading> readings;

  @override
  Future<List<NoiseReading>> history() async => readings;
  @override
  Future<ExposureSettings> settings() async =>
      const ExposureSettings(thresholdDbA: 70, isDefault: true);
  @override
  Future<SubmitOutcome> submit(NoiseReading r) async => SubmitOutcome.stored;
  @override
  Future<ExposureSettings> updateThreshold(double v) async =>
      ExposureSettings(thresholdDbA: v, isDefault: false);
}

class _SilentMic implements PcmSource {
  @override
  int get sampleRate => 48000;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<Stream<Int16List>> start() async => const Stream.empty();
  @override
  Future<void> stop() async {}
}

/// The 13 readings from the S9+ test on 16 Oct, so the tabs render real data.
List<NoiseReading> _deviceDay() {
  const levels = [
    70.5, 62.6, 69.5, 70.3, 52.9, 66.8, 55.7, 58.9, 65.3, 55.9, 82.3, 54.0,
    45.5, //
  ];
  return [
    for (var i = levels.length - 1; i >= 0; i--)
      NoiseReading(
        timestamp: DateTime.utc(2026, 10, 16, 13, 50 + i),
        dbA: levels[i],
        laeq: levels[i],
      ),
  ];
}

void main() {
  late DashboardViewModel dashboard;
  late MeasurementViewModel measurement;

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    final repo = _Repo(_deviceDay());
    dashboard = DashboardViewModel(
      repository: repo,
      sync: SyncEngine(store: MemoryOutboxStore(), remote: repo),
      onSessionExpired: () async {},
    );
    measurement = MeasurementViewModel(
      source: _SilentMic(),
      onReading: (_) async => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: HomeShell(
            dashboard: dashboard,
            measurement: measurement,
            email: 'test@example.com',
            onSignOut: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() {
    measurement.dispose();
    dashboard.dispose();
  });

  testWidgets('four labelled tabs, as in the wireframes', (tester) async {
    await pump(tester);
    for (final label in ['Monitor', 'History', 'Summary', 'Settings']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('Monitor shows the dose as a share of the limit', (tester) async {
    await pump(tester);
    // The unrounded dose of these readings is 72.138 dB(A), which against a
    // 70 dB limit is 10^(0.2138) = 163.6%, shown as 164%. (A first version of
    // this test expected 162%, from the rounded 72.1: the error was in the
    // test's arithmetic, not the app's.)
    expect(find.textContaining('164% of your limit'), findsOneWidget);
    expect(find.text('Start monitoring'), findsOneWidget);
  });

  testWidgets('each tab shows its own screen', (tester) async {
    await pump(tester);
    final expected = {
      'History': 'Last 13 readings',
      'Summary': 'Loudest moment',
      'Settings': 'Background monitoring',
    };
    for (final MapEntry(key: tab, value: marker) in expected.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(tab),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(marker), findsOneWidget, reason: tab);
    }
  });

  testWidgets('Summary reports the loudest moment from the readings', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.text('82.3 dB(A)'), findsOneWidget);
  });

  testWidgets('Settings shows the signed-in account', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('test@example.com'), findsOneWidget);
  });

  testWidgets('no tab overflows at Android\u2019s largest text size '
      '(SC 1.4.4)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 2.625; // the S9+'s density
    addTearDown(tester.view.reset);
    await pump(tester, textScale: 2.0);
    for (final tab in ['History', 'Summary', 'Settings', 'Monitor']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(tab),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
