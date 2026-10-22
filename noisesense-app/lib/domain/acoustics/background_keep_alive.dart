/// Keeps measurement running while the app is not on screen.
abstract interface class BackgroundKeepAlive {
  /// Starts background measurement; returns false if unsupported or refused.
  Future<bool> begin();

  /// Stops background measurement; safe to call when not running.
  Future<void> end();

  /// Fires when the user stops measurement outside the app.
  Stream<void> get stopRequests;
}

/// Fallback for platforms or tests without background measurement.
class NoBackgroundKeepAlive implements BackgroundKeepAlive {
  const NoBackgroundKeepAlive();

  @override
  Future<bool> begin() async => false;

  @override
  Future<void> end() async {}

  @override
  Stream<void> get stopRequests => const Stream.empty();
}