import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/acoustics/background_keep_alive.dart';

/// [BackgroundKeepAlive] backed by `MeasurementService.kt`, a foreground
/// service, through a platform channel.
///
/// Written directly rather than with a background-execution plugin. The
/// plugins in that space mostly run Dart in a second isolate, which would mean
/// splitting the measurement code across two isolates and passing levels
/// between them. Here the service only changes the process's priority and the
/// capture stays where it is, so about forty lines of Kotlin replace a
/// dependency and an architectural split.
class AndroidMeasurementService implements BackgroundKeepAlive {
  AndroidMeasurementService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopRequested') _stops.add(null);
    });
  }

  static const channelName = 'com.noisesense/measurement_service';

  final MethodChannel _channel;
  final StreamController<void> _stops = StreamController<void>.broadcast();

  @override
  Future<bool> begin() async {
    try {
      // Asked for before the service starts, so the "measuring" notification
      // can appear on Android 13+. A refusal is not fatal: the service and
      // measurement still run, the user just cannot see the notification.
      await _channel.invokeMethod<void>('requestNotificationPermission');
      return await _channel.invokeMethod<bool>('begin') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Not on Android, or running in a test without the native side.
      return false;
    }
  }

  @override
  Future<void> end() async {
    try {
      await _channel.invokeMethod<void>('end');
    } on PlatformException {
      // Nothing to release.
    } on MissingPluginException {
      // Not on Android.
    }
  }

  @override
  Stream<void> get stopRequests => _stops.stream;
}
