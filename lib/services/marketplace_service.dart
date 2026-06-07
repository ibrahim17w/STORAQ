import 'dart:convert';
import 'api_service.dart';
import '../models/models.dart';

class MarketplaceService {
  static Future<List<Product>> fetchMarketplaceFeed() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/marketplace/feed',
      headers: ApiService.publicHeaders,
      useCache: true,
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = body.containsKey('data')
          ? body['data'] as List<dynamic>
          : body as List<dynamic>? ?? [];
      return items
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
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

  static Future<List<Product>> fetchTrendingProducts() async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/products/trending',
        headers: ApiService.publicHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Product>> fetchSponsoredProducts({
    double? lat,
    double? lng,
    String? village,
    String? city,
    String? country,
    String? countryCode,
    String? cityId,
  }) async {
    try {
      final params = <String, String>{};
      if (lat != null) params['lat'] = lat.toString();
      if (lng != null) params['lng'] = lng.toString();
      if (village != null && village.isNotEmpty) params['village'] = village;
      if (city != null && city.isNotEmpty) params['city'] = city;
      if (country != null && country.isNotEmpty) params['country'] = country;
      if (countryCode != null && countryCode.isNotEmpty) params['country_code'] = countryCode;
      if (cityId != null && cityId.isNotEmpty) params['city_id'] = cityId;

      final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/products/sponsored$query',
        headers: ApiService.publicHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Store>> fetchSponsoredStores() async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/stores/sponsored',
        headers: ApiService.publicHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list
            .map((e) => Store.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Product>> fetchRecommendations() async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/recommendations',
        headers: await ApiService.authHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> placeOrder({
    required List<Map<String, dynamic>> items,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/marketplace/checkout',
      headers: await ApiService.authHeaders,
      body: jsonEncode({
        'items': items,
        'payment_method': paymentMethod,
        if (notes != null) 'notes': notes,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Order failed');
  }

  static Future<Product?> fetchProductDetail(int productId) async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/marketplace/products/$productId',
        headers: ApiService.publicHeaders,
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return Product.fromJson(body);
      }
    } catch (_) {}
    return null;
  }

  static Future<List<Product>> fetchNearbyProducts({
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
        final list = jsonDecode(response.body) as List<dynamic>;
        return list
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
