import 'dart:convert';
import 'api_service.dart';

class SubscriptionLimitException implements Exception {
  final String code;
  final String message;
  final int onlineCount;
  final int onlineLimit;
  final List<dynamic> tiers;

  SubscriptionLimitException({
    required this.code,
    required this.message,
    required this.onlineCount,
    required this.onlineLimit,
    required this.tiers,
  });

  @override
  String toString() => message;
}

class SubscriptionService {
  static Future<Map<String, dynamic>> getStatus() async {
    final response = await ApiService.authGet('/my-store/subscription');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(data['error']?.toString() ?? 'Failed to load subscription');
  }

  static Future<List<dynamic>> getTiers() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/subscription/tiers',
      headers: ApiService.publicHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed to load tiers');
  }

  static Future<Map<String, dynamic>> requestSubscription({
    required int tierId,
    required String paymentTrack,
  }) async {
    final response = await ApiService.authPost('/my-store/subscription/request', {
      'tier_id': tierId,
      'payment_track': paymentTrack,
    });
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(
      data['message']?.toString() ??
          data['error']?.toString() ??
          'Failed to request subscription',
    );
  }

  static Future<Map<String, dynamic>> getOnlineProducts() async {
    final response = await ApiService.authGet('/my-store/products/online-status');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(data['error']?.toString() ?? 'Failed to load products');
  }

  static Future<Map<String, dynamic>> setProductOnline(int productId, bool isOnline) async {
    final response = await ApiService.authPut(
      '/my-store/products/$productId/online',
      {'is_online': isOnline},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    if (response.statusCode == 403 && data['error'] == 'online_slot_limit_reached') {
      throw SubscriptionLimitException(
        code: data['error']?.toString() ?? 'online_slot_limit_reached',
        message: data['message']?.toString() ?? 'Online slot limit reached',
        onlineCount: data['online_count'] as int? ?? 0,
        onlineLimit: data['online_limit'] as int? ?? 5,
        tiers: data['tiers'] as List<dynamic>? ?? [],
      );
    }
    throw Exception(data['error']?.toString() ?? 'Failed to update product');
  }

  static Future<void> bulkSetOnline(List<int> productIds) async {
    final response = await ApiService.authPut('/my-store/products/online/bulk', {
      'online_product_ids': productIds,
    });
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return;
    if (response.statusCode == 403 && data['error'] == 'online_slot_limit_reached') {
      throw SubscriptionLimitException(
        code: data['error']?.toString() ?? 'online_slot_limit_reached',
        message: data['message']?.toString() ?? 'Online slot limit reached',
        onlineCount: data['online_count'] as int? ?? 0,
        onlineLimit: data['online_limit'] as int? ?? 5,
        tiers: data['tiers'] as List<dynamic>? ?? [],
      );
    }
    throw Exception(data['error']?.toString() ?? 'Failed to update products');
  }

  static SubscriptionLimitException? parseLimitError(int statusCode, Map<String, dynamic> data) {
    if (statusCode == 403 && data['error'] == 'online_slot_limit_reached') {
      return SubscriptionLimitException(
        code: data['error']?.toString() ?? 'online_slot_limit_reached',
        message: data['message']?.toString() ?? 'Online slot limit reached',
        onlineCount: data['online_count'] as int? ?? 0,
        onlineLimit: data['online_limit'] as int? ?? 5,
        tiers: data['tiers'] as List<dynamic>? ?? [],
      );
    }
    if (statusCode == 429 && data['error'] == 'daily_creation_limit_reached') {
      return SubscriptionLimitException(
        code: data['error']?.toString() ?? 'daily_creation_limit_reached',
        message: data['message']?.toString() ?? 'Daily creation limit reached',
        onlineCount: 0,
        onlineLimit: data['limit'] as int? ?? 50,
        tiers: [],
      );
    }
    return null;
  }

  static Future<Map<String, dynamic>> redeemPromo(String code) async {
    final response = await ApiService.authPost('/my-store/redeem-promo', {
      'code': code.trim().toUpperCase(),
    });
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Failed to redeem promo code');
  }

  // Admin
  static Future<List<dynamic>> getPendingPayments() async {
    final response = await ApiService.authGet('/admin/subscription/payments?status=pending');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(data['error']?.toString() ?? 'Failed to load payments');
  }

  static Future<void> verifyPayment(int paymentId) async {
    final response = await ApiService.authPut(
      '/admin/subscription/payments/$paymentId/verify',
      {},
    );
    if (response.statusCode == 200) return;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(data['error']?.toString() ?? 'Failed to verify payment');
  }
}
