/// One aggregated measurement window, as produced on the device.
///
/// Raw audio never reaches this class. By the time a [NoiseReading] exists the
/// audio buffer has already been discarded, and only these numbers remain
/// (603: FR-03). This is the privacy guarantee expressed in the type system.
class NoiseReading {
  /// Creates a reading. Throws [ArgumentError] for values that cannot be real.
  ///
  /// [timestamp] is normalised to UTC and truncated to whole seconds. That
  /// truncation is deliberate: the backend stores readings under a sort key of
  /// `TS#` plus a second-precision timestamp, and uses that key to recognise a
  /// replayed submission as a duplicate (603: FR-06). Two readings in the same
  /// second would therefore collide, so the measurement window must be at
  /// least one second long.
  NoiseReading({
    required DateTime timestamp,
    required this.dbA,
    this.laeq,
    this.classLabel,
    this.confidence,
  }) : timestamp = _wholeSecondUtc(timestamp) {
    _requireLevel(dbA, 'dbA');
    final l = laeq;
    if (l != null) _requireLevel(l, 'laeq');
    final c = confidence;
    if (c != null && (c.isNaN || c < 0 || c > 1)) {
      throw ArgumentError.value(c, 'confidence', 'must be between 0 and 1');
    }
  }

  /// Start of the measurement window, UTC, whole seconds.
  final DateTime timestamp;

  /// A-weighted level reported for the window, in dB(A).
  final double dbA;

  /// A-weighted equivalent continuous level over the window, in dB(A), when
  /// available. Preferred for dose calculation because it is energy-based.
  final double? laeq;

  /// Dominant source predicted by the on-device classifier (603: FR-09).
  final String? classLabel;

  /// Classifier confidence for [classLabel], from 0 to 1.
  final double? confidence;

  static DateTime _wholeSecondUtc(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second);
  }

  /// Sanity bounds only, to catch programming errors and corrupt data. They
  /// are not a claim about what a phone microphone can measure accurately.
  static void _requireLevel(double value, String name) {
    if (!value.isFinite || value < 0 || value > 200) {
      throw ArgumentError.value(
        value,
        name,
        'must be a level between 0 and 200 dB',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NoiseReading &&
      other.timestamp == timestamp &&
      other.dbA == dbA &&
      other.laeq == laeq &&
      other.classLabel == classLabel &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(timestamp, dbA, laeq, classLabel, confidence);

  @override
  String toString() =>
      'NoiseReading(${timestamp.toIso8601String()}, $dbA dB(A)'
      '${classLabel == null ? '' : ', $classLabel'})';
}
