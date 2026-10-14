/// Account and session operations the app needs.
///
/// Like [NoiseRepository], this interface names no identity provider. Screens
/// depend on it, not on Cognito, so the provider can be replaced by writing
/// one new implementation (603: NFR-06).
///
/// Every method reports failure by throwing a `NoiseSenseException`, so the
/// UI distinguishes "wrong password" from "no signal" without inspecting
/// status codes.
abstract interface class AuthRepository {
  /// Registers a new account. The service then emails a confirmation code.
  ///
  /// Throws [AccountExistsException] if the email is already registered, or
  /// [InvalidRequestException] if the password fails the policy.
  Future<void> signUp({required String email, required String password});

  /// Confirms a new account with the emailed code.
  ///
  /// Throws [InvalidRequestException] if the code is wrong or expired.
  Future<void> confirmSignUp({required String email, required String code});

  /// Sends a fresh confirmation code, for when the first expired or was lost.
  Future<void> resendConfirmationCode({required String email});

  /// Signs in and stores the session.
  ///
  /// Throws [UnauthorisedException] for bad credentials, or
  /// [ConfirmationRequiredException] if the account is not yet confirmed.
  Future<void> signIn({required String email, required String password});

  /// Starts a password reset by emailing a code.
  ///
  /// Completes normally whether or not [email] is registered, so the reset
  /// flow cannot be used to discover which addresses have accounts. Throws
  /// [ConfirmationRequiredException] for an account that was never confirmed,
  /// since there is no verified address to send a code to.
  Future<void> requestPasswordReset({required String email});

  /// Sets a new password using the emailed code.
  ///
  /// Throws [InvalidRequestException] if the code is wrong or expired, or the
  /// new password fails the policy.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Clears the stored session. Safe to call when already signed out.
  Future<void> signOut();

  /// Whether a usable session exists, restoring and refreshing it if needed.
  ///
  /// Used at startup to decide between the sign-in screen and the dashboard,
  /// so a returning user is not asked to sign in again.
  Future<bool> hasValidSession();
}
