abstract final class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://nonsmoking-api.onrender.com',
  );

  static bool get isConfigured => baseUrl.isNotEmpty;
}

