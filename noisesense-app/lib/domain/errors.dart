/// Domain-level failures, independent of HTTP details.
sealed class NoiseSenseException implements Exception {
  const NoiseSenseException(this.message);

  /// Human-readable detail for logs and, where appropriate, the UI.
  final String message;

  /// Whether retrying later might succeed.
  bool get isRetryable => false;

  @override
  String toString() => '$runtimeType: $message';
}

/// No valid session; the user must sign in again.
final class UnauthorisedException extends NoiseSenseException {
  const UnauthorisedException(super.message);
}

/// Request rejected as invalid; [message] is user-safe.
final class InvalidRequestException extends NoiseSenseException {
  const InvalidRequestException(super.message);
}

/// Service unreachable, overloaded, throttled, or returned a server error.
final class ServiceUnavailableException extends NoiseSenseException {
  const ServiceUnavailableException(super.message);

  @override
  bool get isRetryable => true;
}

/// Service returned an unrecognised response.
final class UnexpectedResponseException extends NoiseSenseException {
  const UnexpectedResponseException(super.message);
}

/// Account exists but its email is unconfirmed.
final class ConfirmationRequiredException extends NoiseSenseException {
  const ConfirmationRequiredException(super.message);
}

/// An account already exists for this email address.
final class AccountExistsException extends NoiseSenseException {
  const AccountExistsException(super.message);
}
