import 'dart:convert';
import 'api_service.dart';

class OrderService {
  static Future<Map<String, dynamic>> checkout({
    required List<Map<String, dynamic>> items,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/checkout',
      headers: await ApiService.authHeaders,
      body: jsonEncode({
        'items': items,
        'payment_method': paymentMethod,
        'notes': notes,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Checkout failed');
  }

  static Future<Map<String, dynamic>> createOrder({
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
    double subtotal = 0,
    double discount = 0,
    double tax = 0,
    double total = 0,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'items': items,
      'subtotal': subtotal,
      'discount': discount,
      'tax': tax,
      'total': total,
      'payment_method': paymentMethod,
    };
    if (customerName != null) body['customer_name'] = customerName;
    if (customerPhone != null) body['customer_phone'] = customerPhone;
    if (notes != null) body['notes'] = notes;

    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/orders',
      headers: await ApiService.authHeaders,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Checkout failed');
  }

  static Future<List<dynamic>> fetchOrders({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/orders?limit=$limit&offset=$offset',
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body.containsKey('data')) {
        return body['data'] as List<dynamic>;
      }
      return body as List<dynamic>? ?? [];
    }
    throw Exception('Failed to load orders');
  }

  static Future<Map<String, dynamic>> fetchOrder(int id) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/orders/$id',
      headers: await ApiService.authHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Order not found');
  }

  // ============================================================
  // RECEIPT SETTINGS
  // ============================================================

  static Future<Map<String, dynamic>> getReceiptSettings() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/my-store/receipt-settings',
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return {
      'footer_message': 'Thank you for your purchase!',
      'show_logo': true,
      'show_barcode': true,
      'currency_symbol': 'SYP',
    };
  }

  static Future<Map<String, dynamic>> updateReceiptSettings({
    String? footerMessage,
    bool? showLogo,
    bool? showBarcode,
    String? currencySymbol,
  }) async {
    final body = <String, dynamic>{};
    if (footerMessage != null) body['footer_message'] = footerMessage;
    if (showLogo != null) body['show_logo'] = showLogo;
    if (showBarcode != null) body['show_barcode'] = showBarcode;
    if (currencySymbol != null) body['currency_symbol'] = currencySymbol;

    final response = await ApiService.putWithTimeout(
      '${ApiService.baseUrl}/api/my-store/receipt-settings',
      headers: await ApiService.authHeaders,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Update failed');
  }

  // ============================================================
  // LOW STOCK ALERTS
  // ============================================================

  static Future<List<dynamic>> fetchLowStockProducts() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/my-store/low-stock',
      headers: await ApiService.authHeaders,
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }
}
