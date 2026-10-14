/// Supplies the bearer token for API calls.
///
/// The API client depends on this interface rather than on Cognito directly,
/// so it can be tested with a fake and so the identity provider can change
/// without touching HTTP code.
abstract interface class TokenProvider {
  /// The token to send as `Authorization: Bearer ...`, refreshed if necessary,
  /// or null when no user is signed in.
  ///
  /// The implementation returns the Cognito **access token**, not the ID token.
  /// The spike confirmed the API Gateway authoriser accepts either, because it
  /// matches its configured audience against a token's `aud` *or* `client_id`
  /// claim, and Cognito puts the app client id in `client_id` on access
  /// tokens. Given a free choice, the access token is correct on two counts:
  /// OAuth 2.0 intends access tokens for resource access and ID tokens for
  /// telling the client who the user is; and the ID token carries identity
  /// attributes such as the user's email, which the API has no need of. Not
  /// sending them keeps the auth layer consistent with the project's data
  /// minimisation stance.
  ///
  /// The name is deliberately neutral so this decision can be revisited
  /// without the interface becoming a lie.
  Future<String?> bearerToken();
}
