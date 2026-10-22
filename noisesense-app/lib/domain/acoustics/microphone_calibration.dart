import 'dart:math' as math;

/// Where a calibration offset came from.
enum CalibrationSource {
  /// Assumed from the Android CDD nominal sensitivity.
  nominal,

  /// Measured against a reference on this device.
  measured,
}

/// Converts digital signal power into sound pressure level.
class MicrophoneCalibration {
  const MicrophoneCalibration({required this.offsetDb, required this.source});

  /// CDD reference SPL for a 1 kHz tone.
  static const double cddReferenceSplDb = 90;

  /// CDD reference RMS for 16-bit samples.
  static const double cddReferenceRms16 = 2500;

  /// Nominal calibration derived from the CDD reference point.
  static final MicrophoneCalibration androidCddNominal = MicrophoneCalibration(
    offsetDb: cddReferenceSplDb - 20 * _log10(cddReferenceRms16 / 32768),
    source: CalibrationSource.nominal,
  );

  /// Mean-square 16-bit quantisation noise floor for samples scaled to ±1.0.
  static const double quantisationFloorMeanSquare =
      1 / (32768.0 * 32768.0 * 12);

  /// Offset in dB added to dBFS to give dB SPL.
  final double offsetDb;

  final CalibrationSource source;

  /// Lowest reportable level, in dB.
  double get noiseFloorDb => levelDb(0);

  /// Converts mean-square power to dB SPL, clamped to the noise floor.
  double levelDb(double meanSquare) =>
      10 * _log10(math.max(meanSquare, quantisationFloorMeanSquare)) + offsetDb;

  static double _log10(double x) => math.log(x) / math.ln10;
}