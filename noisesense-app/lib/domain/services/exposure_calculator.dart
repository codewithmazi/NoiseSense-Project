import 'dart:math' as math;

import '../models/noise_reading.dart';

/// The three Lden assessment periods, with their default boundaries and
/// penalties as set out in the EU Environmental Noise Directive (2002/49/EC,
/// Annex I). Evening and night levels are penalised because the same sound
/// does more harm when it disturbs rest and sleep.
enum ExposurePeriod {
  /// 07:00 to 19:00, no penalty.
  day(penaltyDb: 0),

  /// 19:00 to 23:00, +5 dB.
  evening(penaltyDb: 5),

  /// 23:00 to 07:00, +10 dB.
  night(penaltyDb: 10);

  const ExposurePeriod({required this.penaltyDb});

  /// Decibels added to levels measured in this period.
  final double penaltyDb;

  /// The period containing a given local clock hour (0 to 23).
  static ExposurePeriod forLocalHour(int hour) {
    if (hour < 0 || hour > 23) throw RangeError.range(hour, 0, 23, 'hour');
    if (hour >= 7 && hour < 19) return day;
    if (hour >= 19 && hour < 23) return evening;
    return night;
  }
}

/// A cumulative exposure figure for a set of readings.
class ExposureDose {
  const ExposureDose({
    required this.levelDb,
    required this.coveredDuration,
    required this.readingCount,
  });

  /// Time-weighted equivalent level with Lden penalties applied, in dB.
  final double levelDb;

  /// Total measured time, shown alongside the level.
  final Duration coveredDuration;

  /// Number of readings the level was computed from.
  final int readingCount;
}

int _deviceLocalHour(DateTime utc) => utc.toLocal().hour;

/// Turns individual readings into cumulative exposure
class ExposureCalculator {
  /// Converts UTC to local hour; injectable for testing.
  const ExposureCalculator({this.localHour = _deviceLocalHour});

  final int Function(DateTime utc) localHour;

  /// Energy (logarithmic) average of levels in dB.
  static double energyAverage(Iterable<double> levelsDb) {
    var energy = 0.0;
    var count = 0;
    for (final level in levelsDb) {
      energy += math.pow(10, level / 10).toDouble();
      count++;
    }
    if (count == 0) {
      throw ArgumentError.value(levelsDb, 'levelsDb', 'must not be empty');
    }
    return _toDb(energy / count);
  }

  /// Lden-style cumulative level for readings covering [window]. Returns null when there are no readings.
  ExposureDose? ldenStyle(
    Iterable<NoiseReading> readings, {
    required Duration window,
  }) {
    if (window <= Duration.zero) {
      throw ArgumentError.value(window, 'window', 'must be positive');
    }
    var energy = 0.0;
    var count = 0;
    for (final reading in readings) {
      final period = ExposurePeriod.forLocalHour(localHour(reading.timestamp));
      final level = (reading.laeq ?? reading.dbA) + period.penaltyDb;
      energy += math.pow(10, level / 10).toDouble();
      count++;
    }
    if (count == 0) return null;
    // Every reading covers the same window, so the time-weighted mean of the
    // energies reduces to their simple mean.
    return ExposureDose(
      levelDb: _toDb(energy / count),
      coveredDuration: window * count,
      readingCount: count,
    );
  }

  /// Dose as an equal-energy fraction of the limit.
  static double doseFraction(double levelDb, double limitDb) =>
      math.pow(10, (levelDb - limitDb) / 10).toDouble();

  static double _toDb(double energy) => 10 * math.log(energy) / math.ln10;
}
