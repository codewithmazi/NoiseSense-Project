import '../domain/errors.dart';

/// Turns a domain failure into words a user can act on.
///
/// This translation lives in the presentation layer on purpose. The data layer
/// decides what *kind* of failure occurred; only the UI knows what a person
/// should be told about it, and the two are not the same. A timeout message
/// containing "POST /metrics timed out after 10000 ms" is the right thing in a
/// log and the wrong thing on a screen.
///
/// Because [NoiseSenseException] is `sealed`, the switch below is checked for
/// exhaustiveness at compile time. Adding a new failure type to the domain
/// therefore breaks this build until someone decides what the user should see,
/// which is the opposite of the usual outcome, where a new error quietly
/// falls through to a generic "something went wrong".
String userMessageFor(NoiseSenseException error) => switch (error) {
  // Already deliberately generic: sign-in reports a wrong password and an
  // unknown account identically so the API cannot be used to discover
  // which email addresses are registered.
  UnauthorisedException() => error.message,

  // Validation detail, documented as safe to display. Telling the user
  // which rule they broke is what makes the message useful; "invalid
  // input" is not actionable.
  InvalidRequestException() => error.message,

  AccountExistsException() => error.message,

  ConfirmationRequiredException() => error.message,

  // Replaced rather than shown. The user cannot act on a status code, but
  // can act on "check your connection", and this is also the one case
  // where retrying is genuinely worth suggesting.
  ServiceUnavailableException() =>
    'Could not reach NoiseSense. Check your connection, then try again.',

  // A contract mismatch between app and backend. There is nothing the
  // user can do, so they are told that plainly instead of being handed a
  // diagnostic. The original message still reaches the log.
  UnexpectedResponseException() => 'Something went wrong at our end. Your data is safe; please try again shortly.',
};
