import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'offline_service.dart';

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
    String? receiptNumber,
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
    if (receiptNumber != null && receiptNumber.isNotEmpty) {
      body['receipt_number'] = receiptNumber;
    }

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
      final List<dynamic> orders;
      if (body.containsKey('data')) {
        orders = body['data'] as List<dynamic>;
      } else {
        orders = body as List<dynamic>? ?? [];
      }
      await OfflineService.cacheOrders(orders);
      return orders;
    }
    throw Exception('Failed to load orders');
  }

  /// Order history when offline or server unreachable.
  static Future<List<dynamic>> fetchOrdersOffline({
    int limit = 200,
    int offset = 0,
  }) async {
    return OfflineService.getCachedOrders(limit: limit, offset: offset);
  }

  static Future<List<dynamic>> loadOrderHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      if (await ApiService.isServerReachable()) {
        return await fetchOrders(limit: limit, offset: offset);
      }
    } catch (_) {}
    return fetchOrdersOffline(limit: limit, offset: offset);
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
      final settings = jsonDecode(response.body) as Map<String, dynamic>;
      await _cacheReceiptSettings(settings);
      return settings;
    }
    return _defaultReceiptSettings();
  }

  static Map<String, dynamic> _defaultReceiptSettings() => {
    'footer_message': 'Thank you for your purchase!',
    'show_logo': true,
    'show_barcode': true,
    'currency_symbol': 'SYP',
  };

  static Future<void> _cacheReceiptSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_receipt_settings', jsonEncode(settings));
  }

  static Future<Map<String, dynamic>> getReceiptSettingsOffline() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_receipt_settings');
    if (raw == null) return _defaultReceiptSettings();
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return _defaultReceiptSettings();
    }
  }

  static Future<Map<String, dynamic>> loadReceiptSettings() async {
    try {
      if (await ApiService.isServerReachable()) {
        return await getReceiptSettings();
      }
    } catch (_) {}
    return getReceiptSettingsOffline();
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

  /// Upload queued offline receipts to the server.
  static Future<Map<String, dynamic>> syncPendingOrders() async {
    if (!await ApiService.isServerReachable()) {
      throw Exception('Cannot sync while offline');
    }

    await OfflineService.remapAllQueuedOrderItems();

    final pending = await OfflineService.getPendingOrders();
    if (pending.isEmpty) {
      return {'synced': 0, 'failed': 0, 'status': 'nothing_to_sync'};
    }

    int synced = 0;
    int failed = 0;
    String? lastError;

    for (final order in pending) {
      try {
        final orderData = Map<String, dynamic>.from(
          order['order_data'] as Map<String, dynamic>,
        );
        final itemsRaw = orderData['items'] as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> items = [];
        final List<String> unresolvedNames = [];

        for (final raw in itemsRaw) {
          final map = raw is Map<String, dynamic>
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{};

          final productName =
              (map['product_name'] ??
                      map['name'] ??
                      map['productName'] ??
                      'Unknown')
                  .toString();
          final dynamic quantityRaw =
              map['quantity'] ?? map['qty'] ?? map['count'];
          final dynamic unitPriceRaw =
              map['unit_price'] ?? map['price'] ?? map['unitPrice'] ?? 0;
          final dynamic totalPriceRaw =
              map['total_price'] ??
              map['totalPrice'] ??
              map['line_total'] ??
              (unitPriceRaw * (quantityRaw ?? 0));
          final barcode =
              (map['barcode'] ?? map['product_barcode'])?.toString();

          int quantity;
          if (quantityRaw is int) {
            quantity = quantityRaw;
          } else if (quantityRaw is double) {
            quantity = quantityRaw.toInt();
          } else if (quantityRaw is String) {
            quantity = int.tryParse(quantityRaw) ?? 0;
          } else {
            quantity = 0;
          }

          final serverProductId = await OfflineService.resolveServerProductId(
            map['product_id'] ?? map['id'] ?? map['productId'],
            barcode: barcode,
          );

          if (serverProductId == null || serverProductId <= 0) {
            unresolvedNames.add(productName);
            continue;
          }

          if (quantity < 1) {
            throw Exception(
              'Invalid quantity for "$productName": $quantity',
            );
          }

          items.add({
            'product_id': serverProductId,
            'product_name': productName,
            'quantity': quantity,
            'unit_price': (unitPriceRaw is num
                ? unitPriceRaw.toDouble()
                : (num.tryParse(unitPriceRaw.toString()) ?? 0).toDouble()),
            'total_price': (totalPriceRaw is num
                ? totalPriceRaw.toDouble()
                : (num.tryParse(totalPriceRaw.toString()) ?? 0).toDouble()),
            'barcode': barcode,
          });
        }

        if (unresolvedNames.isNotEmpty) {
          throw Exception(
            'Cannot sync receipt: link these products first (sync inventory): ${unresolvedNames.join(', ')}',
          );
        }

        if (items.isEmpty) {
          throw Exception('Order has no valid items to sync');
        }

        final receiptNo = orderData['receipt_number']?.toString();
        await createOrder(
          items: List<Map<String, dynamic>>.from(items),
          customerName: orderData['customer_name']?.toString(),
          customerPhone: orderData['customer_phone']?.toString(),
          subtotal: (orderData['subtotal'] as num?)?.toDouble() ?? 0,
          discount: (orderData['discount'] as num?)?.toDouble() ?? 0,
          tax: (orderData['tax'] as num?)?.toDouble() ?? 0,
          total: (orderData['total'] as num?)?.toDouble() ?? 0,
          notes: orderData['notes']?.toString(),
          paymentMethod: orderData['payment_method']?.toString() ?? 'cash',
          receiptNumber: receiptNo,
        );

        await OfflineService.markOrderSynced(order['id'] as int);
        final receipt = orderData['receipt_number']?.toString();
        if (receipt != null && receipt.isNotEmpty) {
          await OfflineService.markOfflineOrderSynced(receipt);
        }
        final productIds = items
            .map((i) => i['product_id'] as int)
            .where((id) => id > 0)
            .toList();
        await OfflineService.discardUnsyncedStockChangesForProducts(productIds);
        synced++;
      } catch (e) {
        failed++;
        lastError = e.toString();
      }
    }

    return {
      'synced': synced,
      'failed': failed,
      if (lastError != null) 'lastError': lastError,
    };
  }
}
