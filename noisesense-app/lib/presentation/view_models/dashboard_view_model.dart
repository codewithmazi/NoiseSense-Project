import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/errors.dart';
import '../../domain/models/exposure_settings.dart';
import '../../domain/models/noise_reading.dart';
import '../../domain/repositories/noise_repository.dart';
import '../../domain/services/exposure_calculator.dart';
import '../../domain/services/sync_engine.dart';
import '../error_text.dart';

/// Presentation state for the exposure dashboard.
class DashboardViewModel extends ChangeNotifier {
  /// Private field formals.
  DashboardViewModel({
    required this._repository,
    required this._sync,
    required this._onSessionExpired,
    this._calculator = const ExposureCalculator(),
    this.measurementWindow = const Duration(minutes: 1),
  }) {
    _syncSubscription = _sync.statusChanges.listen(_onSyncStatus);
  }

  final NoiseRepository _repository;

  /// New readings always go through the outbox, never straight to the API.
  final SyncEngine _sync;
  late final StreamSubscription<SyncStatus> _syncSubscription;
  bool _expiryReported = false;

  /// Upload state, for the "waiting to upload" indicators.
  SyncStatus get syncStatus => _sync.status;

  /// Whether [reading] is held on the device and not yet on the service.
  bool isPending(NoiseReading reading) =>
      _sync.status.pendingTimestamps.contains(reading.timestamp);
  final ExposureCalculator _calculator;

  /// What the app does when the service rejects the stored token.
  final Future<void> Function() _onSessionExpired;

  /// How much time each reading represents.
  final Duration measurementWindow;

  List<NoiseReading> _readings = const [];
  ExposureSettings? _settings;
  ExposureDose? _dose;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _hasLoadedOnce = false;

  /// Readings newest first, as returned by the service.
  List<NoiseReading> get readings => _readings;

  ExposureSettings? get settings => _settings;

  /// Cumulative Lden-style exposure over [readings], or null if there are none.
  ExposureDose? get dose => _dose;

  bool get isLoading => _isLoading;

  /// True while a threshold change is being saved.
  bool get isSaving => _isSaving;

  String? get errorMessage => _errorMessage;

  /// True once a load has completed, successfully or not.
  bool get hasLoadedOnce => _hasLoadedOnce;

  /// True when the latest exposure is above the user's alert level.
  bool get isOverThreshold {
    final current = _dose;
    final threshold = _settings?.thresholdDbA;
    if (current == null || threshold == null) return false;
    return current.levelDb >= threshold;
  }

  /// Fetches readings and settings, then recomputes the dose.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Readings still on the device are shown even if the service cannot be reached.
    _mergeReadings(await _sync.unsyncedReadings());
    _recomputeDose();

    try {
      final results = await Future.wait([
        _repository.history(),
        _repository.settings(),
      ]);
      _mergeReadings(results[0] as List<NoiseReading>);
      _settings = results[1] as ExposureSettings;
      _recomputeDose();
      // A good moment to retry: the service has just answered.
      unawaited(_sync.flush());
    } on NoiseSenseException catch (error) {
      await _handle(error);
    } finally {
      _isLoading = false;
      _hasLoadedOnce = true;
      notifyListeners();
    }
  }

  /// Saves a new alert threshold and adopts whatever the service confirms.
  Future<bool> updateThreshold(double thresholdDbA) async {
    if (_isSaving) return false;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    var saved = false;
    try {
      _settings = await _repository.updateThreshold(thresholdDbA);
      saved = true;
    } on NoiseSenseException catch (error) {
      await _handle(error);
    } finally {
      _isSaving = false;
      notifyListeners();
    }
    return saved;
  }

  /// Keeps a new reading and shows it at once; uploading happens behind it.
  Future<bool> submitReading(NoiseReading reading) async {
    try {
      await _sync.enqueue(reading);
    } on Exception {
      _errorMessage =
          'A reading could not be saved on this phone. Check it has free '
          'storage space.';
      notifyListeners();
      return false;
    }
    _mergeReadings([reading]);
    _recomputeDose();
    notifyListeners();
    return true;
  }

  /// Retries uploads now, for example when the app returns to the screen.
  Future<void> syncNow() => _sync.flush();

  /// Combines [incoming] with what is already shown, one entry per timestamp, newest first.
  void _mergeReadings(List<NoiseReading> incoming) {
    final byTime = {for (final r in _readings) r.timestamp: r};
    for (final r in incoming) {
      byTime.putIfAbsent(r.timestamp, () => r);
    }
    _readings = byTime.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void _onSyncStatus(SyncStatus status) {
    if (status.needsSignIn && !_expiryReported) {
      // Pending readings stay in this user's outbox and are sent after they sign back in.
      _expiryReported = true;
      unawaited(_onSessionExpired());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_syncSubscription.cancel());
    unawaited(_sync.dispose());
    super.dispose();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  void _recomputeDose() {
    _dose = _calculator.ldenStyle(_readings, window: measurementWindow);
  }

  /// Decides whether a failure is the user's problem or the session's.
  Future<void> _handle(NoiseSenseException error) async {
    if (error is UnauthorisedException) {
      // The token was refused.
      await _onSessionExpired();
      return;
    }
    _errorMessage = userMessageFor(error);
  }
}
