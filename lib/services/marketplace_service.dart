import 'dart:convert';
import 'api_service.dart';

class MarketplaceService {
  static Future<List<dynamic>> fetchMarketplaceFeed() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/marketplace/feed',
      headers: ApiService.publicHeaders,
      useCache: true,
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body.containsKey('data')) {
        return body['data'] as List<dynamic>;
      }
      return body as List<dynamic>? ?? [];
    }
    throw Exception('Failed to load marketplace feed');
  }

  static Future<void> trackProductView(int productId) async {
    try {
      await ApiService.postWithTimeout(
        '${ApiService.baseUrl}/api/products/$productId/view',
        headers: await ApiService.authHeaders,
      );
    } catch (_) {
      // Silently fail
    }
  }

  static Future<void> trackSearch(String query) async {
    try {
      await ApiService.postWithTimeout(
        '${ApiService.baseUrl}/api/search/track',
        headers: await ApiService.authHeaders,
        body: jsonEncode({'query': query}),
      );
    } catch (_) {
      // Silently fail
    }
  }

  static Future<List<dynamic>> fetchTrendingProducts() async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/products/trending',
        headers: ApiService.publicHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> fetchSponsoredStores() async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/stores/sponsored',
        headers: ApiService.publicHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> fetchRecommendations() async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/recommendations',
        headers: await ApiService.authHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> fetchNearbyProducts({
    required double lat,
    required double lng,
    double radiusKm = 15,
  }) async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/marketplace/nearby?lat=$lat&lng=$lng&radius=$radiusKm',
        headers: ApiService.publicHeaders,
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }
}
