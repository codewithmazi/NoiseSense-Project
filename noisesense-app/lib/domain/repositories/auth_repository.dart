/// Account and session operations the app needs.
/// Like [NoiseRepository], this interface names no identity provider.
/// Every method reports failure by throwing a `NoiseSenseException`, so the UI distinguishes "wrong password" from "no signal" without inspecting status codes.
abstract interface class AuthRepository {
  /// Registers a new account. The service then emails a confirmation code.
  /// Throws [AccountExistsException] if the email is already registered, or [InvalidRequestException] if the password fails the policy.
  Future<void> signUp({required String email, required String password});

  /// Confirms a new account with the emailed code. Throws [InvalidRequestException] if the code is wrong or expired.
  Future<void> confirmSignUp({required String email, required String code});

  /// Sends a fresh confirmation code, for when the first expired or was lost.
  Future<void> resendConfirmationCode({required String email});

  /// Signs in and stores the session. Throws [UnauthorisedException] for bad credentials, or [ConfirmationRequiredException] if the account is not yet confirmed.
  Future<void> signIn({required String email, required String password});

  /// Password reset. Completes normally whether or not [email] is registered, so the reset flow cannot be used to discover which addresses have accounts. Throws
  /// throws [ConfirmationRequiredException] for an account that was never confirmed.
  Future<void> requestPasswordReset({required String email});

  /// Sets a new password using the emailed code. Throws [InvalidRequestException] for wrong or expired code, or if the new password fails the policy.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Clears the stored session.
  Future<void> signOut();

  /// Returns whether a valid session exists, restoring it if needed.
  Future<bool> hasValidSession();

  /// Stable, opaque ID for the signed-in user, or null when signed out. Separates each user's data.
  Future<String?> currentUserId();

  /// The signed-in user's email address.
  Future<String?> currentEmail();
}
