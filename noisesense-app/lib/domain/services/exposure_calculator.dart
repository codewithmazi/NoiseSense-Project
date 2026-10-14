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

  /// Total measured time. The level only describes the time actually
  /// measured, so the UI must show this alongside it.
  final Duration coveredDuration;

  /// Number of readings the level was computed from.
  final int readingCount;
}

int _deviceLocalHour(DateTime utc) => utc.toLocal().hour;

/// Turns individual readings into cumulative exposure (603: FR-04).
///
/// This replaces the 602 design, which alerted on any single reading above a
/// fixed level. A one-second door slam and eight hours of night-time traffic
/// are not equivalent risks, and only an energy-based dose tells them apart.
class ExposureCalculator {
  /// [localHour] converts a UTC timestamp to a local clock hour. It defaults
  /// to the device's time zone, and is injectable so tests give the same
  /// answer whether they run in UTC (CI) or British Summer Time.
  const ExposureCalculator({this.localHour = _deviceLocalHour});

  final int Function(DateTime utc) localHour;

  /// Energy (logarithmic) average of levels in dB.
  ///
  /// Decibels are logarithmic, so they cannot be averaged arithmetically:
  /// 60 dB and 70 dB average to about 67.4 dB, not 65 dB. Loud periods
  /// dominate the result, which is the physically correct behaviour.
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

  /// Lden-style cumulative level for readings that each cover [window].
  ///
  /// Each reading's level is penalised for its period, converted to energy,
  /// averaged over the measured time, and converted back to decibels. It
  /// uses LAeq where present because that is already an energy average over
  /// the window, and falls back to dB(A) otherwise.
  ///
  /// Formal Lden assumes a complete 24-hour record. A phone almost never
  /// provides one, so this averages over the time actually measured. With a
  /// complete, evenly sampled day the result is identical to formal Lden; a
  /// unit test verifies that equivalence. With partial coverage it is an
  /// estimate, which is why [ExposureDose.coveredDuration] is reported.
  ///
  /// Returns null when there are no readings, since no level is defined.
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

  static double _toDb(double energy) => 10 * math.log(energy) / math.ln10;
}
