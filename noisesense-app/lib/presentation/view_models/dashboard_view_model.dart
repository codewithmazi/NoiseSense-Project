import 'package:flutter/foundation.dart';

import '../../domain/errors.dart';
import '../../domain/models/exposure_settings.dart';
import '../../domain/models/noise_reading.dart';
import '../../domain/repositories/noise_repository.dart';
import '../../domain/services/exposure_calculator.dart';
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
    required this._onSessionExpired,
    this._calculator = const ExposureCalculator(),
    this.measurementWindow = const Duration(minutes: 1),
  });

  final NoiseRepository _repository;
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

    try {
      final results = await Future.wait([
        _repository.history(),
        _repository.settings(),
      ]);
      _readings = results[0] as List<NoiseReading>;
      _settings = results[1] as ExposureSettings;
      _recomputeDose();
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

  /// Sends one reading and folds it into the local view on success.
  ///
  /// A [SubmitOutcome.duplicate] is treated as success, because that is what
  /// it means: the service already holds this reading, so the user's data is
  /// safe. Reporting it as a failure would make the offline replay path look
  /// broken precisely when it is working (603: FR-06).
  ///
  /// The accepted reading is inserted locally rather than triggering a reload.
  /// DynamoDB reads are eventually consistent, so an immediate re-read can
  /// legitimately omit the write that just succeeded. Trusting the 201 instead
  /// avoids showing the user their own reading disappearing and reappearing.
  /// Experiment M3 measures how often that staleness actually occurs.
  Future<bool> submitReading(NoiseReading reading) async {
    try {
      final outcome = await _repository.submit(reading);
      if (outcome == SubmitOutcome.stored) {
        _readings = [reading, ..._readings];
        _recomputeDose();
        notifyListeners();
      }
      return true;
    } on NoiseSenseException catch (error) {
      await _handle(error);
      notifyListeners();
      return false;
    }
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
