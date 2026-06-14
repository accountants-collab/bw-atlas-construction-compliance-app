enum AppEnvironment { development, staging, production }

class AppEnvironmentConfig {
  final AppEnvironment environment;
  final String appTitle;
  final String apiBaseUrl;
  final String authConfigName;
  final String storageConfigName;
  final String inviteBaseUrl;
  final bool verboseLogging;
  final String hiveNamespace;

  const AppEnvironmentConfig({
    required this.environment,
    required this.appTitle,
    required this.apiBaseUrl,
    required this.authConfigName,
    required this.storageConfigName,
    required this.inviteBaseUrl,
    required this.verboseLogging,
    required this.hiveNamespace,
  });

  bool get isProduction => environment == AppEnvironment.production;
  bool get isStaging => environment == AppEnvironment.staging;
  bool get isDevelopment => environment == AppEnvironment.development;
  bool get showEnvironmentBadge => !isProduction;
}

class AppEnvironmentRuntime {
  // Public repository note: endpoint values are placeholders.
  static const String _rawEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'staging',
  );

  static final AppEnvironmentConfig current = _resolve(_rawEnv);

  static AppEnvironmentConfig _resolve(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'prod':
      case 'production':
        return const AppEnvironmentConfig(
          environment: AppEnvironment.production,
          appTitle: 'BW Atlas',
          apiBaseUrl: 'https://api.example.com',
          authConfigName: 'auth-production',
          storageConfigName: 'storage-production',
          inviteBaseUrl: 'https://app.example.com/#',
          verboseLogging: false,
          hiveNamespace: 'prod',
        );
      case 'dev':
      case 'development':
        return const AppEnvironmentConfig(
          environment: AppEnvironment.development,
          appTitle: 'BW Atlas (Dev)',
          apiBaseUrl: 'https://dev-api.example.com',
          authConfigName: 'auth-development',
          storageConfigName: 'storage-development',
          inviteBaseUrl: 'https://dev-app.example.com/#',
          verboseLogging: true,
          hiveNamespace: 'dev',
        );
      case 'staging':
      case 'test':
      default:
        return const AppEnvironmentConfig(
          environment: AppEnvironment.staging,
          appTitle: 'BW Atlas (Staging)',
          apiBaseUrl: 'https://staging-api.example.com',
          authConfigName: 'auth-staging',
          storageConfigName: 'storage-staging',
          inviteBaseUrl: 'https://staging-app.example.com/#',
          verboseLogging: true,
          hiveNamespace: 'staging',
        );
    }
  }
}
