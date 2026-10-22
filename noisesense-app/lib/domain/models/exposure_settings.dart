/// The user's exposure preferences (603: FR-05).
class ExposureSettings {
  const ExposureSettings({
    required this.thresholdDbA,
    required this.isDefault,
    this.updatedAt,
  });

  /// Minimum selectable alert threshold.
  static const double minThresholdDbA = 40;

  /// Maximum selectable alert threshold.
  static const double maxThresholdDbA = 100;

  /// Alert threshold in dB(A).
  final double thresholdDbA;

  /// True when the service default applies.
  final bool isDefault;

  /// When the user last changed the value.
  final DateTime? updatedAt;

  /// Returns a validation error, or null if [value] is acceptable.
  static String? validateThreshold(double value) {
    if (value.isNaN || value < minThresholdDbA || value > maxThresholdDbA) {
      return 'Choose a level between ${minThresholdDbA.round()} and '
          '${maxThresholdDbA.round()} dB(A).';
    }
    return null;
  }
}
