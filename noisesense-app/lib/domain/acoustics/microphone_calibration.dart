import 'dart:math' as math;

/// Where a calibration offset came from, so the UI never presents an assumed
/// figure as a measured one.
enum CalibrationSource {
  /// The Android CDD's nominal sensitivity, assumed rather than measured.
  nominal,

  /// Measured on this device against a reference (experiment M6).
  measured,
}

/// Converts digital signal power into sound pressure level.
///
/// A microphone produces numbers, not pascals. The offset that maps one to the
/// other depends on the microphone, its amplifier and the audio path, and is
/// different on every phone model. Without a measured figure, the best
/// available assumption is what Android itself asks manufacturers to provide.
///
/// The Android 10 Compatibility Definition (s. 5.4.6) says devices SHOULD set
/// input sensitivity so that a 1 kHz tone at 90 dB SPL yields an RMS of 2500
/// for 16-bit samples, which it also gives as -22.35 dBFS. The nominal offset is
/// therefore 90 - (-22.35) = 112.35 dB. That is a SHOULD, not a MUST, so on any
/// particular device it is an assumption until M6 measures the real value.
class MicrophoneCalibration {
  const MicrophoneCalibration({required this.offsetDb, required this.source});

  /// The CDD reference point: a 1 kHz tone at this level...
  static const double cddReferenceSplDb = 90;

  /// ...produces this RMS, in 16-bit sample units.
  static const double cddReferenceRms16 = 2500;

  /// The nominal calibration derived from the CDD reference point.
  static final MicrophoneCalibration androidCddNominal = MicrophoneCalibration(
    offsetDb: cddReferenceSplDb - 20 * _log10(cddReferenceRms16 / 32768),
    source: CalibrationSource.nominal,
  );

  /// Mean-square power of 16-bit quantisation noise, for samples scaled to
  /// +/-1.0: one least significant bit squared, over twelve.
  ///
  /// This is the floor of what a 16-bit recording can represent. Clamping to it
  /// gives digital silence a finite, physically meaningful level instead of
  /// negative infinity, which no downstream calculation could handle.
  static const double quantisationFloorMeanSquare =
      1 / (32768.0 * 32768.0 * 12);

  /// Decibels added to dBFS to give dB SPL.
  final double offsetDb;

  final CalibrationSource source;

  /// Lowest level this calibration can report, in dB.
  double get noiseFloorDb => levelDb(0);

  /// Converts the mean square of samples scaled to +/-1.0 into dB SPL.
  ///
  /// The dBFS reference is an RMS of 1.0, the convention the CDD's own
  /// -22.35 dBFS figure uses, so a full-scale sine reads -3.01 dBFS.
  double levelDb(double meanSquare) =>
      10 * _log10(math.max(meanSquare, quantisationFloorMeanSquare)) + offsetDb;

  static double _log10(double x) => math.log(x) / math.ln10;
}
