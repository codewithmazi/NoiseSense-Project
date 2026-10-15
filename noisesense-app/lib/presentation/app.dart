import 'package:flutter/material.dart';

import 'screens/confirm_account_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/sign_in_screen.dart';
import 'theme/app_theme.dart';
import 'view_models/auth_view_model.dart';
import 'view_models/dashboard_view_model.dart';
import 'view_models/measurement_view_model.dart';

/// The application root, and the gate that decides which screen is on display.
///
/// Routing is driven by [AuthStatus] rather than by screens pushing one
/// another. The practical consequence is that there is no way to reach the
/// dashboard without a session, because the dashboard is only built in the
/// [AuthStatus.signedIn] branch. Enforcing that structurally is stronger than
/// enforcing it with a check on each protected screen, which only holds for as
/// long as nobody forgets one.
///
/// It also handles expiry correctly without extra work: when the service
/// refuses a stored token, the dashboard view model reports it, the status
/// changes, and the user is returned to sign-in from wherever they were.
class NoiseSenseApp extends StatefulWidget {
  const NoiseSenseApp({
    super.key,
    required this.auth,
    required this.createDashboard,
    required this.createMeasurement,
  });

  final AuthViewModel auth;

  /// Builds the measurement view model, given the dashboard that finished
  /// readings are handed to. Created and disposed with the dashboard, so the
  /// microphone is released on sign-out.
  final MeasurementViewModel Function(DashboardViewModel dashboard)
  createMeasurement;

  /// Builds the dashboard's view model.
  ///
  /// A factory rather than an instance, because the view model holds one
  /// user's readings. Building it at startup and reusing it would risk showing
  /// the previous user's data to the next one after a sign-out; building it on
  /// sign-in makes that impossible.
  final DashboardViewModel Function() createDashboard;

  @override
  State<NoiseSenseApp> createState() => _NoiseSenseAppState();
}

class _NoiseSenseAppState extends State<NoiseSenseApp> {
  DashboardViewModel? _dashboard;
  MeasurementViewModel? _measurement;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // `onHide` fires when no part of the app is visible. Measuring stops
    // there, because Android hands a backgrounded app silence instead of
    // audio (see MeasurementViewModel).
    _lifecycle = AppLifecycleListener(
      onHide: () => _measurement?.onForegroundChanged(inForeground: false),
    );
    widget.auth.addListener(_onAuthChanged);
    // Checks for a stored session. Until it answers, the status is
    // `unknown` and the splash is shown.
    widget.auth.restoreSession();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.auth.removeListener(_onAuthChanged);
    _measurement?.dispose();
    _dashboard?.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    final signedIn = widget.auth.status == AuthStatus.signedIn;
    if (signedIn && _dashboard == null) {
      final dashboard = widget.createDashboard();
      _dashboard = dashboard;
      _measurement = widget.createMeasurement(dashboard);
    } else if (!signedIn && _dashboard != null) {
      // Disposed on sign-out, which releases its listeners and drops the
      // readings it held. Keeping it alive would leave one user's data in
      // memory behind the next user's sign-in screen. Measurement goes
      // first, so the microphone is never left running for nobody.
      _measurement?.dispose();
      _measurement = null;
      _dashboard!.dispose();
      _dashboard = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoiseSense',
      theme: AppTheme.dark,
      home: ListenableBuilder(
        listenable: widget.auth,
        builder: (context, _) {
          // Exhaustive over the enum, so adding a state to AuthStatus will
          // not compile until this decides what to show for it.
          return switch (widget.auth.status) {
            AuthStatus.unknown => const _SplashScreen(),
            AuthStatus.signedOut => SignInScreen(auth: widget.auth),
            AuthStatus.awaitingConfirmation => ConfirmAccountScreen(
              auth: widget.auth,
            ),
            AuthStatus.signedIn => _dashboardOrSplash(),
          };
        },
      ),
    );
  }

  Widget _dashboardOrSplash() {
    final dashboard = _dashboard;
    final measurement = _measurement;
    // The listener creates the view models before this runs, so the fallback
    // is unreachable in practice. It is here so a future reordering degrades
    // to a splash rather than to a null dereference.
    if (dashboard == null || measurement == null) return const _SplashScreen();
    return DashboardScreen(
      viewModel: dashboard,
      measurement: measurement,
      onSignOut: widget.auth.signOut,
    );
  }
}

/// Shown while the stored session is being checked.
///
/// Branded rather than a bare spinner, because this is the first thing the
/// user sees and the check can include a token refresh over a slow connection.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NoiseSense',
              style: TextStyle(
                color: AppTheme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: AppTheme.spaceLg),
            SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
