/// Environment-specific settings, supplied at build time.
///
/// None of these are hardcoded in source. They arrive through `--dart-define`,
/// which Dart resolves at compile time, so a build for a different AWS account
/// needs no code change:
///
/// ```
/// flutter run \
///   --dart-define=AWS_REGION=us-east-1 \
///   --dart-define=USER_POOL_ID=us-east-1_XXXXXXXXX \
///   --dart-define=USER_POOL_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx \
///   --dart-define=API_BASE_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com
/// ```
///
/// This matters in the Learner Lab specifically: the stack is torn down and
/// redeployed each session, so the pool and API identifiers change regularly.
/// Keeping them out of source means a redeploy never produces a code commit,
/// and the repository carries no reference to one particular lab account.
///
/// These values are configuration, not secrets. A Cognito user pool client
/// created without a client secret (`GenerateSecret: false`) is designed to be
/// embedded in a public client, because possessing the identifier grants
/// nothing without credentials. The genuine secrets, the user's password and
/// tokens, are never compiled in: the password is handled by SRP and the
/// tokens live in Android Keystore-backed storage.
class AppConfig {
  const AppConfig({
    required this.region,
    required this.userPoolId,
    required this.userPoolClientId,
    required this.apiBaseUrl,
  });

  /// The configuration this binary was compiled with. Values absent from the
  /// build are empty strings rather than nulls, which is why [missingKeys]
  /// exists instead of a null check.
  static const AppConfig fromEnvironment = AppConfig(
    region: String.fromEnvironment('AWS_REGION'),
    userPoolId: String.fromEnvironment('USER_POOL_ID'),
    userPoolClientId: String.fromEnvironment('USER_POOL_CLIENT_ID'),
    apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
  );

  final String region;
  final String userPoolId;
  final String userPoolClientId;
  final String apiBaseUrl;

  /// Names of the settings this build is missing.
  ///
  /// Checked at startup so a misconfigured build says so immediately, rather
  /// than presenting a working sign-in screen that fails with an opaque
  /// network error. Failing at the earliest possible point is cheaper to
  /// diagnose than failing at the first request.
  List<String> get missingKeys => [
    if (region.isEmpty) 'AWS_REGION',
    if (userPoolId.isEmpty) 'USER_POOL_ID',
    if (userPoolClientId.isEmpty) 'USER_POOL_CLIENT_ID',
    if (apiBaseUrl.isEmpty) 'API_BASE_URL',
  ];

  bool get isComplete => missingKeys.isEmpty;

  /// Password rules enforced by the deployed user pool, mirrored here so the
  /// user is told before a request is made (Nielsen, 1994: error prevention).
  ///
  /// Cognito remains authoritative. This copy is a convenience, and
  /// [CognitoRestApi] still maps a server-side `InvalidPasswordException` to a
  /// message the user can act on, in case the two ever drift apart.
  static const int passwordMinLength = 8;
}
