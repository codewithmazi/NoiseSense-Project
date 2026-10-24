import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noise_sense/domain/errors.dart';
import 'package:noise_sense/domain/repositories/auth_repository.dart';
import 'package:noise_sense/presentation/screens/sign_in_screen.dart';
import 'package:noise_sense/presentation/theme/app_theme.dart';
import 'package:noise_sense/presentation/view_models/auth_view_model.dart';

/// Widget tests for the sign-in screen.
class _StubAuthRepository implements AuthRepository {
  NoiseSenseException? nextError;
  int signInCalls = 0;
  Completer<void>? gate;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    await gate?.future;
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> confirmSignUp({
    required String email,
    required String code,
  }) async {}

  @override
  Future<void> resendConfirmationCode({required String email}) async {}

  @override
  Future<void> requestPasswordReset({required String email}) async {}

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> hasValidSession() async => false;

  @override
  Future<String?> currentUserId() async => null;

  @override
  Future<String?> currentEmail() async => null;
}

void main() {
  late _StubAuthRepository repository;
  late AuthViewModel auth;

  setUp(() {
    repository = _StubAuthRepository();
    auth = AuthViewModel(repository);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SignInScreen(auth: auth),
      ),
    );
  }

  Finder fieldLabelled(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

  testWidgets('both fields carry autofill hints, so a password manager can '
      'fill them (WCAG 2.2 SC 3.3.8)', (tester) async {
    await pumpScreen(tester);

    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    final hints = fields
        .expand((f) => f.autofillHints ?? const <String>[])
        .toSet();

    expect(hints, contains(AutofillHints.email));
    expect(hints, contains(AutofillHints.password));
  });

  testWidgets('the fields are inside an AutofillGroup, so both are filled '
      'together', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(AutofillGroup), findsOneWidget);
  });

  testWidgets('nothing blocks pasting into the password field', (tester) async {
    // Paste must not be disabled.
    await pumpScreen(tester);
    final password = tester.widget<EditableText>(
      find.byType(EditableText).last,
    );
    expect(password.enableInteractiveSelection, isTrue);
    expect(password.obscureText, isTrue, reason: 'hidden by default');
  });

  testWidgets('the password can be revealed, and is hidden to begin with', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
    // The toggle names its new action, not its current state.
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets(
    'submitting an empty form validates locally and makes no request',
    (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(
        repository.signInCalls,
        0,
        reason: 'no round trip for a local error',
      );
    },
  );

  testWidgets('a malformed address is explained next to the field', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.enterText(fieldLabelled('Email address'), 'not-an-address');
    await tester.enterText(fieldLabelled('Password'), 'Passw0rd');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(
      find.text('That does not look like an email address.'),
      findsOneWidget,
    );
    expect(repository.signInCalls, 0);
  });

  testWidgets('a valid form reaches the repository', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(fieldLabelled('Email address'), 'ron@example.com');
    await tester.enterText(fieldLabelled('Password'), 'Passw0rd');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(repository.signInCalls, 1);
  });

  testWidgets('a failure is shown in a live region, so a screen reader '
      'announces it (WCAG 2.2 SC 4.1.3)', (tester) async {
    repository.nextError = const UnauthorisedException(
      'Incorrect email address or password.',
    );
    await pumpScreen(tester);

    await tester.enterText(fieldLabelled('Email address'), 'ron@example.com');
    await tester.enterText(fieldLabelled('Password'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email address or password.'), findsOneWidget);

    final semantics = tester.getSemantics(
      find.text('Incorrect email address or password.'),
    );
    expect(
      semantics.flagsCollection.isLiveRegion,
      isTrue,
      reason: 'a failure the user cannot see is a failure they cannot act on',
    );
  });

  testWidgets('the error carries an icon as well as colour (SC 1.4.1)', (
    tester,
  ) async {
    repository.nextError = const UnauthorisedException(
      'Incorrect email address or password.',
    );
    await pumpScreen(tester);
    await tester.enterText(fieldLabelled('Email address'), 'ron@example.com');
    await tester.enterText(fieldLabelled('Password'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a second tap while the request is in flight is ignored', (
    tester,
  ) async {
    // Prevents the duplicate submission rather than relying on the user not to try.
    repository.gate = Completer<void>();
    await pumpScreen(tester);
    await tester.enterText(fieldLabelled('Email address'), 'ron@example.com');
    await tester.enterText(fieldLabelled('Password'), 'Passw0rd');

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    // The label is replaced by a spinner, so the wait is visible.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('Sign in'),
      ),
      findsNothing,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    repository.gate!.complete();
    await tester.pumpAndSettle();

    expect(repository.signInCalls, 1);
  });

  testWidgets('the whole screen scrolls, so a raised font size cannot overflow '
      'it (SC 1.4.4)', (tester) async {
    // Flutter reports an overflow as a rendering error.
    tester.view.physicalSize = const Size(411 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          // Android allows up to 2.0 in accessibility settings.
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: SignInScreen(auth: auth),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('a forgotten password can be reset, starting with the address '
      'already typed', (tester) async {
    // Recognition rather than recall: the user does not type the address twice.
    await pumpScreen(tester);
    await tester.enterText(fieldLabelled('Email address'), 'ron@example.com');
    await tester.tap(find.text('Forgotten your password?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('ron@example.com'), findsOneWidget);
  });

  testWidgets('the reset moves from requesting a code to entering it', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Forgotten your password?'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'ron@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset code'));
    await tester.pumpAndSettle();

    expect(find.text('Reset code'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.textContaining('If an account uses'), findsOneWidget);
  });

  testWidgets('a completed reset returns to sign-in with the address filled', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Forgotten your password?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'ron@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset code'));
    await tester.pumpAndSettle();

    await tester.enterText(fieldLabelled('Reset code'), '123456');
    await tester.enterText(fieldLabelled('New password'), 'N3wPassword');
    await tester.tap(find.widgetWithText(FilledButton, 'Set new password'));
    await tester.pumpAndSettle();

    expect(find.text('Reset password'), findsNothing, reason: 'popped');
    expect(find.text('ron@example.com'), findsOneWidget);
    expect(find.textContaining('Password changed'), findsOneWidget);
  });

  testWidgets('a route to account creation is offered', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Create an account'), findsOneWidget);
  });
}
