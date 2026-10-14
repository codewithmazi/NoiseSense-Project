/// Failures the rest of the app can reason about without knowing about HTTP.
///
/// The data layer translates transport details (status codes, socket errors,
/// timeouts) into these types, so screens and the offline outbox decide what
/// to do from meaning rather than from raw HTTP. The class is `sealed`, so a
/// `switch` over it must handle every case or the code will not compile.
sealed class NoiseSenseException implements Exception {
  const NoiseSenseException(this.message);

  /// Human-readable detail, suitable for logs and, where noted, for the UI.
  final String message;

  /// Whether retrying the same operation later might succeed. The outbox uses
  /// this to decide between "keep and retry" and "give up and tell the user".
  bool get isRetryable => false;

  @override
  String toString() => '$runtimeType: $message';
}

/// No valid session: the user must sign in again. Not retryable as-is.
final class UnauthorisedException extends NoiseSenseException {
  const UnauthorisedException(super.message);
}

/// The request was rejected as invalid. [message] is safe to show the user.
final class InvalidRequestException extends NoiseSenseException {
  const InvalidRequestException(super.message);
}

/// The service could not be reached or was overloaded: network failure,
/// timeout, throttling (429) or a server error (5xx). Retrying later may work.
final class ServiceUnavailableException extends NoiseSenseException {
  const ServiceUnavailableException(super.message);

  @override
  bool get isRetryable => true;
}

/// The service replied with something the app does not understand. This
/// points to a contract mismatch between app and backend, so it fails loudly.
final class UnexpectedResponseException extends NoiseSenseException {
  const UnexpectedResponseException(super.message);
}

/// The account exists but its email address has never been confirmed.
///
/// A distinct type because it is not really an error: it tells the UI to send
/// the user to the confirmation screen rather than show a failure.
final class ConfirmationRequiredException extends NoiseSenseException {
  const ConfirmationRequiredException(super.message);
}

/// Someone has already registered with this email address.
final class AccountExistsException extends NoiseSenseException {
  const AccountExistsException(super.message);
}
