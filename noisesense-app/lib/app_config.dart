/// Environment-specific settings supplied at build time via `--dart-define`.
class AppConfig {
  const AppConfig({
    required this.region,
    required this.userPoolId,
    required this.userPoolClientId,
    required this.apiBaseUrl,
  });

  /// Configuration compiled into this binary; missing values are empty strings.
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

  /// Names of missing configuration values.
  List<String> get missingKeys => [
    if (region.isEmpty) 'AWS_REGION',
    if (userPoolId.isEmpty) 'USER_POOL_ID',
    if (userPoolClientId.isEmpty) 'USER_POOL_CLIENT_ID',
    if (apiBaseUrl.isEmpty) 'API_BASE_URL',
  ];

  bool get isComplete => missingKeys.isEmpty;

  /// Minimum password length enforced by the user pool.
  static const int passwordMinLength = 8;
}
