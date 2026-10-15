import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/acoustics/background_keep_alive.dart';
import 'package:noise_sense/domain/acoustics/pcm_source.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/presentation/view_models/measurement_view_model.dart';

/// A microphone that plays whatever the test pushes into it.
class _FakeSource implements PcmSource {
  bool permission = true;
  bool failOnStart = false;
  int starts = 0;
  int stops = 0;
  StreamController<Int16List>? controller;

  @override
  int get sampleRate => 48000;

  @override
  Future<bool> ensurePermission() async => permission;

  @override
  Future<Stream<Int16List>> start() async {
    starts++;
    if (failOnStart) throw Exception('mic busy');
    controller = StreamController<Int16List>();
    return controller!.stream;
  }

  void Function()? onStop;

  @override
  Future<void> stop() async {
    stops++;
    onStop?.call();
    await controller?.close();
    controller = null;
  }

  /// Pushes [seconds] of a 1 kHz tone at the CDD reference RMS (90 dB).
  Future<void> play(int seconds) async {
    const rms = 2500.0;
    for (var s = 0; s < seconds; s++) {
      controller!.add(
        Int16List.fromList([
          for (var i = 0; i < sampleRate; i++)
            (rms * math.sqrt2 * math.sin(2 * math.pi * 1000 * i / sampleRate))
                .round(),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  late _FakeSource source;
  late List<NoiseReading> received;
  late bool uploadSucceeds;
  late MeasurementViewModel vm;

  setUp(() {
    source = _FakeSource();
    received = [];
    uploadSucceeds = true;
    vm = MeasurementViewModel(
      source: source,
      onReading: (r) async {
        received.add(r);
        return uploadSucceeds;
      },
      window: const Duration(seconds: 10),
      clock: () => DateTime.utc(2026, 10, 15, 9),
    );
  });

  tearDown(() => vm.dispose());

  test('a refused permission is its own state, with a way forward', () async {
    source.permission = false;
    await vm.start();
    expect(vm.status, MeasurementStatus.permissionDenied);
    expect(vm.errorMessage, contains('settings'));
    expect(source.starts, 0, reason: 'no capture without permission');
  });

  test('a microphone that fails to start is reported and released', () async {
    source.failOnStart = true;
    await vm.start();
    expect(vm.status, MeasurementStatus.failed);
    expect(source.stops, greaterThan(0));
  });

  test('live levels are shown while measuring', () async {
    await vm.start();
    expect(vm.isMeasuring, isTrue);
    await source.play(3);
    expect(vm.liveLevelDb, closeTo(90, 0.1));
    expect(vm.elapsedInWindow, const Duration(seconds: 3));
  });

  test(
    'a completed window becomes a reading, timed from its first sample',
    () async {
      await vm.start();
      await source.play(10);
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      final r = received.single;
      expect(r.timestamp, DateTime.utc(2026, 10, 15, 9));
      expect(r.laeq, closeTo(90.0, 0.1));
      expect(vm.windowsSent, 1);
    },
  );

  test('levels are rounded to one decimal before leaving the device', () async {
    await vm.start();
    await source.play(10);
    await Future<void>.delayed(Duration.zero);
    final laeq = received.single.laeq!;
    expect((laeq * 10).roundToDouble() / 10, laeq);
  });

  test('stopping part-way through a window sends nothing', () async {
    // A reading must describe the whole window it claims to. A 4-second
    // fragment reported as a 10-second window would distort the dose.
    await vm.start();
    await source.play(4);
    await vm.stop();
    expect(received, isEmpty);
    expect(vm.status, MeasurementStatus.idle);
    expect(source.stops, greaterThan(0));
  });

  test('going to the background stops measuring', () async {
    // Android gives a backgrounded app silence, which would be recorded as
    // falsely quiet windows.
    await vm.start();
    await vm.onForegroundChanged(inForeground: false);
    expect(vm.isMeasuring, isFalse);
  });

  test('a failed upload is counted rather than silently lost', () async {
    uploadSucceeds = false;
    await vm.start();
    await source.play(10);
    await Future<void>.delayed(Duration.zero);
    expect(vm.windowsFailed, 1);
    expect(vm.windowsSent, 0);
  });

  test(
    'the stream ending unexpectedly is a failure, not a silent stop',
    () async {
      await vm.start();
      await source.controller!.close();
      await Future<void>.delayed(Duration.zero);
      expect(vm.status, MeasurementStatus.failed);
    },
  );

  test('starting twice does not open the microphone twice', () async {
    await Future.wait([vm.start(), vm.start()]);
    expect(source.starts, 1);
  });

  group('background measurement', () {
    late _FakeKeepAlive keepAlive;
    late MeasurementViewModel bg;

    setUp(() {
      keepAlive = _FakeKeepAlive();
      bg = MeasurementViewModel(
        source: source,
        onReading: (r) async {
          received.add(r);
          return true;
        },
        keepAlive: keepAlive,
        window: const Duration(seconds: 10),
        clock: () => DateTime.utc(2026, 10, 15, 9),
      );
    });

    tearDown(() => bg.dispose());

    test('with the service granted, hiding the app does not stop it', () async {
      await bg.start();
      expect(bg.measuresInBackground, isTrue);
      await bg.onForegroundChanged(inForeground: false);
      expect(bg.isMeasuring, isTrue);
      // And readings still arrive while hidden.
      await source.play(10);
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
    });

    test('with the service refused, hiding the app stops it', () async {
      // The negative case. Carrying on without the service would record
      // the silence Android hands a background app as falsely quiet minutes.
      keepAlive.grant = false;
      await bg.start();
      expect(bg.measuresInBackground, isFalse);
      await bg.onForegroundChanged(inForeground: false);
      expect(bg.isMeasuring, isFalse);
    });

    test('the service is requested only after microphone permission', () async {
      // Android 14 throws if a microphone service starts without it.
      source.permission = false;
      await bg.start();
      expect(keepAlive.begins, 0);
    });

    test('stopping releases the service, after the microphone', () async {
      await bg.start();
      await bg.stop();
      expect(keepAlive.ends, 1);
      expect(keepAlive.order, ['begin', 'micStop', 'end']);
    });

    test('a microphone failure also releases the service', () async {
      // Otherwise the notification would keep claiming to measure.
      source.failOnStart = true;
      await bg.start();
      expect(bg.status, MeasurementStatus.failed);
      expect(keepAlive.ends, 1);
    });

    test('Stop on the notification stops measurement in the app', () async {
      await bg.start();
      keepAlive.requestStop();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(bg.isMeasuring, isFalse);
      expect(keepAlive.ends, 1);
    });

    test('the service is not ended twice', () async {
      await bg.start();
      await bg.stop();
      await bg.stop();
      expect(keepAlive.ends, 1);
    });

    setUp(() => source.onStop = () => keepAlive.order.add('micStop'));
  });
}

class _FakeKeepAlive implements BackgroundKeepAlive {
  bool grant = true;
  int begins = 0;
  int ends = 0;
  final order = <String>[];
  final _stops = StreamController<void>.broadcast();

  void requestStop() => _stops.add(null);

  @override
  Future<bool> begin() async {
    begins++;
    order.add('begin');
    return grant;
  }

  @override
  Future<void> end() async {
    ends++;
    order.add('end');
  }

  @override
  Stream<void> get stopRequests => _stops.stream;
}
