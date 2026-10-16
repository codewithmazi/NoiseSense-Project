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
///
/// Holds the user's readings, their threshold and the cumulative dose derived
/// from them. Like [AuthViewModel] it depends only on domain interfaces, so it
/// is tested against a fake repository with no network involved.
class DashboardViewModel extends ChangeNotifier {
  /// Private field formals. Dart exposes these to callers without the leading
  /// underscore, so the call site reads `repository:` and `onSessionExpired:`
  /// while the fields themselves stay private to this class.
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

  /// Every new reading goes through this, never straight to the API, so a
  /// reading measured with no signal is kept and sent later rather than lost.
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
  ///
  /// Injected rather than reached for, because a view model must not drive
  /// navigation. The app wires this to [AuthViewModel.sessionExpired], which
  /// returns the user to sign-in with the reason given; a test wires it to a
  /// counter and asserts it fired.
  final Future<void> Function() _onSessionExpired;

  /// How much time each reading represents.
  ///
  /// Dose is a time-weighted quantity, so it cannot be computed without this.
  /// It is a parameter rather than a constant because the Week 3 capture
  /// engine owns the real analysis window, and this value must then come from
  /// it rather than being duplicated here and allowed to drift.
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

  /// Cumulative Lden-style exposure over [readings], or null when there are
  /// none and therefore no level to report.
  ExposureDose? get dose => _dose;

  bool get isLoading => _isLoading;

  /// True while a threshold change is being saved. Separate from [isLoading]
  /// so saving a setting does not blank the readings already on screen.
  bool get isSaving => _isSaving;

  String? get errorMessage => _errorMessage;

  /// True once a load has completed, successfully or not.
  ///
  /// Used to tell "nothing here yet" apart from "no readings". An empty list
  /// shown before the first load would wrongly tell a user with months of
  /// history that they have none.
  bool get hasLoadedOnce => _hasLoadedOnce;

  /// True when the user has readings but their most recent exposure is above
  /// the level they chose to be warned about.
  bool get isOverThreshold {
    final current = _dose;
    final threshold = _settings?.thresholdDbA;
    if (current == null || threshold == null) return false;
    return current.levelDb >= threshold;
  }

  /// Fetches readings and settings, then recomputes the dose.
  ///
  /// The two requests are issued concurrently with `Future.wait`, not one
  /// after the other. They are independent, and on a mobile connection where
  /// a round trip may include a Lambda cold start, serialising them would
  /// roughly double the time the user waits for a screen that cannot be drawn
  /// until both have arrived.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Readings still on the device are shown even if the service cannot be
    // reached, so an offline user still sees what they have measured.
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
  ///
  /// The returned settings are used rather than the requested value, so if the
  /// service ever clamps or normalises the number the UI shows what is
  /// actually in force rather than what was asked for.
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
  ///
  /// Returns true once the reading is safe on the device, which no longer
  /// depends on the network. It returns false only if local storage itself
  /// fails, the one case in which the reading really is lost.
  ///
  /// The reading is shown immediately rather than after a reload. DynamoDB
  /// reads are eventually consistent, so re-reading straight after a write
  /// can legitimately omit it; experiment M3 measures how often. Showing the
  /// local copy avoids a reading appearing, vanishing and reappearing.
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

  /// Combines [incoming] with what is already shown, one entry per timestamp,
  /// newest first.
  ///
  /// A union rather than a replacement, so a reading the user has already
  /// seen never disappears because an eventually consistent read briefly
  /// omitted it. Timestamps are the identity because the backend uses them
  /// as the key too, so the same reading from two sources is one entry.
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
      // Pending readings stay in this user's outbox and are sent after they
      // sign back in.
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
      // The token was refused. No message is set: the user is about to be
      // taken to the sign-in screen, which explains itself.
      await _onSessionExpired();
      return;
    }
    _errorMessage = userMessageFor(error);
  }
}
