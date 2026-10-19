import 'dart:async';

import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';
import 'data/ml/yamnet_model.dart';
import 'domain/acoustics/source_classifier.dart';
import 'data/api/noise_api_client.dart';
import 'data/audio/android_measurement_service.dart';
import 'data/audio/microphone_pcm_source.dart';
import 'data/auth/cognito_auth_service.dart';
import 'data/auth/cognito_rest_api.dart';
import 'data/auth/secure_cognito_storage.dart';
import 'data/local/deferred_outbox_store.dart';
import 'data/local/sqlite_outbox_store.dart';
import 'domain/services/sync_engine.dart';
import 'presentation/app.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/view_models/auth_view_model.dart';
import 'presentation/view_models/dashboard_view_model.dart';
import 'presentation/view_models/measurement_view_model.dart';

/// Composition root: the one place where concrete implementations are chosen.
///
/// Every dependency is constructed here and passed downwards. Nothing below
/// this function reaches for a global, a singleton or a service locator, which
/// is why each view model can be built in a test with a fake repository and no
/// setup at all.
///
/// It is also where the layering becomes visible. This function names
/// `CognitoUserPool` and `NoiseApiClient`; no screen or view model does. The
/// AWS dependency is confined to the data layer and to these few lines, so the
/// lock-in mitigation argued for in the 602 report (Opara-Martins et al.,
/// 2016) is structural rather than aspirational: replacing the provider means
/// supplying different implementations of the same two interfaces here.
void main() {
  // Must come first. AndroidMeasurementService registers a platform-channel
  // handler when it is constructed, below, and that needs the engine bindings.
  // runApp() would create them, but only after this function has built every
  // dependency. Leaving this out crashed the first build on the S9+ before
  // anything was drawn; the unit tests could not catch it because the test
  // framework always initialises the bindings itself.
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig.fromEnvironment;

  // A build without its configuration cannot work, so it says so immediately
  // instead of presenting a sign-in screen that fails on the first request.
  if (!config.isComplete) {
    runApp(const _ConfigurationErrorApp(config: config));
    return;
  }

  // --- data layer -----------------------------------------------------------

  final pool = CognitoUserPool(
    config.userPoolId,
    config.userPoolClientId,
    // Without this the package keeps tokens in memory and the user signs in
    // again on every launch.
    storage: SecureCognitoStorage(),
  );

  final authService = CognitoAuthService(
    pool: pool,
    api: CognitoRestApi(
      region: config.region,
      clientId: config.userPoolClientId,
    ),
  );

  final api = NoiseApiClient(
    baseUrl: config.apiBaseUrl,
    // The same object supplies tokens and handles sessions, but the API client
    // only ever sees it as a TokenProvider, so it cannot sign the user out.
    tokens: authService,
  );

  // --- presentation layer ---------------------------------------------------

  final auth = AuthViewModel(authService);

  // One instance for the app's lifetime: it owns the platform channel's
  // handler, and a second instance would silently replace the first.
  final measurementService = AndroidMeasurementService();

  runApp(
    NoiseSenseApp(
      auth: auth,
      createDashboard: () {
        // Built per sign-in and disposed at sign-out, along with the
        // dashboard, so each user's queue is opened only while they are
        // signed in.
        final sync = SyncEngine(
          store: DeferredOutboxStore(() async {
            final userId = await authService.currentUserId();
            if (userId == null) {
              throw StateError('Outbox opened with nobody signed in');
            }
            return SqliteOutboxStore.open(ownerId: userId);
          }),
          remote: api,
        );
        final dashboard = DashboardViewModel(
          repository: api,
          sync: sync,
          // A rejected token ends the session through the auth view model,
          // so the dashboard never has to know what a 401 is.
          onSessionExpired: auth.sessionExpired,
        );
        // Sends anything left unsent from a previous session.
        unawaited(sync.start());
        return dashboard;
      },
      createMeasurement: (dashboard) => MeasurementViewModel(
        source: MicrophonePcmSource(),
        keepAlive: measurementService,
        loadClassifier: () async {
          final model = await YamnetModel.load();
          final mapping = await rootBundle.loadString(
            'assets/models/source_categories.json',
          );
          return WindowClassifier(
            model: model,
            categories: SourceCategoryMap.parse(mapping, model.labels),
          );
        },
        onReading: dashboard.submitReading,
      ),
    ),
  );
}

/// Shown when the build is missing its `--dart-define` values.
///
/// A deliberate screen rather than a thrown exception. The usual outcome of a
/// misconfigured build is an unexplained failure at the first network call,
/// which sends the developer looking in the wrong place. Naming the missing
/// keys turns a confusing session into a ten-second fix, and in the Learner
/// Lab, where identifiers change with every redeploy, this is the most likely
/// mistake there is.
class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoiseSense',
      theme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.settings_outlined,
                  color: AppTheme.error,
                  size: 40,
                ),
                const SizedBox(height: AppTheme.spaceMd),
                const Text(
                  'This build is not configured',
                  style: TextStyle(
                    color: AppTheme.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppTheme.spaceSm),
                Text(
                  'Rebuild with --dart-define for: '
                  '${config.missingKeys.join(', ')}.',
                  style: const TextStyle(
                    color: AppTheme.onSurfaceMuted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
