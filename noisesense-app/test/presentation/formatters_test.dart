import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/presentation/formatters.dart';

void main() {
  group('levels', () {
    test('are shown to one decimal place and no further', () {
      // Not fussiness. A phone microphone is uncalibrated, and Kardous and
      // Shaw (2014) measured errors of several decibels across consumer
      // devices, so printing 67.4382 dB(A) would claim a precision the
      // instrument does not have.
      expect(Formatters.level(67.4382), '67.4 dB(A)');
      expect(Formatters.level(60), '60.0 dB(A)');
    });

    test('a threshold is shown in whole decibels, matching the slider', () {
      // The slider moves in 1 dB steps, so showing a decimal would imply a
      // value the control cannot select.
      expect(Formatters.threshold(70.0), '70 dB(A)');
      expect(Formatters.threshold(69.6), '70 dB(A)');
    });
  });

  group('durations', () {
    test('use the largest sensible unit', () {
      expect(Formatters.duration(const Duration(seconds: 45)), '45 s');
      expect(Formatters.duration(const Duration(minutes: 45)), '45 min');
      expect(Formatters.duration(const Duration(hours: 3)), '3 h');
      expect(
        Formatters.duration(const Duration(hours: 3, minutes: 20)),
        '3 h 20 min',
      );
    });

    test('a whole number of hours omits the minutes', () {
      // "2 h 0 min" is noise.
      expect(Formatters.duration(const Duration(hours: 2)), '2 h');
    });
  });

  group('timestamps', () {
    test('are converted to local time', () {
      // Readings are stored in UTC. A user in British Summer Time shown
      // "13:32" for a reading they took at 14:32 would reasonably conclude
      // the app is broken.
      final utc = DateTime.utc(2026, 10, 11, 13, 32);
      final expected = utc.toLocal();
      final formatted = Formatters.timestamp(utc, now: utc);
      expect(
        formatted,
        '${expected.hour.toString().padLeft(2, '0')}:'
        '${expected.minute.toString().padLeft(2, '0')}',
      );
    });

    test('today shows the time only', () {
      final utc = DateTime.utc(2026, 10, 11, 9, 5);
      expect(Formatters.timestamp(utc, now: utc), hasLength(5));
    });

    test('an earlier day includes the date', () {
      final reading = DateTime.utc(2026, 10, 9, 14, 32);
      final now = DateTime.utc(2026, 10, 11, 14, 32);
      // The date is included, so a list spanning several days is readable.
      expect(Formatters.timestamp(reading, now: now), contains('Oct'));
    });

    test('hours and minutes are zero padded', () {
      final utc = DateTime.utc(2026, 10, 11, 1, 5);
      final local = utc.toLocal();
      final formatted = Formatters.timestamp(utc, now: utc);
      expect(formatted.split(':')[1], local.minute.toString().padLeft(2, '0'));
      expect(formatted, hasLength(5));
    });
  });

  group('classifier output', () {
    test('a label is made readable', () {
      expect(Formatters.classLabel('road_traffic'), 'Road traffic');
      expect(Formatters.classLabel('speech'), 'Speech');
    });

    test('an unrecognised label is still shown rather than hidden', () {
      // A newer model version emitting a label this build has never seen
      // should degrade to showing it, not to showing nothing.
      expect(
        Formatters.classLabel('aircraft_overflight'),
        'Aircraft overflight',
      );
    });

    test('confidence is a whole percentage', () {
      expect(Formatters.confidence(0.82), '82%');
      expect(Formatters.confidence(1), '100%');
      expect(Formatters.confidence(0.005), '1%');
    });
  });
}
