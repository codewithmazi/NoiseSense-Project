/// One aggregated measurement window; contains no raw audio.
class NoiseReading {
  /// Creates a reading; normalises [timestamp] to whole UTC seconds.
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

  /// Window start time, UTC, whole seconds.
  final DateTime timestamp;

  /// A-weighted level for the window, in dB(A).
  final double dbA;

  /// Energy-based equivalent continuous level, when available.
  final double? laeq;

  /// Dominant predicted noise source.
  final String? classLabel;

  /// Classifier confidence for [classLabel], from 0 to 1.
  final double? confidence;

  static DateTime _wholeSecondUtc(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second);
  }

  /// Validates that a level is finite and within sane bounds.
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
