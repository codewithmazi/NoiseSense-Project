import 'package:flutter/foundation.dart';

import '../../domain/errors.dart';
import '../../domain/repositories/auth_repository.dart';
import '../error_text.dart';

/// Where the user is in the sign-in process.
///
/// This is the only thing that decides which screen is on display, so the
/// states are mutually exclusive by construction. An app that tracks
/// `isLoading`, `isSignedIn` and `needsConfirmation` as three independent
/// booleans can represent eight situations, of which five are nonsense.
enum AuthStatus {
  /// Startup: the stored session has not been checked yet. Distinct from
  /// [signedOut] so a returning user sees a brief splash rather than a
  /// sign-in form that vanishes a moment later.
  unknown,

  /// Nobody is signed in.
  signedOut,

  /// An account exists but its email address is unconfirmed, so the next step
  /// is entering the emailed code.
  awaitingConfirmation,

  /// A usable session is held.
  signedIn,
}

/// Presentation state for registration and sign-in.
///
/// It depends on [AuthRepository], an interface in the domain layer, and knows
/// nothing about Cognito, SRP, JWTs or HTTP. That is what lets the whole class
/// be unit tested against a fake repository, with no network and no AWS
/// account, and it is the same inversion that keeps the identity provider
/// replaceable (603: NFR-06).
///
/// `ChangeNotifier` is the SDK's own observer implementation. It was preferred
/// to Bloc or Riverpod because this app has a small number of independent view
/// models and no shared mutable state beyond the session: those packages would
/// have added a dependency and a good deal of ceremony without making anything
/// here more testable. The trade-off accepted is losing Bloc's explicit,
/// replayable event stream, which would have been worth having in a larger
/// team. The decision is recorded in the change log rather than left implicit.
class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._auth);

  final AuthRepository _auth;

  AuthStatus _status = AuthStatus.unknown;
  bool _isBusy = false;
  String? _errorMessage;
  String? _notice;
  String _pendingEmail = '';

  AuthStatus get status => _status;

  /// True while a request is in flight. Screens use this to show progress and
  /// to detach their submit buttons.
  bool get isBusy => _isBusy;

  /// The current failure to display, or null.
  String? get errorMessage => _errorMessage;

  /// A non-failure message to display, such as confirmation that a new code
  /// has been sent. Kept separate from [errorMessage] so success is never
  /// rendered in the error style.
  String? get notice => _notice;

  /// The address awaiting confirmation. The confirmation screen shows it, so
  /// the user can see whether they mistyped it, and resend uses it so they do
  /// not have to type it again (Nielsen, 1994: recognition rather than
  /// recall).
  String get pendingEmail => _pendingEmail;

  /// Decides the opening screen by checking for a stored session.
  ///
  /// Called once at startup. Session restoration is why the app does not ask
  /// a returning user for their password: the refresh token in Keystore-backed
  /// storage is exchanged for new tokens without their involvement.
  Future<void> restoreSession() async {
    final valid = await _auth.hasValidSession();
    _status = valid ? AuthStatus.signedIn : AuthStatus.signedOut;
    if (valid) _signedInEmail = await _auth.currentEmail();
    notifyListeners();
  }

  String? _signedInEmail;

  /// The account shown in Settings. Null when signed out, or if the token
  /// does not carry an address.
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
        // Signing in to an unconfirmed account is not a dead end. Rather than
        // reporting a failure, the user is moved to the step that resolves it.
        if (error is ConfirmationRequiredException) {
          _pendingEmail = address;
          _status = AuthStatus.awaitingConfirmation;
          // Worded carefully: no new code has been sent at this point. Claiming
          // one had been would leave the user waiting for an email that is not
          // coming, so the offer to resend is made explicit instead.
          _notice =
              'This address still needs confirming. Enter the code emailed '
              'to $address, or ask for a new one.';
          // Returning true suppresses the error banner: from the user's point
          // of view the action succeeded in moving them forward.
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
      // Confirmation does not produce a session: Cognito's ConfirmSignUp
      // only marks the address verified. The user still has to sign in, so
      // they are returned to the sign-in screen with the reason stated.
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
  ///
  /// Kept separate from [pendingEmail], which belongs to registration. The two
  /// flows can be entered one after the other, and sharing one field would let
  /// a half-finished sign-up silently redirect a reset code to the wrong
  /// address.
  String get resetEmail => _resetEmail;
  String _resetEmail = '';

  /// Asks for a reset code. Does not change [status]: resetting a password
  /// happens beside the sign-in screen, not instead of it, so the back button
  /// still returns there.
  Future<bool> requestPasswordReset({required String email}) {
    final address = email.trim();
    return _run(() async {
      await _auth.requestPasswordReset(email: address);
      _resetEmail = address;
      // Conditional on purpose. The service reports success for addresses
      // with no account, so the app must not claim that one exists.
      _notice =
          'If an account uses $address, a reset code is on its way. '
          'It can take a minute to arrive.';
    });
  }

  /// Sets the new password. On success the user is told to sign in with it,
  /// rather than being signed in automatically: Cognito's
  /// ConfirmForgotPassword returns no tokens, and signing in silently with a
  /// password just typed would hide a mistake in it until the next launch.
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
  ///
  /// Separate from [signOut] so the user is told why they are back at the
  /// sign-in screen. Being silently logged out mid-task reads as a crash.
  Future<void> sessionExpired() async {
    await _auth.signOut();
    _status = AuthStatus.signedOut;
    _errorMessage = null;
    _notice = 'Your session has expired. Please sign in again.';
    notifyListeners();
  }

  /// Dismisses whatever message is on screen, so a stale one does not follow
  /// the user to the next step.
  void clearMessages() {
    if (_errorMessage == null && _notice == null) return;
    _errorMessage = null;
    _notice = null;
    notifyListeners();
  }

  /// Runs [action] with busy state, error translation and one notification.
  ///
  /// Every operation shares this, which is what guarantees the busy flag is
  /// always cleared, including on the failure paths. Doing it per-method is
  /// how buttons get left spinning forever after an error.
  ///
  /// [onFailure] lets a caller claim a particular exception and handle it as
  /// something other than an error; returning true means "handled, show no
  /// error banner".
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
