import '../domain/errors.dart';

/// Turns a domain failure into words a user can act on.
String userMessageFor(NoiseSenseException error) => switch (error) {
  // Already generic; shown as is.
  UnauthorisedException() => error.message,

  // Validation detail, documented as safe to display.
  InvalidRequestException() => error.message,

  AccountExistsException() => error.message,

  ConfirmationRequiredException() => error.message,

  // Replaced with a generic message rather than shown.
  ServiceUnavailableException() =>
    'Could not reach NoiseSense. Check your connection, then try again.',

  // App/backend contract mismatch.
  UnexpectedResponseException() => 'Something went wrong at our end. Your data is safe; please try again shortly.',
};
