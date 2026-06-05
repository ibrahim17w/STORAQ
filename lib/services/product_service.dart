// lib/services/product_service.dart
// FIXED: syncPendingChanges now reads category_ids (plural) from pending creates
// FIXED: image sync for offline products via individual multipart uploads

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
      if (!fallbackToCache) rethrow;
    }

    if (fallbackToCache) {
      final cached = await OfflineService.getCachedProducts(storeId: storeId);
      if (cached.isNotEmpty) return cached;
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
    return !connectivity.contains(ConnectivityResult.none);
  }

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

    final tempId = DateTime.now().millisecondsSinceEpoch;
    // Do NOT cache pending creates in cached_products — getMergedProducts()
    // already surfaces them from pending_products. Caching here caused
    // duplicate products after sync (temp 'pending_' ID vs real server ID).
    return {'offline': true, 'pending': true, 'id': 'pending_$tempId'};
  }

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

  static Future<void> deleteProductOfflineAware(int id, int storeId) async {
    try {
      if (await _isOnline()) {
        return await deleteProduct(id);
      }
    } catch (e) {}

    await OfflineService.addPendingDelete(id, storeId);
    await OfflineService.removeCachedProduct(id);
  }

  // ============================================================
  // BULK SYNC (with image-aware individual uploads)
  // ============================================================

  /// Syncs all pending changes (creates, updates, deletes, stock changes) to server.
  /// Products with local images are synced individually via multipart to preserve images.
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

    final bulkCreates = <Map<String, dynamic>>[];
    final imageCreates = <Map<String, dynamic>>[];
    for (final c in creates) {
      if (_pendingHasImages(c)) {
        imageCreates.add(c);
      } else {
        bulkCreates.add({
          'local_id': c['id'],
          'name': c['name'],
          'price': c['price'],
          'quantity': c['quantity'],
          'description': c['description'],
          'barcode': c['barcode'],
          'category_id': _extractCategoryId(c),
          'low_stock_threshold': c['low_stock_threshold'] ?? 5,
          'currency': c['currency'] ?? 'SYP',
        });
      }
    }

    final bulkUpdates = <Map<String, dynamic>>[];
    final imageUpdates = <Map<String, dynamic>>[];
    for (final u in updates) {
      if (_pendingHasImages(u)) {
        imageUpdates.add(u);
      } else {
        bulkUpdates.add({
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
        });
      }
    }

    final results = <String, dynamic>{
      'status': 'synced',
      'creates': <Map<String, dynamic>>[],
      'updates': <Map<String, dynamic>>[],
      'deletes': <Map<String, dynamic>>[],
      'stock_changes': <Map<String, dynamic>>[],
    };

    // --- CREATES WITH IMAGES (individual multipart) ---
    for (final c in imageCreates) {
      try {
        final imageFiles = _extractImageFiles(c);
        final result = await createProduct(
          name: c['name']?.toString() ?? '',
          price: (c['price'] as num?)?.toDouble() ?? 0,
          quantity: c['quantity'] is int
              ? c['quantity']
              : int.tryParse(c['quantity']?.toString() ?? '0') ?? 0,
          description: c['description']?.toString(),
          barcode: c['barcode']?.toString(),
          categoryId: _extractCategoryId(c),
          lowStockThreshold: c['low_stock_threshold'] is int
              ? c['low_stock_threshold']
              : int.tryParse(c['low_stock_threshold']?.toString() ?? '5') ?? 5,
          currency: c['currency']?.toString() ?? 'SYP',
          image: imageFiles.isNotEmpty ? imageFiles.first : null,
          extraImages: imageFiles.length > 1 ? imageFiles.sublist(1) : null,
        );
        (results['creates'] as List<Map<String, dynamic>>).add({
          'local_id': c['id'],
          'status': 'success',
          'server_id': result['id'],
          'product': result,
        });
        await OfflineService.removePending(c['id'] as int);
      } catch (e) {
        (results['creates'] as List<Map<String, dynamic>>).add({
          'local_id': c['id'],
          'status': 'error',
          'error': e.toString(),
        });
      }
    }

    // --- UPDATES WITH IMAGES (individual multipart) ---
    for (final u in imageUpdates) {
      try {
        final imageFiles = _extractImageFiles(u);
        final serverId = u['server_id'] as int;
        final result = await updateProduct(
          id: serverId,
          name: u['name']?.toString() ?? '',
          price: (u['price'] as num?)?.toDouble() ?? 0,
          quantity: u['quantity'] is int
              ? u['quantity']
              : int.tryParse(u['quantity']?.toString() ?? '0') ?? 0,
          description: u['description']?.toString(),
          barcode: u['barcode']?.toString(),
          categoryId: _extractCategoryId(u),
          lowStockThreshold: u['low_stock_threshold'] is int
              ? u['low_stock_threshold']
              : int.tryParse(u['low_stock_threshold']?.toString() ?? '5') ?? 5,
          currency: u['currency']?.toString() ?? 'SYP',
          image: imageFiles.isNotEmpty ? imageFiles.first : null,
          extraImages: imageFiles.length > 1 ? imageFiles.sublist(1) : null,
        );
        (results['updates'] as List<Map<String, dynamic>>).add({
          'local_id': u['id'],
          'status': 'success',
          'product': result,
        });
        await OfflineService.removePending(u['id'] as int);
      } catch (e) {
        (results['updates'] as List<Map<String, dynamic>>).add({
          'local_id': u['id'],
          'status': 'error',
          'error': e.toString(),
        });
      }
    }

    // --- BULK SYNC for no-image items ---
    final body = <String, dynamic>{
      'creates': bulkCreates,
      'updates': bulkUpdates,
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

    if (bulkCreates.isNotEmpty ||
        bulkUpdates.isNotEmpty ||
        deletes.isNotEmpty ||
        stockChanges.isNotEmpty) {
      final response = await ApiService.postWithTimeout(
        '${ApiService.baseUrl}/api/products/sync',
        headers: await ApiService.authHeaders,
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        (results['creates'] as List<Map<String, dynamic>>).addAll(
          (data['creates'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        );
        (results['updates'] as List<Map<String, dynamic>>).addAll(
          (data['updates'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        );
        (results['deletes'] as List<Map<String, dynamic>>).addAll(
          (data['deletes'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        );
        (results['stock_changes'] as List<Map<String, dynamic>>).addAll(
          (data['stock_changes'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        );

        for (final c in bulkCreates) {
          final localId = c['local_id'] as int;
          final success = (results['creates'] as List<Map<String, dynamic>>)
              .any((r) => r['local_id'] == localId && r['status'] == 'success');
          if (success) await OfflineService.removePending(localId);
        }
        for (final u in bulkUpdates) {
          final localId = u['local_id'] as int;
          final success = (results['updates'] as List<Map<String, dynamic>>)
              .any((r) => r['local_id'] == localId && r['status'] == 'success');
          if (success) await OfflineService.removePending(localId);
        }
        for (final d in deletes) {
          final localId = d['id'] as int;
          final success = (results['deletes'] as List<Map<String, dynamic>>)
              .any((r) => r['local_id'] == localId && r['status'] == 'success');
          if (success) await OfflineService.clearPendingDelete(localId);
        }
        for (final s in stockChanges) {
          final localId = s['id'] as int;
          final success =
              (results['stock_changes'] as List<Map<String, dynamic>>).any(
                (r) => r['local_id'] == localId && r['status'] == 'success',
              );
          if (success) await OfflineService.markStockChangeSynced(localId);
        }
      } else {
        throw Exception(data['error']?.toString() ?? 'Sync failed');
      }
    }

    // Refresh cache from server so IDs match and old temp entries are gone
    try {
      await OfflineService.clearCachedProducts(storeId);
      await fetchProducts(storeId, useCache: false);
    } catch (_) {}
    return results;
  }

  // ============================================================
  // IMAGE HELPERS
  // ============================================================

  static bool _pendingHasImages(Map<String, dynamic> pending) {
    final raw = pending['image_paths'];
    if (raw == null) return false;
    List<dynamic> paths = [];
    if (raw is String) {
      try {
        paths = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        return false;
      }
    } else if (raw is List) {
      paths = raw;
    }
    return paths.any((p) => p != null && p.toString().isNotEmpty);
  }

  static List<File> _extractImageFiles(Map<String, dynamic> pending) {
    final raw = pending['image_paths'];
    if (raw == null) return [];
    List<dynamic> paths = [];
    if (raw is String) {
      try {
        paths = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        return [];
      }
    } else if (raw is List) {
      paths = raw;
    }
    return paths
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .map((p) => File(p))
        .where((f) => f.existsSync())
        .toList();
  }

  /// Extracts a single category ID from pending data that may have
  /// category_id (int), category_ids (List), or null.
  static int? _extractCategoryId(Map<String, dynamic> pending) {
    final direct = pending['category_id'];
    if (direct is int) return direct;
    if (direct is String) return int.tryParse(direct);

    final list = pending['category_ids'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is int) return first;
      if (first is String) return int.tryParse(first);
    }

    return null;
  }

  // ============================================================
  // CREATE / UPDATE / DELETE
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
  // PRODUCT IMAGES
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
  // BARCODE
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
  // PRODUCT SEARCH
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
