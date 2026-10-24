import 'package:amazon_cognito_identity_dart_2/cognito.dart';

import '../../domain/errors.dart';
import '../../domain/repositories/auth_repository.dart';
import '../api/token_provider.dart';
import 'cognito_rest_api.dart';

/// Cognito-backed authentication.
class CognitoAuthService implements AuthRepository, TokenProvider {
  /// Private field formals: callers write `pool:` and `api:`.
  CognitoAuthService({required this._pool, required this._api});

  final CognitoUserPool _pool;
  final CognitoRestApi _api;

  /// Cached so repeated API calls do not re-read secure storage.
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
    // Clears the locally stored session.
    await user?.signOut();
    _user = null;
  }

  @override
  Future<bool> hasValidSession() async {
    try {
      return await _session() != null;
    } on NoiseSenseException {
      // At startup an unusable session is simply "not signed in".
      return false;
    }
  }

  // ------------------------------------------------------------ TokenProvider

  /// The Cognito subject (`sub`) from the access token.
  @override
  Future<String?> currentUserId() async =>
      (await _session())?.getAccessToken().getSub();

  /// Read from the ID token, which carries the `email` claim; the access token does not.
  @override
  Future<String?> currentEmail() async {
    final payload = (await _session())?.getIdToken().payload;
    final email = payload is Map ? payload['email'] : null;
    return email is String ? email : null;
  }

  @override
  Future<String?> bearerToken() async {
    final session = await _session();
    // See TokenProvider.bearerToken.
    return session?.getAccessToken().getJwtToken();
  }

  /// Restores the stored session, refreshing it if the tokens have expired.
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
      // Wrong password and unknown account are reported identically.
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
