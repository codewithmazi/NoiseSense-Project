import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noise_sense/data/api/noise_api_client.dart';
import 'package:noise_sense/data/api/token_provider.dart';
import 'package:noise_sense/domain/errors.dart';
import 'package:noise_sense/domain/models/noise_reading.dart';
import 'package:noise_sense/domain/repositories/noise_repository.dart';

/// Stands in for Cognito, so these tests need no network and no AWS account.
class _FakeTokens implements TokenProvider {
  _FakeTokens(this.token);
  final String? token;

  @override
  Future<String?> bearerToken() async => token;
}

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

NoiseApiClient _client(
  MockClientHandler handler, {
  String? token = 'id-token-123',
  Duration timeout = const Duration(seconds: 5),
}) => NoiseApiClient(
  baseUrl: 'https://api.example.test/', // trailing slash is trimmed
  tokens: _FakeTokens(token),
  httpClient: MockClient(handler),
  timeout: timeout,
);

final _reading = NoiseReading(
  timestamp: DateTime.utc(2026, 10, 9, 14, 30, 5, 999),
  dbA: 68.4,
  laeq: 65.1,
  classLabel: 'traffic',
  confidence: 0.82,
);

void main() {
  group('submit', () {
    test(
      'sends the ID token, client timestamp and classifier fields',
      () async {
        late http.Request sent;
        final client = _client((request) async {
          sent = request;
          return _json({'message': 'stored'}, 201);
        });

        expect(await client.submit(_reading), SubmitOutcome.stored);

        expect(sent.method, 'POST');
        expect(sent.url.toString(), 'https://api.example.test/metrics');
        expect(sent.headers['Authorization'], 'Bearer id-token-123');
        expect(sent.headers['Content-Type'], startsWith('application/json'));
        expect(jsonDecode(sent.body), {
          'timestamp': '2026-10-09T14:30:05Z',
          'dbA': 68.4,
          'laeq': 65.1,
          'classLabel': 'traffic',
          'confidence': 0.82,
        });
      },
    );

    test('omits optional fields that are absent', () async {
      late http.Request sent;
      final client = _client((request) async {
        sent = request;
        return _json({'message': 'stored'}, 201);
      });

      await client.submit(
        NoiseReading(timestamp: DateTime.utc(2026, 10, 9), dbA: 55),
      );

      expect(jsonDecode(sent.body), {
        'timestamp': '2026-10-09T00:00:00Z',
        'dbA': 55.0,
      });
    });

    test('a 200 replay counts as a duplicate, not a failure', () async {
      final client = _client(
        (_) async => _json({'message': 'duplicate ignored'}, 200),
      );
      expect(await client.submit(_reading), SubmitOutcome.duplicate);
    });
  });

  group('error mapping', () {
    test('no token fails fast without making a request', () async {
      var called = false;
      final client = _client((_) async {
        called = true;
        return _json({}, 200);
      }, token: null);

      await expectLater(
        client.submit(_reading),
        throwsA(isA<UnauthorisedException>()),
      );
      expect(called, isFalse);
    });

    test('401 means the user must sign in again', () async {
      final client = _client(
        (_) async => _json({'message': 'Unauthorized'}, 401),
      );
      await expectLater(
        client.history(),
        throwsA(
          isA<UnauthorisedException>().having(
            (e) => e.isRetryable,
            'isRetryable',
            isFalse,
          ),
        ),
      );
    });

    test("400 surfaces the server's message for the user", () async {
      final client = _client(
        (_) async =>
            _json({'message': "Field 'dbA' (number) is required"}, 400),
      );
      await expectLater(
        client.submit(_reading),
        throwsA(
          isA<InvalidRequestException>().having(
            (e) => e.message,
            'message',
            "Field 'dbA' (number) is required",
          ),
        ),
      );
    });

    for (final code in [429, 500, 503]) {
      test('$code is retryable, so the outbox keeps the reading', () async {
        final client = _client((_) async => _json({'message': 'busy'}, code));
        await expectLater(
          client.submit(_reading),
          throwsA(
            isA<ServiceUnavailableException>().having(
              (e) => e.isRetryable,
              'isRetryable',
              isTrue,
            ),
          ),
        );
      });
    }

    test('a network failure is retryable', () async {
      final client = _client(
        (_) async => throw http.ClientException('connection refused'),
      );
      await expectLater(
        client.history(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('a timeout is retryable', () async {
      final client = _client((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _json({'count': 0, 'items': []}, 200);
      }, timeout: const Duration(milliseconds: 20));
      await expectLater(
        client.history(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('a non-JSON success body fails loudly', () async {
      final client = _client(
        (_) async => http.Response('<html>proxy error</html>', 200),
      );
      await expectLater(
        client.history(),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });
  });

  group('history', () {
    test('parses readings and ignores internal storage keys', () async {
      final client = _client(
        (_) async => _json({
          'count': 2,
          'items': [
            {
              'PK': 'USER#abc',
              'SK': 'TS#2026-10-09T14:30:05Z',
              'type': 'reading',
              'timestamp': '2026-10-09T14:30:05Z',
              'dbA': 68.4,
              'laeq': 65.1,
              'classLabel': 'traffic',
              'confidence': 0.82,
            },
            {'timestamp': '2026-10-09T14:29:00Z', 'dbA': 52},
          ],
        }, 200),
      );

      final readings = await client.history();

      expect(readings, hasLength(2));
      expect(readings.first, _reading);
      expect(readings.last.laeq, isNull);
      expect(readings.last.classLabel, isNull);
      expect(readings.last.dbA, 52.0);
    });

    test(
      'a malformed item fails loudly rather than being silently dropped',
      () async {
        final client = _client(
          (_) async => _json({
            'items': [
              {'timestamp': '2026-10-09T14:30:05Z', 'dbA': 'loud'},
            ],
          }, 200),
        );
        await expectLater(
          client.history(),
          throwsA(isA<UnexpectedResponseException>()),
        );
      },
    );
  });

  group('settings', () {
    test('reports whether the threshold is the service default', () async {
      final client = _client(
        (_) async => _json({'thresholdDbA': 70, 'isDefault': true}, 200),
      );
      final settings = await client.settings();
      expect(settings.thresholdDbA, 70.0);
      expect(settings.isDefault, isTrue);
    });

    test(
      'an out-of-range threshold is rejected locally, before any request',
      () async {
        var called = false;
        final client = _client((_) async {
          called = true;
          return _json({}, 200);
        });
        await expectLater(
          client.updateThreshold(5),
          throwsA(isA<InvalidRequestException>()),
        );
        expect(called, isFalse);
      },
    );

    test('a valid threshold is sent with PUT and the result parsed', () async {
      late http.Request sent;
      final client = _client((request) async {
        sent = request;
        return _json({
          'message': 'updated',
          'thresholdDbA': 62.5,
          'updatedAt': '2026-10-09T15:00:00Z',
        }, 200);
      });

      final settings = await client.updateThreshold(62.5);

      expect(sent.method, 'PUT');
      expect(jsonDecode(sent.body), {'thresholdDbA': 62.5});
      expect(settings.thresholdDbA, 62.5);
      expect(settings.isDefault, isFalse);
      expect(settings.updatedAt, DateTime.utc(2026, 10, 9, 15));
    });
  });
}
