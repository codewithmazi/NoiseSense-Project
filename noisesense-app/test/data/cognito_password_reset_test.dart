import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noise_sense/data/auth/cognito_rest_api.dart';
import 'package:noise_sense/domain/errors.dart';

http.Response _awsError(String type, String message) => http.Response(
  jsonEncode({'__type': 'com.amazon.coral.service#$type', 'message': message}),
  400,
  headers: {'content-type': 'application/x-amz-json-1.1'},
);

CognitoRestApi _api(MockClientHandler handler) => CognitoRestApi(
  region: 'us-east-1',
  clientId: 'test-client-id',
  httpClient: MockClient(handler),
  timeout: const Duration(seconds: 2),
);

void main() {
  group('ForgotPassword', () {
    test('targets the right action with the client id and username', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return http.Response('{"CodeDeliveryDetails":{}}', 200);
      });

      await api.forgotPassword(email: 'test@example.test');

      expect(
        sent.headers['X-Amz-Target'],
        'AWSCognitoIdentityProviderService.ForgotPassword',
      );
      expect(jsonDecode(sent.body), {
        'ClientId': 'test-client-id',
        'Username': 'test@example.test',
      });
    });

    test(
      'an unregistered address completes exactly like a registered one',
      () async {
        // The enumeration defence, at the layer where it is enforced for a
        // client still on LEGACY existence errors. If this threw, the reset
        // screen would behave differently for real and invented addresses.
        final api = _api(
          (_) async => _awsError(
            'UserNotFoundException',
            'Username/client id combination not found.',
          ),
        );
        await expectLater(
          api.forgotPassword(email: 'nobody@example.test'),
          completes,
        );
      },
    );

    test(
      'only UserNotFound is swallowed; other failures still surface',
      () async {
        // The negative case for the test above. A blanket "always succeed"
        // would pass it too, and would hide throttling from the user.
        final api = _api(
          (_) async =>
              _awsError('LimitExceededException', 'Attempt limit exceeded.'),
        );
        await expectLater(
          api.forgotPassword(email: 'test@example.test'),
          throwsA(isA<ServiceUnavailableException>()),
        );
      },
    );

    test(
      'an account with no verified address is sent to confirmation',
      () async {
        final api = _api(
          (_) async => _awsError(
            'InvalidParameterException',
            'Cannot reset password for the user as there is no registered/verified email or phone_number',
          ),
        );
        await expectLater(
          api.forgotPassword(email: 'unconfirmed@example.test'),
          throwsA(isA<ConfirmationRequiredException>()),
        );
      },
    );

    test(
      'an unrelated InvalidParameter is not mistaken for that case',
      () async {
        final api = _api(
          (_) async => _awsError(
            'InvalidParameterException',
            '1 validation error detected',
          ),
        );
        await expectLater(
          api.forgotPassword(email: 'x'),
          throwsA(isA<InvalidRequestException>()),
        );
      },
    );
  });

  group('ConfirmForgotPassword', () {
    test('sends the code and new password', () async {
      late http.Request sent;
      final api = _api((request) async {
        sent = request;
        return http.Response('{}', 200);
      });

      await api.confirmForgotPassword(
        email: 'test@example.test',
        code: '123456',
        newPassword: 'N3wPassword',
      );

      expect(
        sent.headers['X-Amz-Target'],
        'AWSCognitoIdentityProviderService.ConfirmForgotPassword',
      );
      expect(jsonDecode(sent.body), {
        'ClientId': 'test-client-id',
        'Username': 'test@example.test',
        'ConfirmationCode': '123456',
        'Password': 'N3wPassword',
      });
    });

    test('an unregistered address reads as a wrong code, not a wrong password', () async {
      // "Incorrect email address or password" would make no sense on a screen
      // that asks for neither, and would hint that the address is the problem.
      final api = _api(
        (_) async => _awsError('UserNotFoundException', 'not found'),
      );
      await expectLater(
        api.confirmForgotPassword(
          email: 'nobody@example.test',
          code: '123456',
          newPassword: 'N3wPassword',
        ),
        throwsA(
          isA<InvalidRequestException>().having(
            (e) => e.message,
            'message',
            contains('code'),
          ),
        ),
      );
    });

    test('UserNotFound is not swallowed here, unlike ForgotPassword', () async {
      // Completing successfully would tell the user their password had been
      // changed when nothing had happened.
      final api = _api(
        (_) async => _awsError('UserNotFoundException', 'not found'),
      );
      await expectLater(
        api.confirmForgotPassword(
          email: 'nobody@example.test',
          code: '123456',
          newPassword: 'N3wPassword',
        ),
        throwsA(isA<NoiseSenseException>()),
      );
    });

    test('a wrong or expired code keeps the service wording', () async {
      for (final type in ['CodeMismatchException', 'ExpiredCodeException']) {
        final api = _api(
          (_) async => _awsError(
            type,
            'Invalid code provided, please request a code again.',
          ),
        );
        await expectLater(
          api.confirmForgotPassword(
            email: 'a@b.test',
            code: '000000',
            newPassword: 'N3wPassword',
          ),
          throwsA(
            isA<InvalidRequestException>().having(
              (e) => e.message,
              'message',
              'Invalid code provided, please request a code again.',
            ),
          ),
          reason: type,
        );
      }
    });

    test('a password the policy rejects is reported as such', () async {
      final api = _api(
        (_) async => _awsError(
          'InvalidPasswordException',
          'Password did not conform with policy',
        ),
      );
      await expectLater(
        api.confirmForgotPassword(
          email: 'a@b.test',
          code: '123456',
          newPassword: 'weak',
        ),
        throwsA(isA<InvalidRequestException>()),
      );
    });
  });

  test(
    'sign-in mapping of UserNotFound is unchanged by the reset work',
    () async {
      // Regression guard: the operation-aware mapping must not alter the
      // existing sign-up flow's messages.
      final api = _api(
        (_) async => _awsError('UserNotFoundException', 'not found'),
      );
      await expectLater(
        api.confirmSignUp(email: 'nobody@example.test', code: '123456'),
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
}
