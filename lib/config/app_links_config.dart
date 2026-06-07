/// Public URLs embedded in store QR codes (receipt + store owner QR).
class AppLinksConfig {
  /// HTTPS base used in QR codes (must match backend hosting /s/:id).
  /// Override at build: --dart-define=PUBLIC_WEB_BASE=https://your-domain.com
  static const String publicWebBase = String.fromEnvironment(
    'PUBLIC_WEB_BASE',
    defaultValue: 'https://storaq-baug.onrender.com',
  );

  /// App store / download page when the app is not installed.
  static const String downloadUrl = String.fromEnvironment(
    'APP_DOWNLOAD_URL',
    defaultValue: 'https://storaq.app/download',
  );

  static const String deepLinkScheme = 'storaq';
}
