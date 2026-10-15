import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/data/audio/android_measurement_service.dart';

/// Tests the Dart half of the platform channel against a scripted native side.
/// The Kotlin half can only be verified on a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidMeasurementService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;

  void nativeSide(Object? Function(MethodCall call) handler) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return handler(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'begin asks for notification permission, then starts the service',
    () async {
      nativeSide((call) => call.method == 'begin' ? true : null);
      expect(await AndroidMeasurementService().begin(), isTrue);
      expect(calls, ['requestNotificationPermission', 'begin']);
    },
  );

  test('a native start failure becomes false, not an exception', () async {
    // Falls back to foreground-only measurement instead of crashing.
    nativeSide((call) {
      if (call.method == 'begin') {
        throw PlatformException(code: 'START_FAILED');
      }
      return null;
    });
    expect(await AndroidMeasurementService().begin(), isFalse);
  });

  test('no native side at all is also false', () async {
    // For example a non-Android build.
    messenger.setMockMethodCallHandler(channel, null);
    expect(await AndroidMeasurementService().begin(), isFalse);
  });

  test('end calls the native side', () async {
    nativeSide((_) => null);
    await AndroidMeasurementService().end();
    expect(calls, ['end']);
  });

  test('a stop from the notification reaches Dart listeners', () async {
    final service = AndroidMeasurementService();
    var stops = 0;
    service.stopRequests.listen((_) => stops++);

    await messenger.handlePlatformMessage(
      AndroidMeasurementService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('stopRequested'),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(stops, 1);
  });
}
