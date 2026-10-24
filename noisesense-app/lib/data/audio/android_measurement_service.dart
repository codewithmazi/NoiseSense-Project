import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/acoustics/background_keep_alive.dart';

/// BackgroundKeepAlive backed by the Kotlin foreground service, via a platform channel.
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
      // Requested first so the measuring notification can appear on Android 13+.
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
