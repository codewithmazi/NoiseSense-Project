import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/errors.dart';

/// Direct Cognito API calls for sign-up, confirmation and code resend.
class CognitoRestApi {
  CognitoRestApi({
    required this.region,
    required this.clientId,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final String region;
  final String clientId;
  final http.Client _http;
  final Duration timeout;

  Uri get _endpoint => Uri.parse('https://cognito-idp.$region.amazonaws.com/');

  Future<void> signUp({required String email, required String password}) =>
      _call('SignUp', {
        'ClientId': clientId,
        'Username': email,
        'Password': password,
        'UserAttributes': [
          {'Name': 'email', 'Value': email},
        ],
      });

  Future<void> confirmSignUp({required String email, required String code}) =>
      _call('ConfirmSignUp', {
        'ClientId': clientId,
        'Username': email,
        'ConfirmationCode': code,
      });

  Future<void> resendConfirmationCode({required String email}) => _call(
    'ResendConfirmationCode',
    {'ClientId': clientId, 'Username': email},
  );

  /// Starts a password reset: Cognito emails a code to the verified address.
  Future<void> forgotPassword({required String email}) => _call(
    'ForgotPassword',
    {'ClientId': clientId, 'Username': email},
    succeedOn: const {'UserNotFoundException'},
  );

  /// Completes a password reset with the emailed code and a new password.
  Future<void> confirmForgotPassword({
    required String email,
    required String code,
    required String newPassword,
  }) => _call('ConfirmForgotPassword', {
    'ClientId': clientId,
    'Username': email,
    'ConfirmationCode': code,
    'Password': newPassword,
  });

  /// Sends one Cognito action.
  Future<void> _call(
    String action,
    Map<String, Object?> payload, {
    Set<String> succeedOn = const {},
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/x-amz-json-1.1',
              'X-Amz-Target': 'AWSCognitoIdentityProviderService.$action',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw ServiceUnavailableException('$action timed out');
    } on http.ClientException catch (e) {
      throw ServiceUnavailableException('$action failed: ${e.message}');
    }

    if (response.statusCode == 200) return;
    if (succeedOn.isNotEmpty && succeedOn.contains(_errorType(response))) {
      return;
    }
    throw _mapError(action, response);
  }

  /// The final segment of Cognito's `__type`, or null if the body has none.
  static String? _errorType(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['__type'] as String?)?.split('#').last;
      }
    } on FormatException {
      // Not JSON.
    }
    return null;
  }

  /// Translates a Cognito error response into a domain exception.
  NoiseSenseException _mapError(String action, http.Response response) {
    String? type;
    String? message;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        type = (decoded['__type'] as String?)?.split('#').last;
        // Cognito is inconsistent about the capitalisation of this field.
        message = (decoded['message'] ?? decoded['Message']) as String?;
      }
    } on FormatException {
      // Not JSON: likely an HTML error page from an intermediary.
    }

    final detail = message ?? 'HTTP ${response.statusCode}';
    return switch (type) {
      'UsernameExistsException' => const AccountExistsException(
        'An account with that email already exists.',
      ),
      'UserNotConfirmedException' => ConfirmationRequiredException(detail),
      // All three are user-correctable, so the service's own wording is shown.
      'CodeMismatchException' ||
      'ExpiredCodeException' ||
      'InvalidPasswordException' => InvalidRequestException(detail),
      // Cognito's response when the account exists but has no verified address to send a code to.
      'InvalidParameterException'
          when action == 'ForgotPassword' &&
              detail.toLowerCase().contains('verified') =>
        const ConfirmationRequiredException(
          'Confirm your email address before resetting the password.',
        ),
      'InvalidParameterException' => InvalidRequestException(detail),
      'NotAuthorizedException' => UnauthorisedException(detail),
      // Cognito rate limits aggressively; these are worth retrying.
      'TooManyRequestsException' ||
      'LimitExceededException' ||
      'TooManyFailedAttemptsException' => ServiceUnavailableException(detail),
      // Only reachable while the app client is on LEGACY existence errors.
      'UserNotFoundException' => switch (action) {
        // Worded as a bad code, so unregistered addresses cannot be detected.
        'ConfirmForgotPassword' => const InvalidRequestException(
          'That code is not right. Check the email and try again.',
        ),
        _ => const UnauthorisedException(
          'Incorrect email address or password.',
        ),
      },
      _ =>
        response.statusCode >= 500
            ? ServiceUnavailableException('$action: $detail')
            : UnexpectedResponseException('$action returned ${type ?? detail}'),
    };
  }
}
