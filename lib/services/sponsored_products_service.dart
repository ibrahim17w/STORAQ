import 'dart:convert';
import 'api_service.dart';

class SponsoredProductsService {
  static Future<Map<String, dynamic>> getPricing() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/sponsorship/pricing',
      headers: ApiService.publicHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load sponsorship pricing');
  }

  static Future<Map<String, dynamic>> getQuote({
    required int productId,
    required String scopeType,
    required int durationDays,
    int? radiusKm,
  }) async {
    final response = await ApiService.authPost(
      '/my-store/products/$productId/sponsorship/quote',
      {
        'scope_type': scopeType,
        'duration_days': durationDays,
        if (radiusKm != null) 'radius_km': radiusKm,
      },
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Failed to get quote');
  }

  static Future<Map<String, dynamic>> requestSponsorship({
    required int productId,
    required String scopeType,
    required int durationDays,
    int? radiusKm,
    String paymentTrack = 'syria_agent',
  }) async {
    final response = await ApiService.authPost(
      '/my-store/products/$productId/sponsorship/request',
      {
        'scope_type': scopeType,
        'duration_days': durationDays,
        'payment_track': paymentTrack,
        if (radiusKm != null) 'radius_km': radiusKm,
      },
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Failed to request sponsorship');
  }

  static Future<Map<String, dynamic>> getMyCampaigns() async {
    final response = await ApiService.authGet('/my-store/sponsorship/campaigns');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(data['error']?.toString() ?? 'Failed to load campaigns');
  }
}
