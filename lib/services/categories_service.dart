import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'offline_service.dart';

class CategoriesService {
  static Future<List<dynamic>> fetchCategories() async {
    // Always try server first when online
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = !connectivity.contains(ConnectivityResult.none);

    if (isOnline) {
      try {
        final response = await ApiService.getWithTimeout(
          '${ApiService.baseUrl}/api/categories',
          headers: ApiService.publicHeaders,
          useCache: true,
        );
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          List<dynamic> cats;
          if (decoded is List) {
            cats = decoded;
          } else if (decoded is Map && decoded.containsKey('data')) {
            cats = decoded['data'] as List<dynamic>;
          } else {
            cats = [];
          }
          // Cache for offline use
          await OfflineService.cacheCategories(cats);
          return cats;
        }
      } catch (e) {
        // Server failed — fall through to cache
      }
    }

    // Offline fallback: return cached categories
    final cached = await OfflineService.getCachedCategories();
    if (cached.isNotEmpty) return cached;

    // Nothing cached — throw so caller knows
    throw Exception('Failed to load categories');
  }
}
