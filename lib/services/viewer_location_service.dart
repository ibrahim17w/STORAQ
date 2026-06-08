import 'package:shared_preferences/shared_preferences.dart';

/// Persists the viewer's detected location so geo-filtered features
/// (sponsored campaigns, currency display, etc.) work on the very next
/// cold start instead of waiting for GPS + reverse-geocode every time.
class ViewerLocationService {
  static const _countryCodeKey = 'viewer_country_code';
  static const _countryNameKey = 'viewer_country_name';
  static const _cityKey = 'viewer_city';
  static const _cityIdKey = 'viewer_city_id';
  static const _villageKey = 'viewer_village';
  static const _villageIdKey = 'viewer_village_id';
  static const _latKey = 'viewer_lat';
  static const _lngKey = 'viewer_lng';

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

  static Future<void> saveLocation({
    String? countryCode,
    String? countryName,
    String? city,
    String? cityId,
    String? village,
    String? villageId,
    double? lat,
    double? lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> setStr(String key, String? value) async {
      if (value != null && value.trim().isNotEmpty) {
        await prefs.setString(key, value.trim());
      }
    }

    if (countryCode != null && countryCode.trim().isNotEmpty) {
      await prefs.setString(_countryCodeKey, countryCode.trim().toUpperCase());
    }
    await setStr(_countryNameKey, countryName);
    await setStr(_cityKey, city);
    await setStr(_cityIdKey, cityId);
    await setStr(_villageKey, village);
    await setStr(_villageIdKey, villageId);
    if (lat != null) await prefs.setDouble(_latKey, lat);
    if (lng != null) await prefs.setDouble(_lngKey, lng);
  }

  static Future<String?> getCountryCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_countryCodeKey);
  }

  static Future<String?> getCountryName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_countryNameKey);
  }

  static Future<Map<String, dynamic>> getLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'country_code': prefs.getString(_countryCodeKey),
      'country': prefs.getString(_countryNameKey),
      'city': prefs.getString(_cityKey),
      'city_id': prefs.getString(_cityIdKey),
      'village': prefs.getString(_villageKey),
      'village_id': prefs.getString(_villageIdKey),
      'lat': prefs.getDouble(_latKey),
      'lng': prefs.getDouble(_lngKey),
    };
  }
}
