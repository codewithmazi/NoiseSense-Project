import 'package:flutter/material.dart';

import 'screens/confirm_account_screen.dart';
import 'screens/home_shell.dart';
import 'screens/sign_in_screen.dart';
import 'theme/app_theme.dart';
import 'view_models/auth_view_model.dart';
import 'view_models/dashboard_view_model.dart';
import 'view_models/measurement_view_model.dart';

/// The application root, and the gate that decides which screen is on display.
class NoiseSenseApp extends StatefulWidget {
  const NoiseSenseApp({
    super.key,
    required this.auth,
    required this.createDashboard,
    required this.createMeasurement,
  });

  final AuthViewModel auth;

  /// Builds the measurement view model, given the dashboard that finished readings are handed to.
  final MeasurementViewModel Function(DashboardViewModel dashboard)
  createMeasurement;

  /// Builds the dashboard's view model.
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
    // `onHide` fires when no part of the app is visible.
    _lifecycle = AppLifecycleListener(
      onHide: () => _measurement?.onForegroundChanged(inForeground: false),
      // Returning to the app is a natural moment to retry uploads.
      onResume: () => _dashboard?.syncNow(),
    );
    widget.auth.addListener(_onAuthChanged);
    // Checks for a stored session.
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
      // Disposed on sign-out, dropping this user's readings and listeners.
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
          // Exhaustive switch: a new AuthStatus will not compile until handled.
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
    // Fallback only; the view models exist before this runs.
    if (dashboard == null || measurement == null) return const _SplashScreen();
    return HomeShell(
      dashboard: dashboard,
      measurement: measurement,
      email: widget.auth.signedInEmail,
      onSignOut: widget.auth.signOut,
    );
  }
}

/// Shown while the stored session is being checked.
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
