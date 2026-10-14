/// Number, time and duration formatting for display.
///
/// Written by hand rather than with `intl`, because the app needs about six
/// formats and adding a localisation dependency to get them would not pay for
/// itself. The limitation is accepted openly: these produce British English
/// conventions only, so genuine internationalisation would mean replacing this
/// file with `intl` rather than extending it.
class Formatters {
  const Formatters._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// A sound level with its unit, to one decimal place: `67.4 dB(A)`.
  ///
  /// One decimal, no more. A phone microphone is uncalibrated, and Kardous and
  /// Shaw (2014) found errors of several decibels across consumer devices, so
  /// quoting two or three decimals would imply a precision the instrument does
  /// not have. Displaying a number to more digits than it is accurate to is a
  /// quiet form of overclaiming.
  static String level(double dbA) => '${dbA.toStringAsFixed(1)} dB(A)';

  /// A level with no unit, for use beside a label that already carries one.
  static String levelValue(double dbA) => dbA.toStringAsFixed(1);

  /// A threshold, which users set in whole decibels: `70 dB(A)`.
  static String threshold(double dbA) => '${dbA.round()} dB(A)';

  /// Elapsed time in the largest sensible unit: `45 min`, `3 h 20 min`.
  static String duration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }

  /// A timestamp in the device's time zone: `14:32` today, `11 Oct, 14:32`
  /// otherwise.
  ///
  /// Converted to local time because readings are stored in UTC, and a user in
  /// British Summer Time reading "13:32" for something they measured at 14:32
  /// would reasonably conclude the app is broken.
  static String timestamp(DateTime utc, {DateTime? now}) {
    final local = utc.toLocal();
    final today = (now ?? DateTime.now()).toLocal();
    final time = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    final isToday =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    if (isToday) return time;
    return '${local.day} ${_months[local.month - 1]}, $time';
  }

  /// Turns a classifier label into something readable: `road_traffic` becomes
  /// `Road traffic`. Falls back to the raw value, so an unrecognised label
  /// from a newer model version is still shown rather than hidden.
  static String classLabel(String raw) {
    final words = raw.replaceAll('_', ' ').trim();
    if (words.isEmpty) return raw;
    return words[0].toUpperCase() + words.substring(1).toLowerCase();
  }

  /// A confidence as a whole percentage: `0.82` becomes `82%`.
  static String confidence(double value) => '${(value * 100).round()}%';

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
