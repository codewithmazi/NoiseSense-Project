import 'package:amazon_cognito_identity_dart_2/cognito.dart';

import '../../domain/errors.dart';
import '../../domain/repositories/auth_repository.dart';
import '../api/token_provider.dart';
import 'cognito_rest_api.dart';

/// Cognito-backed authentication.
///
/// Implements both [AuthRepository], for account and session operations, and
/// [TokenProvider], so the API client can obtain a bearer token without
/// knowing anything about Cognito.
///
/// The work is split deliberately. Sign-in goes through
/// `amazon_cognito_identity_dart_2`, which implements SRP so the password
/// never leaves the device. Sign-up, confirmation and resend go through
/// [CognitoRestApi], because the Week 1 spike found the package's error
/// reporting for those operations too vague to drive a usable interface.
class CognitoAuthService implements AuthRepository, TokenProvider {
  /// Dart exposes a private field formal without its underscore, so callers
  /// write `pool:` and `api:` while the fields stay private.
  CognitoAuthService({required this._pool, required this._api});

  final CognitoUserPool _pool;
  final CognitoRestApi _api;

  /// Cached so repeated API calls do not re-read secure storage. The package
  /// refreshes the underlying tokens when they expire.
  CognitoUser? _user;

  // ----------------------------------------------------------- AuthRepository

  @override
  Future<void> signUp({required String email, required String password}) =>
      _api.signUp(email: email, password: password);

  @override
  Future<void> confirmSignUp({required String email, required String code}) =>
      _api.confirmSignUp(email: email, code: code);

  @override
  Future<void> resendConfirmationCode({required String email}) =>
      _api.resendConfirmationCode(email: email);

  @override
  Future<void> requestPasswordReset({required String email}) =>
      _api.forgotPassword(email: email);

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) => _api.confirmForgotPassword(
    email: email,
    code: code,
    newPassword: newPassword,
  );

  @override
  Future<void> signIn({required String email, required String password}) async {
    final user = CognitoUser(email, _pool);
    try {
      // SRP: proves knowledge of the password without transmitting it.
      await user.authenticateUser(
        AuthenticationDetails(username: email, password: password),
      );
      _user = user;
    } on CognitoUserNewPasswordRequiredException {
      // Only reachable for admin-created accounts, which this app never makes.
      throw const InvalidRequestException('This account needs a new password.');
    } on CognitoUserConfirmationNecessaryException {
      throw const ConfirmationRequiredException(
        'Confirm your email address to continue.',
      );
    } on CognitoClientException catch (e) {
      throw _mapSignInError(e);
    }
  }

  @override
  Future<void> signOut() async {
    final user = _user ?? await _pool.getCurrentUser();
    // Clears the locally stored session. It does not revoke the refresh token
    // server-side, so the sign-out is local only; noted as a limitation.
    await user?.signOut();
    _user = null;
  }

  @override
  Future<bool> hasValidSession() async {
    try {
      return await _session() != null;
    } on NoiseSenseException {
      // At startup an unusable session is simply "not signed in"; the user is
      // shown the sign-in screen rather than an error.
      return false;
    }
  }

  // ------------------------------------------------------------ TokenProvider

  /// The Cognito subject (`sub`) from the access token: a UUID that never
  /// changes for the account, unlike the email address, which a user can
  /// change. The token was issued to this device by Cognito, so its payload is
  /// read without re-verifying the signature; it is only used as a local
  /// storage key, never to authorise anything.
  @override
  Future<String?> currentUserId() async =>
      (await _session())?.getAccessToken().getSub();

  /// Read from the ID token, which carries the `email` claim; the access token
  /// does not. It is only displayed on this device, never sent anywhere, so
  /// this does not reverse the decision to send the access token to the API.
  @override
  Future<String?> currentEmail() async {
    final payload = (await _session())?.getIdToken().payload;
    final email = payload is Map ? payload['email'] : null;
    return email is String ? email : null;
  }

  @override
  Future<String?> bearerToken() async {
    final session = await _session();
    // See TokenProvider.bearerToken: the access token is sent rather than the
    // ID token, so no identity attributes are disclosed to the API.
    return session?.getAccessToken().getJwtToken();
  }

  /// Restores the stored session, refreshing it if the tokens have expired.
  /// Returns null when nobody is signed in.
  Future<CognitoUserSession?> _session() async {
    final user = _user ??= await _pool.getCurrentUser();
    if (user == null) return null;
    try {
      final session = await user.getSession();
      // A session past its expiry whose refresh failed is unusable.
      if (session == null || !session.isValid()) return null;
      return session;
    } on CognitoClientException catch (e) {
      // A revoked or expired refresh token means a genuine re-authentication.
      if (e.code == 'NotAuthorizedException') {
        _user = null;
        return null;
      }
      throw ServiceUnavailableException(
        e.message ?? 'Could not refresh session',
      );
    }
  }

  NoiseSenseException _mapSignInError(CognitoClientException e) {
    final detail = e.message ?? e.code ?? 'Sign-in failed';
    return switch (e.code) {
      // Wrong password and unknown account are reported identically, so the
      // API cannot be used to enumerate registered email addresses.
      'NotAuthorizedException' || 'UserNotFoundException' =>
        const UnauthorisedException('Incorrect email address or password.'),
      'UserNotConfirmedException' => ConfirmationRequiredException(detail),
      'PasswordResetRequiredException' => const InvalidRequestException(
        'Reset your password to continue.',
      ),
      'TooManyRequestsException' ||
      'LimitExceededException' => ServiceUnavailableException(detail),
      _ => UnexpectedResponseException(detail),
    };
  }
}
