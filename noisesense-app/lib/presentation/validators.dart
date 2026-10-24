import '../app_config.dart';

/// Form checks run before a request is made.
class Validators {
  const Validators._();

  /// Checks an email address loosely: something, an @, a dot-bearing domain.
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
