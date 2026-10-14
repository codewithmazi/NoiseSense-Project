import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/errors.dart';
import '../../domain/models/exposure_settings.dart';
import '../../domain/models/noise_reading.dart';
import '../../domain/repositories/noise_repository.dart';
import 'token_provider.dart';

/// HTTPS client for the NoiseSense API (API Gateway HTTP API in front of the
/// ingest Lambda).
///
/// This is the only class in the app that knows the API's paths, JSON shapes
/// and status codes. Everything above it works with domain types and
/// [NoiseSenseException]s.
///
/// It makes exactly one attempt per call. Retrying is a policy decision that
/// belongs to the offline outbox, which knows whether a reading can wait;
/// this class only reports, through [NoiseSenseException.isRetryable],
/// whether a failure is worth retrying.
class NoiseApiClient implements NoiseRepository {
  NoiseApiClient({
    required String baseUrl,
    required this._tokens,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _http = httpClient ?? http.Client();

  final String _base;
  final TokenProvider _tokens;
  final http.Client _http;

  /// Upper bound for each request. Includes Lambda cold starts, so it must
  /// stay comfortably above the cold-start latency measured in experiment M2.
  final Duration timeout;

  @override
  Future<SubmitOutcome> submit(NoiseReading reading) async {
    final response = await _send(
      'POST',
      '/metrics',
      body: _readingToJson(reading),
    );
    // 201 = stored now; 200 = the service already had it (idempotent replay).
    return switch (response.statusCode) {
      201 => SubmitOutcome.stored,
      200 => SubmitOutcome.duplicate,
      final code => throw UnexpectedResponseException(
        'POST /metrics returned HTTP $code',
      ),
    };
  }

  @override
  Future<List<NoiseReading>> history() async {
    final json = _decodeObject(await _send('GET', '/history'), 'GET /history');
    final items = json['items'];
    if (items is! List) {
      throw const UnexpectedResponseException(
        "GET /history: 'items' is missing",
      );
    }
    return [for (final item in items) _readingFromJson(item)];
  }

  @override
  Future<ExposureSettings> settings() async {
    final json = _decodeObject(
      await _send('GET', '/settings'),
      'GET /settings',
    );
    return _settingsFromJson(json);
  }

  @override
  Future<ExposureSettings> updateThreshold(double thresholdDbA) async {
    // Validate before spending a network round trip on a doomed request.
    final problem = ExposureSettings.validateThreshold(thresholdDbA);
    if (problem != null) throw InvalidRequestException(problem);

    final json = _decodeObject(
      await _send('PUT', '/settings', body: {'thresholdDbA': thresholdDbA}),
      'PUT /settings',
    );
    return _settingsFromJson(json);
  }

  // ---------------------------------------------------------------- transport

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final token = await _tokens.bearerToken();
    if (token == null || token.isEmpty) {
      // Fail fast: a request without a token can only ever return 401.
      throw const UnauthorisedException('Not signed in');
    }

    final request = http.Request(method, Uri.parse('$_base$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ServiceUnavailableException(
        '$method $path timed out after ${timeout.inMilliseconds} ms',
      );
    } on http.ClientException catch (e) {
      throw ServiceUnavailableException('$method $path failed: ${e.message}');
    }

    _throwIfError(response);
    return response;
  }

  /// Maps an HTTP failure to its meaning.
  ///
  /// 429 and 5xx are retryable. This matters under load: the Learner Lab caps
  /// Lambda at 10 concurrent executions, so a burst of submissions can be
  /// throttled, and a throttled reading must wait in the outbox rather than
  /// be thrown away.
  void _throwIfError(http.Response response) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;
    final message = _serverMessage(response) ?? 'HTTP $code';
    if (code == 401 || code == 403) throw UnauthorisedException(message);
    if (code == 429 || code >= 500) throw ServiceUnavailableException(message);
    if (code >= 400) throw InvalidRequestException(message);
    throw UnexpectedResponseException('Unexpected HTTP $code');
  }

  // ----------------------------------------------------------------- mapping

  /// Wire format for a reading. The client always supplies the timestamp,
  /// because the backend uses it as the idempotency key for offline replay.
  static Map<String, Object?> _readingToJson(NoiseReading r) => {
    'timestamp': _formatTimestamp(r.timestamp),
    'dbA': r.dbA,
    if (r.laeq != null) 'laeq': r.laeq,
    if (r.classLabel != null) 'classLabel': r.classLabel,
    if (r.confidence != null) 'confidence': r.confidence,
  };

  /// Second-precision UTC ISO 8601, matching the backend's own format so that
  /// client- and server-generated timestamps sort consistently.
  static String _formatTimestamp(DateTime utc) =>
      '${utc.toUtc().toIso8601String().split('.').first}Z';

  /// Builds a reading from one history item.
  ///
  /// Only public fields are read. The response also carries internal storage
  /// keys (`PK`, `SK`), which are deliberately ignored so the app does not
  /// come to depend on how the backend stores data.
  static NoiseReading _readingFromJson(Object? item) {
    if (item is! Map<String, dynamic>) {
      throw const UnexpectedResponseException('History item is not an object');
    }
    final rawTimestamp = item['timestamp'];
    final timestamp = rawTimestamp is String
        ? DateTime.tryParse(rawTimestamp)
        : null;
    if (timestamp == null) {
      throw UnexpectedResponseException(
        "History item has invalid 'timestamp': $rawTimestamp",
      );
    }
    final dbA = _optionalNum(item, 'dbA');
    if (dbA == null) {
      throw const UnexpectedResponseException("History item is missing 'dbA'");
    }
    final label = item['classLabel'];
    if (label != null && label is! String) {
      throw const UnexpectedResponseException("'classLabel' is not text");
    }
    try {
      return NoiseReading(
        timestamp: timestamp,
        dbA: dbA,
        laeq: _optionalNum(item, 'laeq'),
        classLabel: label as String?,
        confidence: _optionalNum(item, 'confidence'),
      );
    } on ArgumentError catch (e) {
      // The service returned a value no real reading could have.
      throw UnexpectedResponseException('History item rejected: ${e.message}');
    }
  }

  static ExposureSettings _settingsFromJson(Map<String, dynamic> json) {
    final threshold = _optionalNum(json, 'thresholdDbA');
    if (threshold == null) {
      throw const UnexpectedResponseException(
        "Settings are missing 'thresholdDbA'",
      );
    }
    final updatedAt = json['updatedAt'];
    return ExposureSettings(
      thresholdDbA: threshold,
      // The PUT response omits the flag; a value the user just set is never
      // the default.
      isDefault: json['isDefault'] == true,
      updatedAt: updatedAt is String ? DateTime.tryParse(updatedAt) : null,
    );
  }

  static double? _optionalNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw UnexpectedResponseException("'$key' is not a number: $value");
  }

  static Map<String, dynamic> _decodeObject(
    http.Response response,
    String what,
  ) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall through to the error below.
    }
    throw UnexpectedResponseException('$what did not return a JSON object');
  }

  static String? _serverMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } on FormatException {
      // Not JSON, e.g. an HTML error page from a proxy.
    }
    return null;
  }
}
