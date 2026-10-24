/// Supplies the bearer token for API calls.
abstract interface class TokenProvider {
  /// The token to send in the Authorization header.
  Future<String?> bearerToken();
}
