import '../app_config.dart';

/// Form checks run before a request is made.
///
/// These exist to save the user a pointless round trip and to put the
/// explanation next to the field that caused it (Nielsen, 1994: error
/// prevention, and help users recognise and recover from errors). They are
/// not a security boundary. Cognito re-checks everything, and
/// `CognitoRestApi` maps its rejections to messages of their own.
class Validators {
  const Validators._();

  /// Checks an email address loosely: something, an @, a dot-bearing domain.
  ///
  /// Deliberately not a full RFC 5322 implementation. The grammar permits
  /// quoted local parts, comments and bracketed address literals, so the
  /// published "complete" regular expressions are thousands of characters
  /// long and still reject valid addresses, which turns a validator into a
  /// barrier to entry. The authoritative test of an address is whether the
  /// confirmation email arrives, and the app already depends on that. So this
  /// catches typing accidents and defers the real judgement to the mail
  /// system.
  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter your email address.';
    final at = text.indexOf('@');
    final hasLocalPart = at > 0;
    final domain = at >= 0 ? text.substring(at + 1) : '';
    final hasDomain =
        domain.contains('.') &&
        !domain.startsWith('.') &&
        !domain.endsWith('.');
    if (!hasLocalPart || !hasDomain || text.contains(' ')) {
      return 'That does not look like an email address.';
    }
    return null;
  }

  /// Checks a new password against the deployed user pool's policy.
  ///
  /// Every unmet rule is listed in one message. Revealing them one at a time,
  /// as a user fixes each in turn, is a well-known way to make a sign-up form
  /// feel adversarial.
  ///
  /// The rules mirror the `PasswordPolicy` in the SAM template: at least
  /// eight characters, with an upper-case letter, a lower-case letter and a
  /// digit. Symbols are allowed but not required.
  static String? newPassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Choose a password.';

    final unmet = <String>[
      if (text.length < AppConfig.passwordMinLength)
        'at least ${AppConfig.passwordMinLength} characters',
      if (!text.contains(RegExp('[A-Z]'))) 'a capital letter',
      if (!text.contains(RegExp('[a-z]'))) 'a lower-case letter',
      if (!text.contains(RegExp('[0-9]'))) 'a number',
    ];
    if (unmet.isEmpty) return null;
    return 'Your password needs ${_list(unmet)}.';
  }

  /// Checks a password being used to sign in.
  ///
  /// Only emptiness is checked. Applying the new-password rules here would be
  /// a mistake: an account created before a policy change may hold a password
  /// that no longer satisfies it, and refusing to even attempt sign-in would
  /// lock that user out of their own data over a client-side rule.
  static String? existingPassword(String? value) =>
      (value ?? '').isEmpty ? 'Enter your password.' : null;

  /// Checks a Cognito confirmation code: six digits.
  static String? confirmationCode(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter the code from your email.';
    if (!RegExp(r'^\d{6}$').hasMatch(text)) {
      return 'The code is six digits.';
    }
    return null;
  }

  /// Joins requirements as prose: "a, b and c".
  static String _list(List<String> items) => switch (items.length) {
    1 => items.single,
    2 => '${items.first} and ${items.last}',
    _ => '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}',
  };
}
