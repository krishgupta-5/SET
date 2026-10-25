/// Non-secret build configuration.
///
/// The app ships NO secrets: Telegram, Gemini and Groq are only called by the
/// backend. The only setting is the backend URL, overridable at build time:
///
///   flutter run --dart-define=API_URL=http://10.0.2.2:8000
class AppConfig {
  AppConfig._();

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://set-iamf.onrender.com',
  );
}
