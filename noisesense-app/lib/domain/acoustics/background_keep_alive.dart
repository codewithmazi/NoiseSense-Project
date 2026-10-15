/// Keeps measurement running while the app is not on screen.
///
/// On Android this is a foreground service, but the domain only needs to know
/// three things: ask for it, release it, and hear when the user ends it from
/// outside the app. Keeping the interface that small means the measurement
/// logic is tested with a fake, and a platform without the concept (or a
/// device that refuses it) degrades to foreground-only measurement rather
/// than failing.
abstract interface class BackgroundKeepAlive {
  /// Starts keeping the app alive. Returns false if the platform refused, in
  /// which case measuring continues only while the app is visible.
  Future<bool> begin();

  /// Stops keeping the app alive. Safe to call when not running.
  Future<void> end();

  /// Fires when the user stops measurement from outside the app, such as the
  /// Stop action on the Android notification.
  Stream<void> get stopRequests;
}

/// For platforms and tests where background measurement does not exist.
class NoBackgroundKeepAlive implements BackgroundKeepAlive {
  const NoBackgroundKeepAlive();

  @override
  Future<bool> begin() async => false;

  @override
  Future<void> end() async {}

  @override
  Stream<void> get stopRequests => const Stream.empty();
}
