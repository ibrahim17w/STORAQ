// lib/services/analytics_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../providers/locale_provider.dart';

class AnalyticsService {
  static const _cacheKey = 'analytics_dashboard_cache';
  static const _cacheTimeKey = 'analytics_dashboard_cache_time';

  static Future<Map<String, dynamic>> fetchDashboard({int days = 7}) async {
    try {
      final lang = localeNotifier.value.languageCode;
      final response = await ApiService.authGet(
        '/analytics/dashboard?days=$days&lang=$lang',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _cacheData(data);
        return data;
      }
      throw Exception('Failed to load analytics');
    } catch (e) {
      final cached = await getCachedDashboard();
      if (cached != null) return cached;
      rethrow;
    }
  }

  static Future<void> _cacheData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(data));
    await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
  }

  static Future<Map<String, dynamic>?> getCachedDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<DateTime?> getCacheTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheTimeKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> trackStoreVisit(int storeId) async {
    try {
      await ApiService.postWithTimeout(
        '${ApiService.baseUrl}/api/stores/$storeId/visit',
        headers: await ApiService.authHeaders,
      );
    } catch (_) {}
  }
}
