import 'package:shared_preferences/shared_preferences.dart';

/// Single cached [SharedPreferences] instance.
///
/// Concurrent `getInstance()` calls on Windows can hang or stall startup;
/// route all prefs access through here.
class PrefsService {
  PrefsService._();

  static Future<SharedPreferences>? _future;

  static Future<SharedPreferences> get instance {
    _future ??= SharedPreferences.getInstance().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw StateError('SharedPreferences timed out'),
    );
    return _future!;
  }
}
