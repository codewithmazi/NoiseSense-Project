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

/// Composition root: constructs and wires concrete dependencies.
void main() {
  // Required before registering platform-channel handlers.
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig.fromEnvironment;

  // Fail fast if required build configuration is missing.
  if (!config.isComplete) {
    runApp(const _ConfigurationErrorApp(config: config));
    return;
  }

  // --- data layer -----------------------------------------------------------

  final pool = CognitoUserPool(
    config.userPoolId,
    config.userPoolClientId,
    // Persist tokens across launches.
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
    // API client only sees authService as a TokenProvider.
    tokens: authService,
  );

  // --- presentation layer ---------------------------------------------------

  final auth = AuthViewModel(authService);

  // Single instance: owns the platform-channel handler.
  final measurementService = AndroidMeasurementService();

  runApp(
    NoiseSenseApp(
      auth: auth,
      createDashboard: () {
        // Built per sign-in and disposed at sign-out.
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
          // Ends the session when a token is rejected.
          onSessionExpired: auth.sessionExpired,
        );
        // Sync any unsent readings from a previous session.
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

/// Shown when required `--dart-define` values are missing.
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
