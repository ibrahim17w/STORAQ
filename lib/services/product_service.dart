// lib/services/product_service.dart
// FIXED: syncPendingChanges now reads category_ids (plural) from pending creates
// FIXED: image sync for offline products via individual multipart uploads

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'api_service.dart';
import 'marketplace_service.dart';
import 'offline_service.dart';
import 'order_service.dart';
import 'store_catalog_service.dart';
import 'subscription_service.dart';

class ProductService {
  // ============================================================
  // FETCH (auto-caches when online, falls back to cache when offline)
  // ============================================================

  static List<Product> _mapsToProducts(List<Map<String, dynamic>> maps) {
    return maps.map((m) => Product.fromJson(m)).toList();
  }

  static Future<List<Product>> fetchProducts(
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
        return _mapsToProducts(await OfflineService.getMergedProducts(storeId));
      }
    } catch (e) {
      if (!fallbackToCache) rethrow;
    }

    if (fallbackToCache) {
      return loadStoreCatalogOffline(storeId);
    }

    throw Exception('Failed to load products');
  }

  static Future<List<Product>> loadStoreCatalogOffline(int storeId) async {
    final merged = await OfflineService.getMergedProducts(storeId);
    if (merged.isNotEmpty) return _mapsToProducts(merged);
    final cached = await OfflineService.getCachedProducts(storeId: storeId);
    return _mapsToProducts(cached);
  }

  static Future<List<Product>> fetchMyStoreProducts({
    bool useCache = true,
    bool fallbackToCache = true,
  }) async {
    try {
      final response = await ApiService.authGet('/my-store/products');
      if (response.statusCode == 200) {
        final products = jsonDecode(response.body) as List<dynamic>;
        final storeId = await ApiService.getMyStoreId();
        if (storeId != null) {
          await OfflineService.cacheProducts(storeId, products);
          await OfflineService.setLastSync(storeId);
        }
        if (storeId != null) {
          return _mapsToProducts(
            await OfflineService.getMergedProducts(storeId),
          );
        }
        return products
            .whereType<Map<String, dynamic>>()
            .map((m) => Product.fromJson(m))
            .toList();
      }
    } catch (e) {
      if (!fallbackToCache) rethrow;
    }
    final storeId = await ApiService.getMyStoreId();
    if (storeId != null) return loadStoreCatalogOffline(storeId);
    throw Exception('Failed to load store products');
  }

  static Future<List<Product>> loadStoreCatalog(
    int storeId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && !await _isOnline()) {
      return loadStoreCatalogOffline(storeId);
    }
    try {
      final hasStore = await ApiService.getStoreContext();
      if (hasStore != null) {
        return await fetchMyStoreProducts(
          useCache: !forceRefresh,
          fallbackToCache: true,
        );
      }
      return await fetchProducts(
        storeId,
        useCache: !forceRefresh,
        fallbackToCache: true,
      );
    } catch (_) {
      return loadStoreCatalogOffline(storeId);
    }
  }

  static Future<List<Product>> fetchProductsOffline(int storeId) async {
    return loadStoreCatalogOffline(storeId);
  }

  // ============================================================
  // OFFLINE-AWARE WRAPPERS
  // ============================================================

  static Future<bool> _isOnline() async {
    return ApiService.isServerReachable();
  }

  static Future<Product> createProductOfflineAware({
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
    return Product(
      id: 'pending_$tempId',
      name: name,
      price: price,
      quantity: quantity,
      description: description,
      barcode: barcode,
      categoryId: categoryId,
      currency: currency ?? 'SYP',
      pendingCreate: true,
    );
  }

  static Future<Product> updateProductOfflineAware({
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

    return Product(
      id: id,
      name: name,
      price: price,
      quantity: quantity,
      description: description,
      barcode: barcode,
      categoryId: categoryId,
      currency: currency ?? 'SYP',
      pendingUpdate: true,
    );
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

  /// Syncs pending creates/updates/deletes (and optionally stock) to server.
  /// Products with local images are synced individually via multipart to preserve images.
  static Future<Map<String, dynamic>> syncPendingChanges(
    int storeId, {
    bool includeStockChanges = true,
  }) async {
    if (!await _isOnline()) {
      throw Exception('Cannot sync while offline');
    }

    final creates = await OfflineService.getPendingCreates(storeId: storeId);
    final updates = await OfflineService.getPendingUpdates(storeId: storeId);
    final deletes = await OfflineService.getPendingDeletes(storeId: storeId);
    final stockChanges = includeStockChanges
        ? await OfflineService.getUnsyncedStockChanges()
        : <Map<String, dynamic>>[];

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
        final createResult = <String, dynamic>{
          'local_id': c['id'],
          'status': 'success',
          'server_id': result.id,
          'product': result.toJson(),
        };
        (results['creates'] as List).add(createResult);
        await _applySuccessfulCreate(
          pendingRow: c,
          syncResult: createResult,
          storeId: storeId,
        );
      } catch (e) {
        (results['creates'] as List).add({
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
          existingImages: _extractExistingImages(u),
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
        final createResults = _parseSyncResultList(data['creates']);
        final updateResults = _parseSyncResultList(data['updates']);
        final deleteResults = _parseSyncResultList(data['deletes']);
        final stockResults = _parseSyncResultList(data['stock_changes']);

        (results['creates'] as List).addAll(createResults);
        (results['updates'] as List).addAll(updateResults);
        (results['deletes'] as List).addAll(deleteResults);
        (results['stock_changes'] as List).addAll(stockResults);

        for (final c in bulkCreates) {
          final localId = c['local_id'];
          Map<String, dynamic>? pendingRow;
          for (final p in creates) {
            if (p['id'].toString() == localId.toString()) {
              pendingRow = p;
              break;
            }
          }
          if (pendingRow == null) continue;
          for (final r in createResults) {
            if (_createSyncSucceeded(r, localId)) {
              await _applySuccessfulCreate(
                pendingRow: pendingRow,
                syncResult: r,
                storeId: storeId,
              );
              break;
            }
          }
        }

        for (final u in bulkUpdates) {
          final localId = u['local_id'];
          final ok = updateResults.any(
            (r) =>
                _syncLocalIdMatch(r['local_id'], localId) &&
                r['status'] == 'success',
          );
          if (ok) {
            final id = localId is int
                ? localId
                : int.tryParse(localId.toString());
            if (id != null) await OfflineService.removePending(id);
          }
        }

        for (final d in deletes) {
          final localId = d['id'];
          final ok = deleteResults.any(
            (r) =>
                _syncLocalIdMatch(r['local_id'], localId) &&
                r['status'] == 'success',
          );
          if (ok) {
            final id = localId is int
                ? localId
                : int.tryParse(localId.toString());
            if (id != null) await OfflineService.clearPendingDelete(id);
          }
        }

        for (final s in stockChanges) {
          final localId = s['id'];
          final ok = stockResults.any(
            (r) =>
                _syncLocalIdMatch(r['local_id'], localId) &&
                r['status'] == 'success',
          );
          if (ok) {
            final id = localId is int
                ? localId
                : int.tryParse(localId.toString());
            if (id != null) await OfflineService.markStockChangeSynced(id);
          }
        }
      } else {
        final err = data['error']?.toString() ??
            data['details']?.toString() ??
            'Sync failed (${response.statusCode})';
        throw Exception(err);
      }
    }

    await OfflineService.remapAllQueuedOrderItems();

    try {
      await fetchProducts(storeId, useCache: false);
    } catch (_) {}

    final summary = _summarizeSyncResults(results);
    results.addAll(summary);

    if (summary['failed'] > 0 && summary['succeeded'] == 0) {
      throw Exception(
        summary['message']?.toString() ?? 'Product sync failed',
      );
    }

    return results;
  }

  /// Sync inventory, remap receipts, upload orders, then manual stock adjustments.
  static Future<Map<String, dynamic>> syncStore(int storeId) async {
    Map<String, dynamic> productResults;
    try {
      productResults = await syncPendingChanges(
        storeId,
        includeStockChanges: false,
      );
    } catch (e) {
      productResults = {'status': 'error', 'error': e.toString()};
    }

    await OfflineService.remapAllQueuedOrderItems();
    final orderResults = await OrderService.syncPendingOrders();

    Map<String, dynamic> stockResults = {'status': 'nothing_to_sync'};
    try {
      stockResults = await syncPendingStockChanges(storeId);
    } catch (e) {
      stockResults = {'status': 'error', 'error': e.toString()};
    }

    try {
      await fetchProducts(storeId, useCache: false);
    } catch (_) {}

    return {
      'products': productResults,
      'orders': orderResults,
      'stock': stockResults,
    };
  }

  /// Applies queued manual stock adjustments (run after orders are synced).
  static Future<Map<String, dynamic>> syncPendingStockChanges(int storeId) async {
    if (!await _isOnline()) {
      throw Exception('Cannot sync while offline');
    }

    final stockChanges = await OfflineService.getUnsyncedStockChanges();
    if (stockChanges.isEmpty) {
      return {'status': 'nothing_to_sync'};
    }

    final body = <String, dynamic>{
      'creates': <Map<String, dynamic>>[],
      'updates': <Map<String, dynamic>>[],
      'deletes': <Map<String, dynamic>>[],
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
    if (response.statusCode != 200) {
      throw Exception(
        data['error']?.toString() ?? 'Stock sync failed (${response.statusCode})',
      );
    }

    final stockResults = _parseSyncResultList(data['stock_changes']);
    for (final s in stockChanges) {
      final localId = s['id'];
      final ok = stockResults.any(
        (r) =>
            _syncLocalIdMatch(r['local_id'], localId) &&
            r['status'] == 'success',
      );
      if (ok) {
        final id = localId is int ? localId : int.tryParse(localId.toString());
        if (id != null) await OfflineService.markStockChangeSynced(id);
      }
    }

    return {
      'status': 'synced',
      'stock_changes': stockResults,
    };
  }

  static List<Map<String, dynamic>> _parseSyncResultList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static bool _syncLocalIdMatch(dynamic a, dynamic b) =>
      a != null && b != null && a.toString() == b.toString();

  static int? _serverIdFromSyncResult(Map<String, dynamic> r) {
    final direct = r['server_id'] ?? r['product']?['id'];
    if (direct is int) return direct;
    return int.tryParse(direct?.toString() ?? '');
  }

  static bool _createSyncSucceeded(Map<String, dynamic> r, dynamic localId) {
    if (!_syncLocalIdMatch(r['local_id'], localId)) return false;
    if (r['status'] == 'success') return true;
    return _serverIdFromSyncResult(r) != null;
  }

  static Future<void> _applySuccessfulCreate({
    required Map<String, dynamic> pendingRow,
    required Map<String, dynamic> syncResult,
    required int storeId,
  }) async {
    final pendingRowId = pendingRow['id'];
    final localId = pendingRowId is int
        ? pendingRowId
        : int.tryParse(pendingRowId?.toString() ?? '');
    if (localId == null) return;

    final serverId = _serverIdFromSyncResult(syncResult);
    if (serverId == null || serverId <= 0) return;

    await OfflineService.saveProductIdMapping(
      pendingRowId: localId,
      serverId: serverId,
      barcode: pendingRow['barcode']?.toString(),
      storeId: storeId,
    );
    await OfflineService.removePending(localId);

    final product = syncResult['product'];
    if (product is Map<String, dynamic>) {
      await OfflineService.cacheProducts(storeId, [product]);
    }
  }

  static Map<String, dynamic> _summarizeSyncResults(
    Map<String, dynamic> results,
  ) {
    var succeeded = 0;
    var failed = 0;
    final errors = <String>[];

    for (final key in ['creates', 'updates', 'deletes', 'stock_changes']) {
      final list = results[key];
      if (list is! List) continue;
      for (final raw in list) {
        if (raw is! Map) continue;
        final r = Map<String, dynamic>.from(raw);
        if (r['status'] == 'success' || _serverIdFromSyncResult(r) != null) {
          succeeded++;
        } else if (r['status'] == 'error') {
          failed++;
          final err = r['error']?.toString();
          if (err != null && err.isNotEmpty) errors.add(err);
        }
      }
    }

    return {
      'succeeded': succeeded,
      'failed': failed,
      if (errors.isNotEmpty) 'message': errors.first,
    };
  }

  // ============================================================
  // IMAGE HELPERS
  // ============================================================

  static bool _pendingHasImages(Map<String, dynamic> pending) {
    return _extractImageFiles(pending).isNotEmpty;
  }

  static List<File> _extractImageFiles(Map<String, dynamic> pending) {
    final paths = <String>[];

    void addPath(dynamic value) {
      if (value is String && value.isNotEmpty) {
        paths.add(value);
      }
    }

    final raw = pending['image_paths'];
    if (raw is String) {
      try {
        for (final item in jsonDecode(raw) as List<dynamic>) {
          addPath(item);
        }
      } catch (_) {}
    } else if (raw is List) {
      for (final item in raw) {
        addPath(item);
      }
    }

    addPath(pending['image_path']);

    return paths
        .map((p) => File(p))
        .where((f) => f.existsSync())
        .toList();
  }

  static List<String>? _extractExistingImages(Map<String, dynamic> pending) {
    final raw = pending['existing_images'];
    if (raw is String) {
      try {
        return (jsonDecode(raw) as List<dynamic>).whereType<String>().toList();
      } catch (_) {
        return null;
      }
    }
    if (raw is List) {
      return raw.whereType<String>().where((p) => p.isNotEmpty).toList();
    }
    return null;
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

  static Future<Product> createProduct({
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
    bool? listOnline,
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
    if (listOnline != null) request.fields['list_online'] = listOnline.toString();
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
    if (response.statusCode == 201) {
      final storeId = await ApiService.getMyStoreId();
      if (storeId != null) {
        await OfflineService.cacheProducts(storeId, [data]);
      } else {
        StoreCatalogService.instance.notifyChanged();
      }
      return Product.fromJson(data);
    }
    final limitErr = SubscriptionService.parseLimitError(response.statusCode, data);
    if (limitErr != null) throw limitErr;
    throw Exception(data['error']?.toString() ?? data['message']?.toString() ?? 'Failed');
  }

  static Future<Product> updateProduct({
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
    bool? listOnline,
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
    if (listOnline != null) request.fields['list_online'] = listOnline.toString();
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
    if (response.statusCode == 200) {
      await OfflineService.updateCachedProduct(data);
      return Product.fromJson(data);
    }
    final limitErr = SubscriptionService.parseLimitError(response.statusCode, data);
    if (limitErr != null) throw limitErr;
    throw Exception(data['error']?.toString() ?? data['message']?.toString() ?? 'Failed');
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
    await OfflineService.removeCachedProduct(id);
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

  /// Merges local/cached paths, product.images, image_url, and product_images rows.
  static Future<List<String>> resolveProductImages(
    Map<String, dynamic> product,
  ) async {
    final seen = <String>{};
    final merged = <String>[];

    void addAll(Iterable<String> paths) {
      for (final path in paths) {
        final trimmed = path.trim();
        if (trimmed.isEmpty || seen.contains(trimmed)) continue;
        seen.add(trimmed);
        merged.add(trimmed);
      }
    }

    addAll(OfflineService.getProductImagePaths(product));

    final id = product['id'];
    final productId = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (productId == null || productId <= 0) return merged;

    if (merged.length <= 1) {
      try {
        final detail = await MarketplaceService.fetchProductDetail(productId);
        if (detail != null) {
          addAll(OfflineService.getProductImagePaths(detail.toJson()));
        }
      } catch (_) {}
    }

    if (merged.length <= 1) {
      try {
        final rows = await fetchProductImages(productId);
        final urls = rows
            .whereType<Map>()
            .map((row) => row['image_url']?.toString() ?? '')
            .where((url) => url.isNotEmpty);
        addAll(urls);
      } catch (_) {}
    }

    return merged;
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

  static Future<Product?> lookupBarcode(String barcode) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/products/barcode/$barcode',
      headers: ApiService.publicHeaders,
    );
    if (response.statusCode == 200) {
      return Product.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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

  static Future<Product> findProductByBarcode(
    String barcode,
  ) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/products/barcode/$barcode',
      headers: ApiService.publicHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return Product.fromJson(data);
    throw Exception(data['error']?.toString() ?? 'Product not found');
  }

  // ============================================================
  // PRODUCT SEARCH
  // ============================================================

  static Future<List<Product>> searchStoreProducts({
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
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => Product.fromJson(m))
          .toList();
    }
    return [];
  }
}
