import 'package:shared_preferences/shared_preferences.dart';

/// Persists the viewer's detected country for geo-based currency display.
class ViewerLocationService {
  static const _countryCodeKey = 'viewer_country_code';
  static const _countryNameKey = 'viewer_country_name';

  static Future<void> saveCountry({
    required String? countryCode,
    String? countryName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (countryCode != null && countryCode.trim().isNotEmpty) {
      await prefs.setString(_countryCodeKey, countryCode.trim().toUpperCase());
    }
    if (countryName != null && countryName.trim().isNotEmpty) {
      await prefs.setString(_countryNameKey, countryName.trim());
    }
  }

  static Future<String?> getCountryCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_countryCodeKey);
  }

  static Future<String?> getCountryName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_countryNameKey);
  }
}
