import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
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
    double? displaySubtotal,
    double? displayDiscount,
    double? displayTax,
    double? displayTotal,
    String? displayCurrency,
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
    if (displaySubtotal != null) body['display_subtotal'] = displaySubtotal;
    if (displayDiscount != null) body['display_discount'] = displayDiscount;
    if (displayTax != null) body['display_tax'] = displayTax;
    if (displayTotal != null) body['display_total'] = displayTotal;
    if (displayCurrency != null && displayCurrency.isNotEmpty) {
      body['display_currency'] = displayCurrency;
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

  static Future<List<Order>> fetchMyOrders({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/my-orders?limit=$limit&offset=$offset',
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawOrders = body.containsKey('data')
          ? body['data'] as List<dynamic>
          : body as List<dynamic>? ?? [];
      return rawOrders
          .map((item) => Order.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load orders');
  }

  static Future<List<Order>> fetchOrders({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/orders?limit=$limit&offset=$offset',
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> rawOrders;
      if (body.containsKey('data')) {
        rawOrders = body['data'] as List<dynamic>;
      } else {
        rawOrders = body as List<dynamic>? ?? [];
      }
      await OfflineService.cacheOrders(rawOrders);
      return rawOrders
          .map((item) => Order.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load orders');
  }

  /// Order history when offline or server unreachable.
  static Future<List<Order>> fetchOrdersOffline({
    int limit = 200,
    int offset = 0,
  }) async {
    final rawOrders =
        await OfflineService.getCachedOrders(limit: limit, offset: offset);
    return rawOrders
        .map((item) => Order.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Order>> loadOrderHistory({
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

  static Future<Order> fetchOrder(int id) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/orders/$id',
      headers: await ApiService.authHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      final orderRow = data['order'] as Map<String, dynamic>? ?? data;
      final items = data['items'] as List<dynamic>? ?? [];
      final flatMap = <String, dynamic>{...orderRow, 'items': items};
      return Order.fromJson(flatMap);
    }
    throw Exception(data['error']?.toString() ?? 'Order not found');
  }

  // ============================================================
  // RECEIPT SETTINGS
  // ============================================================

  static Future<ReceiptSettings> getReceiptSettings() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/my-store/receipt-settings',
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _cacheReceiptSettings(data);
      return ReceiptSettings.fromJson(data);
    }
    return ReceiptSettings.defaults;
  }

  static Future<void> _cacheReceiptSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_receipt_settings', jsonEncode(settings));
  }

  static Future<ReceiptSettings> getReceiptSettingsOffline() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_receipt_settings');
    if (raw == null) return ReceiptSettings.defaults;
    try {
      return ReceiptSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return ReceiptSettings.defaults;
    }
  }

  static Future<ReceiptSettings> loadReceiptSettings() async {
    try {
      if (await ApiService.isServerReachable()) {
        return await getReceiptSettings();
      }
    } catch (_) {}
    return getReceiptSettingsOffline();
  }

  static Future<ReceiptSettings> updateReceiptSettings({
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
    if (response.statusCode == 200) return ReceiptSettings.fromJson(data);
    throw Exception(data['error']?.toString() ?? 'Update failed');
  }

  // ============================================================
  // LOW STOCK ALERTS
  // ============================================================

  static Future<List<Product>> fetchLowStockProducts() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/my-store/low-stock',
      headers: await ApiService.authHeaders,
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode == 200) {
      final rawList = jsonDecode(response.body) as List<dynamic>;
      return rawList
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();
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
          displaySubtotal: (orderData['display_subtotal'] as num?)?.toDouble(),
          displayDiscount: (orderData['display_discount'] as num?)?.toDouble(),
          displayTax: (orderData['display_tax'] as num?)?.toDouble(),
          displayTotal: (orderData['display_total'] as num?)?.toDouble(),
          displayCurrency: orderData['display_currency']?.toString(),
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
