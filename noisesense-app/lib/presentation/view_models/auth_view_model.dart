import 'package:flutter/foundation.dart';

import '../../domain/errors.dart';
import '../../domain/repositories/auth_repository.dart';
import '../error_text.dart';

/// Where the user is in the sign-in process.
enum AuthStatus {
  /// Startup: the stored session has not been checked yet.
  unknown,

  /// Nobody is signed in.
  signedOut,

  /// An account exists but its email address is unconfirmed.
  awaitingConfirmation,

  /// A usable session is held.
  signedIn,
}

/// Presentation state for registration and sign-in.
class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._auth);

  final AuthRepository _auth;

  AuthStatus _status = AuthStatus.unknown;
  bool _isBusy = false;
  String? _errorMessage;
  String? _notice;
  String _pendingEmail = '';

  AuthStatus get status => _status;

  /// True while a request is in flight.
  bool get isBusy => _isBusy;

  /// The current failure to display, or null.
  String? get errorMessage => _errorMessage;

  /// A non-failure message to display, such as confirmation that a new code has been sent.
  String? get notice => _notice;

  /// The address awaiting confirmation.
  String get pendingEmail => _pendingEmail;

  /// Decides the opening screen by checking for a stored session.
  Future<void> restoreSession() async {
    final valid = await _auth.hasValidSession();
    _status = valid ? AuthStatus.signedIn : AuthStatus.signedOut;
    if (valid) _signedInEmail = await _auth.currentEmail();
    notifyListeners();
  }

  String? _signedInEmail;

  /// The account shown in Settings.
  String? get signedInEmail =>
      _status == AuthStatus.signedIn ? _signedInEmail : null;

  Future<bool> signIn({required String email, required String password}) {
    final address = email.trim();
    return _run(
      () async {
        await _auth.signIn(email: address, password: password);
        _signedInEmail = address;
        _status = AuthStatus.signedIn;
      },
      onFailure: (error) {
        // Signing in to an unconfirmed account is not a dead end.
        if (error is ConfirmationRequiredException) {
          _pendingEmail = address;
          _status = AuthStatus.awaitingConfirmation;
          // Worded so as not to imply a new code was sent.
          _notice =
              'This address still needs confirming. Enter the code emailed '
              'to $address, or ask for a new one.';
          // Returning true suppresses the error banner.
          return true;
        }
        return false;
      },
    );
  }

  Future<bool> signUp({required String email, required String password}) {
    final address = email.trim();
    return _run(() async {
      await _auth.signUp(email: address, password: password);
      _pendingEmail = address;
      _status = AuthStatus.awaitingConfirmation;
      _notice = 'We have sent a confirmation code to $address.';
    });
  }

  Future<bool> confirm({required String code}) {
    assert(_pendingEmail.isNotEmpty, 'confirm() called with no pending email');
    return _run(() async {
      await _auth.confirmSignUp(email: _pendingEmail, code: code.trim());
      // ConfirmSignUp only verifies the address; it does not sign in.
      _status = AuthStatus.signedOut;
      _notice = 'Email address confirmed. You can now sign in.';
    });
  }

  Future<bool> resendCode() {
    assert(
      _pendingEmail.isNotEmpty,
      'resendCode() called with no pending email',
    );
    return _run(() async {
      await _auth.resendConfirmationCode(email: _pendingEmail);
      _notice = 'A new code is on its way to $_pendingEmail.';
    });
  }

  /// Address a password reset is in progress for, or empty.
  String get resetEmail => _resetEmail;
  String _resetEmail = '';

  /// Asks for a reset code.
  Future<bool> requestPasswordReset({required String email}) {
    final address = email.trim();
    return _run(() async {
      await _auth.requestPasswordReset(email: address);
      _resetEmail = address;
      // Conditional on purpose.
      _notice =
          'If an account uses $address, a reset code is on its way. '
          'It can take a minute to arrive.';
    });
  }

  /// Sets the new password.
  Future<bool> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) {
    assert(
      _resetEmail.isNotEmpty,
      'confirmPasswordReset() with no reset email',
    );
    return _run(() async {
      await _auth.confirmPasswordReset(
        email: _resetEmail,
        code: code.trim(),
        newPassword: newPassword,
      );
      _status = AuthStatus.signedOut;
      _notice = 'Password changed. Sign in with your new password.';
    });
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _status = AuthStatus.signedOut;
    _errorMessage = null;
    _notice = null;
    notifyListeners();
  }

  /// Ends the session because the service rejected the stored token.
  Future<void> sessionExpired() async {
    await _auth.signOut();
    _status = AuthStatus.signedOut;
    _errorMessage = null;
    _notice = 'Your session has expired. Please sign in again.';
    notifyListeners();
  }

  /// Dismisses whatever message is on screen, so a stale one does not follow the user to the next step.
  void clearMessages() {
    if (_errorMessage == null && _notice == null) return;
    _errorMessage = null;
    _notice = null;
    notifyListeners();
  }

  /// Runs [action] with busy state, error translation and one notification.
  Future<bool> _run(
    Future<void> Function() action, {
    bool Function(NoiseSenseException error)? onFailure,
  }) async {
    if (_isBusy) return false; // Ignore a double tap already in progress.
    _isBusy = true;
    _errorMessage = null;
    _notice = null;
    notifyListeners();

    var succeeded = false;
    try {
      await action();
      succeeded = true;
    } on NoiseSenseException catch (error) {
      succeeded = onFailure?.call(error) ?? false;
      if (!succeeded) _errorMessage = userMessageFor(error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
    return succeeded;
  }
}
