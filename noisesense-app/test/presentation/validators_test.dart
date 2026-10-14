import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/presentation/validators.dart';

void main() {
  group('email', () {
    test('accepts ordinary addresses', () {
      for (final address in [
        'ron@example.com',
        'ron.bilski@coventry.ac.uk',
        'ron+noisesense@example.co.uk',
        'r@e.io',
      ]) {
        expect(Validators.email(address), isNull, reason: address);
      }
    });

    test('rejects what a user is likely to mistype', () {
      for (final address in [
        '',
        '   ',
        'ron',
        'ron@',
        '@example.com',
        'ron@example',
        'ron@.com',
        'ron@example.',
        'ron example@test.com',
      ]) {
        expect(Validators.email(address), isNotNull, reason: '"$address"');
      }
    });

    test('ignores surrounding whitespace', () {
      // Pasted addresses routinely arrive with a trailing space.
      expect(Validators.email('  ron@example.com  '), isNull);
    });

    test('does not reject a plus-addressed mailbox', () {
      // A real failure in many sign-up forms. Gmail and others use the plus
      // suffix for filtering, and rejecting it blocks valid addresses.
      expect(Validators.email('ron+tag@gmail.com'), isNull);
    });
  });

  group('new password', () {
    test('accepts a password meeting the pool policy', () {
      expect(Validators.newPassword('Passw0rdd'), isNull);
    });

    test('symbols are allowed but not required', () {
      // Mirrors `RequireSymbols: false` in the SAM template. Demanding one
      // here would reject passwords Cognito would have accepted.
      expect(Validators.newPassword('Passw0rd'), isNull);
      expect(Validators.newPassword('Passw0rd!'), isNull);
    });

    test('lists every unmet rule at once', () {
      // Revealing requirements one failure at a time makes a form feel
      // adversarial, so all of them are reported together.
      final message = Validators.newPassword('abc')!;
      expect(message, contains('8 characters'));
      expect(message, contains('capital letter'));
      expect(message, contains('number'));
    });

    test('names only the rule actually broken', () {
      final message = Validators.newPassword('passw0rdd')!;
      expect(message, contains('capital letter'));
      expect(message, isNot(contains('number')));
      expect(message, isNot(contains('8 characters')));
    });

    test('reads as prose, not as a list of fragments', () {
      expect(
        Validators.newPassword('aaaaaaaaa'),
        'Your password needs a capital letter and a number.',
      );
    });

    test('rejects an empty password with a distinct message', () {
      expect(Validators.newPassword(''), 'Choose a password.');
    });
  });

  group('existing password', () {
    test('only emptiness is checked', () {
      // Deliberate. An account created under an older policy may hold a
      // password that no longer satisfies the current rules, and refusing to
      // attempt sign-in would lock that user out of their own data over a
      // client-side check.
      expect(Validators.existingPassword('short'), isNull);
      expect(Validators.existingPassword('nocapitals1'), isNull);
      expect(Validators.existingPassword(''), isNotNull);
    });
  });

  group('confirmation code', () {
    test('accepts six digits', () {
      expect(Validators.confirmationCode('123456'), isNull);
    });

    test('accepts a pasted code with whitespace', () {
      expect(Validators.confirmationCode(' 123456 '), isNull);
    });

    test('rejects the wrong length or non-digits', () {
      for (final code in ['', '12345', '1234567', '12345a', 'abcdef']) {
        expect(Validators.confirmationCode(code), isNotNull, reason: '"$code"');
      }
    });
  });
}
