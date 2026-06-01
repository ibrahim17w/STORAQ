// lib/services/product_service.dart
// FIXED: syncPendingChanges now reads category_ids (plural) from pending creates

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'offline_service.dart';

class ProductService {
  // ============================================================
  // FETCH (auto-caches when online, falls back to cache when offline)
  // ============================================================

  static Future<List<dynamic>> fetchProducts(
    int storeId, {
    bool useCache = true,
    bool fallbackToCache = true,
  }) async {
    final cacheBuster = useCache
        ? ''
        : '?_cb=${DateTime.now().millisecondsSinceEpoch}';
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/products/$storeId$cacheBuster',
        headers: ApiService.publicHeaders,
        useCache: useCache,
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> products;
        if (body.containsKey('data')) {
          products = body['data'] as List<dynamic>;
        } else {
          products = body as List<dynamic>? ?? [];
        }
        await OfflineService.cacheProducts(storeId, products);
        await OfflineService.setLastSync(storeId);
        return products;
      }
    } catch (e) {
      // SocketException, timeout, server error — all fall through to cache
      if (!fallbackToCache) rethrow;
    }

    if (fallbackToCache) {
      final cached = await OfflineService.getCachedProducts(storeId: storeId);
      if (cached.isNotEmpty) return cached;
      // Also include pending creates/updates/deletes in the merged view
      final merged = await OfflineService.getMergedProducts(storeId);
      if (merged.isNotEmpty) return merged;
    }

    throw Exception('Failed to load products');
  }

  static Future<List<dynamic>> fetchProductsOffline(int storeId) async {
    final cached = await OfflineService.getCachedProducts(storeId: storeId);
    if (cached.isNotEmpty) return cached;
    return fetchProducts(storeId, fallbackToCache: true);
  }

  // ============================================================
  // OFFLINE-AWARE WRAPPERS
  // ============================================================

  static Future<bool> _isOnline() async {
    final connectivity = await Connectivity().checkConnectivity();
    // FIXED: v6+ connectivity API — List.contains instead of !=
    return !connectivity.contains(ConnectivityResult.none);
  }

  /// Creates a product. If offline, queues it for later sync.
  static Future<Map<String, dynamic>> createProductOfflineAware({
    required String name,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    int? categoryId,
    int? lowStockThreshold,
    File? image,
    List<File>? extraImages,
    String? currency,
    required int storeId,
  }) async {
    if (await _isOnline()) {
      return createProduct(
        name: name,
        price: price,
        quantity: quantity,
        description: description,
        barcode: barcode,
        categoryId: categoryId,
        lowStockThreshold: lowStockThreshold,
        image: image,
        extraImages: extraImages,
        currency: currency,
      );
    }

    // Offline: queue pending create
    await OfflineService.addPending({
      'name': name,
      'price': price,
      'quantity': quantity,
      'description': description,
      'barcode': barcode,
      'category_id': categoryId,
      'currency': currency ?? 'SYP',
      'image_path': image?.path,
      'image_paths': extraImages?.map((f) => f.path).toList(),
      'action': 'create',
    }, storeId);

    // Optimistic: add to cache immediately so UI shows it
    final tempId = DateTime.now().millisecondsSinceEpoch;
    await OfflineService.cacheProducts(storeId, [
      {
        'id': 'pending_$tempId',
        'name': name,
        'price': price,
        'quantity': quantity,
        'description': description,
        'barcode': barcode,
        'category_id': categoryId,
        'currency': currency ?? 'SYP',
        'image_url': image != null ? image.path : null,
        'images': extraImages?.map((f) => f.path).toList() ?? [],
        'low_stock_threshold': lowStockThreshold ?? 5,
        'updated_at': DateTime.now().toIso8601String(),
        '_pendingCreate': true,
      },
    ]);

    return {'offline': true, 'pending': true, 'id': 'pending_$tempId'};
  }

  /// Updates a product. If offline, queues it for later sync.
  static Future<Map<String, dynamic>> updateProductOfflineAware({
    required int id,
    required String name,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    int? categoryId,
    int? lowStockThreshold,
    File? image,
    List<File>? extraImages,
    List<String>? existingImages,
    String? currency,
    required int storeId,
  }) async {
    if (await _isOnline()) {
      return updateProduct(
        id: id,
        name: name,
        price: price,
        quantity: quantity,
        description: description,
        barcode: barcode,
        categoryId: categoryId,
        lowStockThreshold: lowStockThreshold,
        image: image,
        extraImages: extraImages,
        existingImages: existingImages,
        currency: currency,
      );
    }

    // Offline: queue pending update
    await OfflineService.addPendingUpdate(
      {
        'server_id': id,
        'name': name,
        'price': price,
        'quantity': quantity,
        'description': description,
        'barcode': barcode,
        'category_id': categoryId,
        'currency': currency ?? 'SYP',
        'image_path': image?.path,
        'image_paths': extraImages?.map((f) => f.path).toList(),
        'existing_images': existingImages,
      },
      id,
      storeId,
    );

    // Optimistic: update cache immediately
    await OfflineService.updateCachedProduct({
      'id': id,
      'name': name,
      'price': price,
      'quantity': quantity,
      'description': description,
      'barcode': barcode,
      'category_id': categoryId,
      'currency': currency ?? 'SYP',
      '_pendingUpdate': true,
    });

    return {'offline': true, 'pending': true, 'id': id};
  }

  /// Deletes a product. If offline, queues it for later sync.
  static Future<void> deleteProductOfflineAware(int id, int storeId) async {
    try {
      if (await _isOnline()) {
        return await deleteProduct(id);
      }
    } catch (e) {
      // Server call failed mid-delete — fall through to offline queue
    }

    // Offline: queue for sync and remove from local cache immediately
    await OfflineService.addPendingDelete(id, storeId);
    await OfflineService.removeCachedProduct(id);
  }

  /// Syncs all pending changes (creates, updates, deletes, stock changes) to server.
  static Future<Map<String, dynamic>> syncPendingChanges(int storeId) async {
    if (!await _isOnline()) {
      throw Exception('Cannot sync while offline');
    }

    final creates = await OfflineService.getPendingCreates(storeId: storeId);
    final updates = await OfflineService.getPendingUpdates(storeId: storeId);
    final deletes = await OfflineService.getPendingDeletes(storeId: storeId);
    final stockChanges = await OfflineService.getUnsyncedStockChanges();

    if (creates.isEmpty &&
        updates.isEmpty &&
        deletes.isEmpty &&
        stockChanges.isEmpty) {
      return {'status': 'nothing_to_sync'};
    }

    final body = <String, dynamic>{
      'creates': creates
          .map(
            (c) => {
              'local_id': c['id'],
              'name': c['name'],
              'price': c['price'],
              'quantity': c['quantity'],
              'description': c['description'],
              'barcode': c['barcode'],
              // FIXED: Read category_ids (plural, list) from pending create
              // The backend sync endpoint expects category_id (singular int)
              'category_id': _extractCategoryId(c),
              'low_stock_threshold': c['low_stock_threshold'] ?? 5,
              'currency': c['currency'] ?? 'SYP',
            },
          )
          .toList(),
      'updates': updates
          .map(
            (u) => {
              'local_id': u['id'],
              'server_id': u['server_id'],
              'name': u['name'],
              'price': u['price'],
              'quantity': u['quantity'],
              'description': u['description'],
              'barcode': u['barcode'],
              'category_id': _extractCategoryId(u),
              'low_stock_threshold': u['low_stock_threshold'] ?? 5,
              'currency': u['currency'] ?? 'SYP',
            },
          )
          .toList(),
      'deletes': deletes
          .map((d) => {'local_id': d['id'], 'product_id': d['product_id']})
          .toList(),
      'stock_changes': stockChanges
          .map(
            (s) => {
              'local_id': s['id'],
              'product_id': s['product_id'],
              'delta': s['delta'],
            },
          )
          .toList(),
    };

    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/products/sync',
      headers: await ApiService.authHeaders,
      body: jsonEncode(body),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200) {
      // Clear successfully synced pending items
      for (final c in creates) {
        await OfflineService.removePending(c['id'] as int);
      }
      for (final u in updates) {
        await OfflineService.removePending(u['id'] as int);
      }
      for (final d in deletes) {
        await OfflineService.clearPendingDelete(d['id'] as int);
      }
      for (final s in stockChanges) {
        await OfflineService.markStockChangeSynced(s['id'] as int);
      }

      // Refresh cache from server
      await fetchProducts(storeId, useCache: false);
      return data;
    }

    throw Exception(data['error']?.toString() ?? 'Sync failed');
  }

  /// Extracts a single category ID from pending data that may have
  /// category_id (int), category_ids (List), or null.
  static int? _extractCategoryId(Map<String, dynamic> pending) {
    // Try category_id first (from updates or direct creates)
    final direct = pending['category_id'];
    if (direct is int) return direct;
    if (direct is String) return int.tryParse(direct);

    // Try category_ids (list from add_product_screen offline create)
    final list = pending['category_ids'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is int) return first;
      if (first is String) return int.tryParse(first);
    }

    return null;
  }

  // ============================================================
  // CREATE / UPDATE / DELETE (original methods — UNCHANGED)
  // ============================================================

  static Future<Map<String, dynamic>> createProduct({
    required String name,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    int? categoryId,
    int? lowStockThreshold,
    File? image,
    List<File>? extraImages,
    String? currency,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/api/products'),
    );
    request.headers.addAll(await ApiService.multipartAuthHeaders);
    request.fields['name'] = name;
    request.fields['price'] = price.toString();
    request.fields['quantity'] = quantity.toString();
    if (description != null) request.fields['description'] = description;
    if (barcode != null) request.fields['barcode'] = barcode;
    if (categoryId != null)
      request.fields['category_id'] = categoryId.toString();
    if (lowStockThreshold != null)
      request.fields['low_stock_threshold'] = lowStockThreshold.toString();
    if (currency != null) request.fields['currency'] = currency;
    if (image != null) {
      request.files.add(await http.MultipartFile.fromPath('image', image.path));
    }
    if (extraImages != null && extraImages.isNotEmpty) {
      for (final img in extraImages) {
        request.files.add(
          await http.MultipartFile.fromPath('extra_images', img.path),
        );
      }
    }

    final streamed = await request.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Failed');
  }

  static Future<Map<String, dynamic>> updateProduct({
    required int id,
    required String name,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    int? categoryId,
    int? lowStockThreshold,
    File? image,
    List<File>? extraImages,
    List<String>? existingImages,
    String? currency,
  }) async {
    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('${ApiService.baseUrl}/api/products/$id'),
    );
    request.headers.addAll(await ApiService.multipartAuthHeaders);
    request.fields['name'] = name;
    request.fields['price'] = price.toString();
    request.fields['quantity'] = quantity.toString();
    if (description != null) request.fields['description'] = description;
    if (barcode != null) request.fields['barcode'] = barcode;
    if (categoryId != null)
      request.fields['category_id'] = categoryId.toString();
    if (lowStockThreshold != null)
      request.fields['low_stock_threshold'] = lowStockThreshold.toString();
    if (currency != null) request.fields['currency'] = currency;
    if (existingImages != null)
      request.fields['existing_images'] = jsonEncode(existingImages);
    if (image != null) {
      request.files.add(await http.MultipartFile.fromPath('image', image.path));
    }
    if (extraImages != null && extraImages.isNotEmpty) {
      for (final img in extraImages) {
        request.files.add(
          await http.MultipartFile.fromPath('extra_images', img.path),
        );
      }
    }

    final streamed = await request.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Failed');
  }

  static Future<void> deleteProduct(int id) async {
    final response = await http
        .delete(
          Uri.parse('${ApiService.baseUrl}/api/products/$id'),
          headers: await ApiService.authHeaders,
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Failed');
    }
  }

  // ============================================================
  // PRODUCT IMAGES (UNCHANGED)
  // ============================================================

  static Future<List<dynamic>> fetchProductImages(int productId) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/products/$productId/images',
      headers: ApiService.publicHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  static Future<void> uploadProductImage(int productId, File image) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/api/products/$productId/images'),
    );
    request.headers.addAll(await ApiService.multipartAuthHeaders);
    request.files.add(await http.MultipartFile.fromPath('image', image.path));
    final streamed = await request.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 201) {
      throw Exception('Image upload failed');
    }
  }

  // ============================================================
  // BARCODE (UNCHANGED)
  // ============================================================

  static Future<Map<String, dynamic>?> lookupBarcode(String barcode) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/products/barcode/$barcode',
      headers: ApiService.publicHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) return null;
    throw Exception('Barcode lookup failed');
  }

  static Future<Map<String, dynamic>> checkBarcodeUnique(
    String barcode, {
    int? excludeId,
  }) async {
    var url =
        '${ApiService.baseUrl}/api/products/check-barcode?barcode=${Uri.encodeComponent(barcode)}';
    if (excludeId != null) url += '&exclude_id=$excludeId';
    final response = await ApiService.getWithTimeout(
      url,
      headers: ApiService.publicHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Barcode check failed');
  }

  static Future<Map<String, dynamic>?> validateBarcode(String barcode) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/products/barcode/validate?code=${Uri.encodeComponent(barcode)}',
      headers: ApiService.publicHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) return null;
    throw Exception('Barcode validation failed');
  }

  static Future<Map<String, dynamic>> findProductByBarcode(
    String barcode,
  ) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/products/barcode/$barcode',
      headers: ApiService.publicHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Product not found');
  }

  // ============================================================
  // PRODUCT SEARCH (for checkout) (UNCHANGED)
  // ============================================================

  static Future<List<dynamic>> searchStoreProducts({
    required String query,
    int? storeId,
    int limit = 20,
  }) async {
    final url = storeId != null
        ? '${ApiService.baseUrl}/api/products/$storeId/search?q=${Uri.encodeComponent(query)}&limit=$limit'
        : '${ApiService.baseUrl}/api/products/search?q=${Uri.encodeComponent(query)}&limit=$limit';
    final response = await ApiService.getWithTimeout(
      url,
      headers: ApiService.publicHeaders,
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }
}
