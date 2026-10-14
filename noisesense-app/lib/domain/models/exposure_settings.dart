/// The user's exposure preferences (603: FR-05).
class ExposureSettings {
  const ExposureSettings({
    required this.thresholdDbA,
    required this.isDefault,
    this.updatedAt,
  });

  /// Lowest threshold a user may choose. Below this a phone would alert in
  /// ordinary quiet rooms, which would train the user to ignore alerts.
  static const double minThresholdDbA = 40;

  /// Highest threshold a user may choose. Above this an uncalibrated phone
  /// microphone is not a meaningful instrument (Kardous & Shaw, 2014).
  static const double maxThresholdDbA = 100;

  /// Level, in dB(A), above which the user wants to be alerted.
  final double thresholdDbA;

  /// True when the user has not chosen a value and the service default applies.
  /// The UI shows this, rather than presenting the fallback as a choice.
  final bool isDefault;

  /// When the user last changed the value, if ever.
  final DateTime? updatedAt;

  /// Returns a user-facing error message, or null when [value] is acceptable.
  ///
  /// This deliberately duplicates the backend's range check. The server stays
  /// authoritative; the copy exists so the user is told immediately, before a
  /// network round trip (Nielsen, 1994: error prevention). If the two ever
  /// drift apart, the server's 400 response is still handled correctly.
  static String? validateThreshold(double value) {
    if (value.isNaN || value < minThresholdDbA || value > maxThresholdDbA) {
      return 'Choose a level between ${minThresholdDbA.round()} and '
          '${maxThresholdDbA.round()} dB(A).';
    }
    return null;
  }
}
