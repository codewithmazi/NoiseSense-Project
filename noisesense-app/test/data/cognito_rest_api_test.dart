import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noise_sense/data/auth/cognito_rest_api.dart';
import 'package:noise_sense/domain/errors.dart';

/// Builds a Cognito-shaped error response.
http.Response _awsError(String type, String message, [int status = 400]) =>
    http.Response(
      jsonEncode({
        '__type': 'com.amazon.coral.service#$type',
        'message': message,
      }),
      status,
      headers: {'content-type': 'application/x-amz-json-1.1'},
    );

CognitoRestApi _api(MockClientHandler handler) => CognitoRestApi(
  region: 'us-east-1',
  clientId: 'test-client-id',
  httpClient: MockClient(handler),
  timeout: const Duration(seconds: 2),
);

void main() {
  group('request shape', () {
    test(
      'SignUp targets the right action and sends the email attribute',
      () async {
        late http.Request sent;
        final api = _api((request) async {
          sent = request;
          return http.Response('{}', 200);
        });

        await api.signUp(email: 'test@example.test', password: 'Passw0rd');

        expect(
          sent.url.toString(),
          'https://cognito-idp.us-east-1.amazonaws.com/',
        );
        expect(
          sent.headers['X-Amz-Target'],
          'AWSCognitoIdentityProviderService.SignUp',
        );
        expect(
          sent.headers['Content-Type'],
          startsWith('application/x-amz-json-1.1'),
        );
        expect(jsonDecode(sent.body), {
          'ClientId': 'test-client-id',
          'Username': 'test@example.test',
          'Password': 'Passw0rd',
          'UserAttributes': [
            {'Name': 'email', 'Value': 'test@example.test'},
          ],
        });
      },
    );

    test(
      'the request carries no AWS credentials, being a public operation',
      () async {
        late http.Request sent;
        final api = _api((request) async {
          sent = request;
          return http.Response('{}', 200);
        });

        await api.confirmSignUp(email: 'test@example.test', code: '123456');

        expect(
          sent.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(
          sent.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-amz-security-token')),
        );
      },
    );

    test('ConfirmSignUp sends the code', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return http.Response('{}', 200);
      });

      await api.confirmSignUp(email: 'test@example.test', code: '426074');

      expect(
        sent.headers['X-Amz-Target'],
        'AWSCognitoIdentityProviderService.ConfirmSignUp',
      );
      expect(jsonDecode(sent.body), {
        'ClientId': 'test-client-id',
        'Username': 'test@example.test',
        'ConfirmationCode': '426074',
      });
    });
  });

  group('error mapping', () {
    // This is the mapping the Week 1 spike motivated: the Dart package
    // collapsed all of these into a single "Unknown error".
    test(
      'an existing account is reported as such, not as a generic failure',
      () async {
        final api = _api(
          (_) async => _awsError('UsernameExistsException', 'User exists'),
        );
        await expectLater(
          api.signUp(email: 'a@b.test', password: 'Passw0rd'),
          throwsA(isA<AccountExistsException>()),
        );
      },
    );

    test(
      'a wrong code is user-correctable and keeps the service wording',
      () async {
        final api = _api(
          (_) async => _awsError(
            'CodeMismatchException',
            'Invalid verification code provided',
          ),
        );
        await expectLater(
          api.confirmSignUp(email: 'a@b.test', code: '000000'),
          throwsA(
            isA<InvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Invalid verification code provided',
            ),
          ),
        );
      },
    );

    test('an expired code is distinguishable from a wrong one', () async {
      final api = _api(
        (_) async => _awsError('ExpiredCodeException', 'Code has expired'),
      );
      await expectLater(
        api.confirmSignUp(email: 'a@b.test', code: '123456'),
        throwsA(
          isA<InvalidRequestException>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
    });

    test('an unconfirmed account routes the user to confirmation', () async {
      final api = _api(
        (_) async => _awsError('UserNotConfirmedException', 'Not confirmed'),
      );
      await expectLater(
        api.resendConfirmationCode(email: 'a@b.test'),
        throwsA(isA<ConfirmationRequiredException>()),
      );
    });

    test('a weak password is reported with the policy message', () async {
      final api = _api(
        (_) async =>
            _awsError('InvalidPasswordException', 'Password must have numbers'),
      );
      await expectLater(
        api.signUp(email: 'a@b.test', password: 'weak'),
        throwsA(
          isA<InvalidRequestException>().having(
            (e) => e.message,
            'message',
            contains('numbers'),
          ),
        ),
      );
    });

    test('rate limiting is retryable', () async {
      final api = _api(
        (_) async => _awsError('TooManyRequestsException', 'Slow down', 429),
      );
      await expectLater(
        api.resendConfirmationCode(email: 'a@b.test'),
        throwsA(
          isA<ServiceUnavailableException>().having(
            (e) => e.isRetryable,
            'isRetryable',
            isTrue,
          ),
        ),
      );
    });

    test(
      'an unknown email is indistinguishable from a wrong password',
      () async {
        // Account enumeration defence: the message must not reveal that the
        // address is unregistered.
        final api = _api(
          (_) async =>
              _awsError('UserNotFoundException', 'User does not exist'),
        );
        await expectLater(
          api.resendConfirmationCode(email: 'nobody@example.test'),
          throwsA(
            isA<UnauthorisedException>().having(
              (e) => e.message,
              'message',
              'Incorrect email address or password.',
            ),
          ),
        );
      },
    );

    test('a server error is retryable', () async {
      final api = _api(
        (_) async => _awsError('InternalErrorException', 'boom', 500),
      );
      await expectLater(
        api.signUp(email: 'a@b.test', password: 'Passw0rd'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('a prefixed error type is matched on its final segment', () async {
      final api = _api(
        (_) async => http.Response(
          jsonEncode({
            '__type': 'UsernameExistsException',
            'message': 'exists',
          }),
          400,
        ),
      );
      await expectLater(
        api.signUp(email: 'a@b.test', password: 'Passw0rd'),
        throwsA(isA<AccountExistsException>()),
      );
    });

    test('a non-JSON error body does not crash the mapper', () async {
      final api = _api(
        (_) async => http.Response('<html>gateway timeout</html>', 504),
      );
      await expectLater(
        api.signUp(email: 'a@b.test', password: 'Passw0rd'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('a network failure is retryable', () async {
      final api = _api(
        (_) async => throw http.ClientException('no route to host'),
      );
      await expectLater(
        api.signUp(email: 'a@b.test', password: 'Passw0rd'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('a timeout is retryable', () async {
      final api = _api((_) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return http.Response('{}', 200);
      });
      await expectLater(
        api.signUp(email: 'a@b.test', password: 'Passw0rd'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });
  });
}
