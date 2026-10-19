import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/errors.dart';
import 'package:noise_sense/domain/repositories/auth_repository.dart';
import 'package:noise_sense/presentation/view_models/auth_view_model.dart';

/// A scripted [AuthRepository].
///
/// Hand-written rather than generated with a mocking package. It is a handful
/// of methods, and writing it means the test suite has no code-generation step
/// to run in CI. It also records calls, so a test can assert what the view
/// model asked for and not only what it ended up showing.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository();

  /// Thrown by whichever method is called next, then cleared.
  NoiseSenseException? nextError;

  bool sessionValid = false;
  final List<String> calls = [];
  String? lastEmail;
  String? lastCode;

  void _maybeThrow(String call) {
    calls.add(call);
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    lastEmail = email;
    _maybeThrow('signUp');
  }

  @override
  Future<void> confirmSignUp({
    required String email,
    required String code,
  }) async {
    lastEmail = email;
    lastCode = code;
    _maybeThrow('confirmSignUp');
  }

  @override
  Future<void> resendConfirmationCode({required String email}) async {
    lastEmail = email;
    _maybeThrow('resendConfirmationCode');
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastEmail = email;
    _maybeThrow('signIn');
  }

  String? lastNewPassword;

  @override
  Future<void> requestPasswordReset({required String email}) async {
    lastEmail = email;
    _maybeThrow('requestPasswordReset');
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    lastEmail = email;
    lastCode = code;
    lastNewPassword = newPassword;
    _maybeThrow('confirmPasswordReset');
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    sessionValid = false;
  }

  @override
  Future<bool> hasValidSession() async {
    calls.add('hasValidSession');
    return sessionValid;
  }

  @override
  Future<String?> currentUserId() async => sessionValid ? 'user-1' : null;

  @override
  Future<String?> currentEmail() async =>
      sessionValid ? 'restored@example.com' : null;
}

void main() {
  late _FakeAuthRepository repository;
  late AuthViewModel viewModel;

  setUp(() {
    repository = _FakeAuthRepository();
    viewModel = AuthViewModel(repository);
  });

  group('startup', () {
    test('status is unknown before the stored session has been checked', () {
      // The splash state. Without it the sign-in form would flash up and then
      // be replaced for a user who is already signed in.
      expect(viewModel.status, AuthStatus.unknown);
    });

    test('a stored session goes straight to signed in', () async {
      repository.sessionValid = true;
      await viewModel.restoreSession();
      expect(viewModel.status, AuthStatus.signedIn);
    });

    test('a restored session knows the account email for Settings', () async {
      repository.sessionValid = true;
      await viewModel.restoreSession();
      expect(viewModel.signedInEmail, 'restored@example.com');
    });

    test('no email is exposed once signed out', () async {
      repository.sessionValid = true;
      await viewModel.restoreSession();
      await viewModel.signOut();
      expect(viewModel.signedInEmail, isNull);
    });

    test('no stored session goes to signed out', () async {
      await viewModel.restoreSession();
      expect(viewModel.status, AuthStatus.signedOut);
    });
  });

  group('sign in', () {
    test('success moves to signed in and reports no error', () async {
      final ok = await viewModel.signIn(email: 'a@b.com', password: 'Passw0rd');
      expect(ok, isTrue);
      expect(viewModel.status, AuthStatus.signedIn);
      expect(viewModel.errorMessage, isNull);
      expect(viewModel.isBusy, isFalse);
    });

    test('the email address is trimmed before being sent', () async {
      // A trailing space from a paste or an autocorrect would otherwise be
      // sent as part of the username and fail with "incorrect password".
      await viewModel.signIn(email: '  a@b.com  ', password: 'Passw0rd');
      expect(repository.lastEmail, 'a@b.com');
    });

    test('bad credentials leave the user signed out with a message', () async {
      repository.nextError = const UnauthorisedException(
        'Incorrect email address or password.',
      );
      final ok = await viewModel.signIn(email: 'a@b.com', password: 'wrong');
      expect(ok, isFalse);
      expect(viewModel.status, AuthStatus.unknown); // unchanged by the attempt
      expect(viewModel.errorMessage, 'Incorrect email address or password.');
    });

    test(
      'an unconfirmed account is routed to confirmation, not an error',
      () async {
        // The behaviour this exists to protect: Cognito reports an unconfirmed
        // account as a failed sign-in, but to the user it is an unfinished
        // registration. Showing it as an error would leave them stuck.
        repository.nextError = const ConfirmationRequiredException(
          'needs confirming',
        );
        final handled = await viewModel.signIn(
          email: 'a@b.com',
          password: 'Passw0rd',
        );

        expect(handled, isTrue, reason: 'handled, so no error banner');
        expect(viewModel.status, AuthStatus.awaitingConfirmation);
        expect(viewModel.errorMessage, isNull);
        expect(viewModel.pendingEmail, 'a@b.com');
        expect(viewModel.notice, isNotNull);
      },
    );

    test('the notice does not claim a new code has been sent', () async {
      // Guards a specific wording decision. No code is resent at this point,
      // so promising one would leave the user waiting for nothing.
      repository.nextError = const ConfirmationRequiredException(
        'needs confirming',
      );
      await viewModel.signIn(email: 'a@b.com', password: 'Passw0rd');
      expect(viewModel.notice, contains('or ask for a new one'));
      expect(viewModel.notice, isNot(contains('We have sent')));
    });

    test('a service failure is not reported as a wrong password', () async {
      repository.nextError = const ServiceUnavailableException(
        'timed out after 10000 ms',
      );
      await viewModel.signIn(email: 'a@b.com', password: 'Passw0rd');
      // The raw technical detail must not reach the user.
      expect(viewModel.errorMessage, isNot(contains('10000')));
      expect(viewModel.errorMessage, contains('connection'));
    });

    test('busy is cleared after a failure, not just after a success', () async {
      // The defect this prevents: a submit button left spinning for ever
      // because the busy flag was only reset on the happy path.
      repository.nextError = const UnauthorisedException('no');
      await viewModel.signIn(email: 'a@b.com', password: 'x');
      expect(viewModel.isBusy, isFalse);
    });

    test('a second submission while one is in flight is ignored', () async {
      // Double-tap protection at the view model, not only at the button, so
      // it holds regardless of how the action was triggered.
      final first = viewModel.signIn(email: 'a@b.com', password: 'Passw0rd');
      final second = await viewModel.signIn(
        email: 'a@b.com',
        password: 'Passw0rd',
      );
      await first;
      expect(second, isFalse);
      expect(
        repository.calls.where((c) => c == 'signIn').length,
        1,
        reason: 'only one request should have been made',
      );
    });
  });

  group('sign up', () {
    test('success moves to confirmation with the address remembered', () async {
      final ok = await viewModel.signUp(
        email: 'new@b.com',
        password: 'Passw0rd',
      );
      expect(ok, isTrue);
      expect(viewModel.status, AuthStatus.awaitingConfirmation);
      expect(viewModel.pendingEmail, 'new@b.com');
      expect(viewModel.notice, contains('new@b.com'));
    });

    test('an existing account is reported with its own message', () async {
      repository.nextError = const AccountExistsException(
        'An account already uses that address.',
      );
      final ok = await viewModel.signUp(
        email: 'taken@b.com',
        password: 'Passw0rd',
      );
      expect(ok, isFalse);
      expect(viewModel.status, AuthStatus.unknown);
      expect(viewModel.errorMessage, 'An account already uses that address.');
    });
  });

  group('confirmation', () {
    setUp(() async {
      await viewModel.signUp(email: 'new@b.com', password: 'Passw0rd');
    });

    test(
      'confirming returns the user to sign in, since no session is issued',
      () async {
        // Cognito's ConfirmSignUp only verifies the address; it does not
        // authenticate. Sending the user to a dashboard would then fail on the
        // first request.
        final ok = await viewModel.confirm(code: '123456');
        expect(ok, isTrue);
        expect(viewModel.status, AuthStatus.signedOut);
        expect(viewModel.notice, contains('can now sign in'));
      },
    );

    test(
      'the remembered address is used, so the user does not retype it',
      () async {
        await viewModel.confirm(code: '123456');
        expect(repository.lastEmail, 'new@b.com');
      },
    );

    test(
      'the code is trimmed, so a pasted value with spaces still works',
      () async {
        await viewModel.confirm(code: ' 123456 ');
        expect(repository.lastCode, '123456');
      },
    );

    test('a wrong code keeps the user on the confirmation step', () async {
      repository.nextError = const InvalidRequestException(
        'That code is not right.',
      );
      final ok = await viewModel.confirm(code: '000000');
      expect(ok, isFalse);
      expect(viewModel.status, AuthStatus.awaitingConfirmation);
      expect(viewModel.errorMessage, 'That code is not right.');
    });

    test('resending reports success as a notice, not as an error', () async {
      final ok = await viewModel.resendCode();
      expect(ok, isTrue);
      expect(viewModel.notice, contains('new@b.com'));
      expect(viewModel.errorMessage, isNull);
    });
  });

  group('password reset', () {
    test('requesting a code remembers the trimmed address', () async {
      final ok = await viewModel.requestPasswordReset(email: ' a@b.com ');
      expect(ok, isTrue);
      expect(repository.lastEmail, 'a@b.com');
      expect(viewModel.resetEmail, 'a@b.com');
    });

    test('the notice does not confirm that an account exists', () async {
      // The service reports success for unregistered addresses, so a notice
      // reading "we have sent a code" would be false for them, and true only
      // for real accounts, which would leak the very thing the backend hides.
      await viewModel.requestPasswordReset(email: 'a@b.com');
      expect(viewModel.notice, startsWith('If an account uses'));
    });

    test('requesting a code does not move the user off sign-in', () async {
      await viewModel.restoreSession();
      await viewModel.requestPasswordReset(email: 'a@b.com');
      expect(viewModel.status, AuthStatus.signedOut);
    });

    test('an unconfirmed account is told why no code can be sent', () async {
      repository.nextError = const ConfirmationRequiredException(
        'Confirm your email address before resetting the password.',
      );
      final ok = await viewModel.requestPasswordReset(email: 'a@b.com');
      expect(ok, isFalse);
      expect(viewModel.errorMessage, contains('Confirm your email'));
    });

    test('the reset uses the remembered address, not one retyped', () async {
      await viewModel.requestPasswordReset(email: 'a@b.com');
      await viewModel.confirmPasswordReset(
        code: ' 123456 ',
        newPassword: 'N3wPassword',
      );
      expect(repository.lastEmail, 'a@b.com');
      expect(repository.lastCode, '123456');
      expect(repository.lastNewPassword, 'N3wPassword');
    });

    test('the new password is sent exactly as typed, never trimmed', () async {
      // Trimming a password would silently change it, and the user would
      // then fail to sign in with the one they believe they set.
      await viewModel.requestPasswordReset(email: 'a@b.com');
      await viewModel.confirmPasswordReset(
        code: '123456',
        newPassword: ' Spaced0ut ',
      );
      expect(repository.lastNewPassword, ' Spaced0ut ');
    });

    test('success says to sign in with the new password', () async {
      await viewModel.requestPasswordReset(email: 'a@b.com');
      final ok = await viewModel.confirmPasswordReset(
        code: '123456',
        newPassword: 'N3wPassword',
      );
      expect(ok, isTrue);
      expect(viewModel.status, AuthStatus.signedOut);
      expect(viewModel.notice, contains('new password'));
    });

    test('a wrong code keeps the reset open with the reason shown', () async {
      await viewModel.requestPasswordReset(email: 'a@b.com');
      repository.nextError = const InvalidRequestException(
        'That code is not right.',
      );
      final ok = await viewModel.confirmPasswordReset(
        code: '000000',
        newPassword: 'N3wPassword',
      );
      expect(ok, isFalse);
      expect(viewModel.errorMessage, 'That code is not right.');
    });

    test('reset and registration keep separate addresses', () async {
      // Guards against one flow redirecting the other's code.
      await viewModel.signUp(email: 'new@b.com', password: 'Passw0rd');
      await viewModel.requestPasswordReset(email: 'old@b.com');
      expect(viewModel.pendingEmail, 'new@b.com');
      expect(viewModel.resetEmail, 'old@b.com');
    });
  });

  group('ending a session', () {
    test('signing out clears messages and returns to signed out', () async {
      await viewModel.signIn(email: 'a@b.com', password: 'Passw0rd');
      await viewModel.signOut();
      expect(viewModel.status, AuthStatus.signedOut);
      expect(viewModel.notice, isNull);
      expect(viewModel.errorMessage, isNull);
    });

    test(
      'expiry explains itself instead of silently returning to sign in',
      () async {
        await viewModel.signIn(email: 'a@b.com', password: 'Passw0rd');
        await viewModel.sessionExpired();
        expect(viewModel.status, AuthStatus.signedOut);
        expect(viewModel.notice, contains('expired'));
        // A notice, not an error: nothing has gone wrong, a token simply aged.
        expect(viewModel.errorMessage, isNull);
      },
    );

    test('expiry still clears the stored session', () async {
      await viewModel.sessionExpired();
      expect(repository.calls, contains('signOut'));
    });
  });

  test('listeners are notified on every state change', () async {
    // The whole UI is driven by these notifications, so a change that does
    // not notify is a change the user never sees.
    var notifications = 0;
    viewModel.addListener(() => notifications++);
    await viewModel.signIn(email: 'a@b.com', password: 'Passw0rd');
    // Once when the request starts and the busy state is set, once when it
    // finishes.
    expect(notifications, 2);
  });
}
