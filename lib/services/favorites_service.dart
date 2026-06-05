import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class FavoritesService {
  // ── Product keys (existing — kept for backward compat) ──
  static const String _localKey = 'local_favorite_ids';
  static const String _cacheKey = 'cached_favorites';
  static const String _productCacheKey = 'cached_favorite_products_map';

  // ── Store keys (new) ──
  static const String _localStoreKey = 'local_favorite_store_ids';
  static const String _cacheStoreKey = 'cached_favorite_stores';
  static const String _storeCacheKey = 'cached_favorite_stores_map';

  /// Global notifier for product favorite changes.
  static final ValueNotifier<Set<int>> favoriteIdsNotifier =
      ValueNotifier<Set<int>>({});

  /// Global notifier for store favorite changes.
  static final ValueNotifier<Set<int>> favoriteStoreIdsNotifier =
      ValueNotifier<Set<int>>({});

  /// Call once at app startup (e.g. in main.dart after auth init)
  static Future<void> init() async {
    final productIds = await getLocalFavoriteIds();
    favoriteIdsNotifier.value = productIds.toSet();
    final storeIds = await getLocalFavoriteStoreIds();
    favoriteStoreIdsNotifier.value = storeIds.toSet();
  }

  // ============================================================
  // PRODUCTS (existing logic, unchanged public API)
  // ============================================================

  static Future<List<dynamic>> fetchFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> serverList = [];
    bool serverOk = false;

    try {
      final response = await ApiService.authGet('/favorites');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        serverList = decoded is List
            ? decoded
            : (decoded['data'] as List? ?? []);
        serverOk = true;
      }
    } catch (_) {
      serverOk = false;
    }

    Map<String, dynamic> localProductMap = {};
    final rawProductCache = prefs.getString(_productCacheKey);
    if (rawProductCache != null && rawProductCache.isNotEmpty) {
      try {
        localProductMap = jsonDecode(rawProductCache) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (serverOk) {
      final Set<int> serverIds = {};
      for (final product in serverList) {
        final dynamic rawId = product['id'];
        if (rawId == null) continue;
        final String idStr = rawId.toString();
        localProductMap[idStr] = product;
        final intId = rawId is int ? rawId : int.tryParse(idStr) ?? 0;
        if (intId > 0) serverIds.add(intId);
      }
      await prefs.setString(_productCacheKey, jsonEncode(localProductMap));

      final mergedList = List<dynamic>.from(serverList);
      final localIds = await getLocalFavoriteIds();

      for (final localId in localIds) {
        if (!serverIds.contains(localId)) {
          final localProduct = localProductMap[localId.toString()];
          if (localProduct != null) {
            final alreadyInList = mergedList.any((p) {
              final pid = p['id'];
              final intPid = pid is int
                  ? pid
                  : int.tryParse(pid.toString()) ?? 0;
              return intPid == localId;
            });
            if (!alreadyInList) {
              mergedList.add(localProduct);
            }
          }
        }
      }

      await prefs.setString(_cacheKey, jsonEncode(mergedList));

      final allIds = mergedList
          .map((p) => p['id'])
          .where((id) => id != null)
          .map((id) => id is int ? id : int.tryParse(id.toString()) ?? 0)
          .where((id) => id > 0)
          .toList();
      await prefs.setString(_localKey, jsonEncode(allIds));
      favoriteIdsNotifier.value = allIds.toSet();

      return mergedList;
    }

    final cached = prefs.getString(_cacheKey);
    if (cached != null && cached.isNotEmpty && cached != '[]') {
      try {
        final list = jsonDecode(cached) as List<dynamic>;
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }

    final fallback = localProductMap.values.toList();
    if (fallback.isNotEmpty) {
      await prefs.setString(_cacheKey, jsonEncode(fallback));
    }
    return fallback;
  }

  static Future<void> addFavorite(
    int productId, {
    Map<String, dynamic>? product,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getLocalFavoriteIds();
    if (!ids.contains(productId)) {
      ids.add(productId);
      await prefs.setString(_localKey, jsonEncode(ids));
    }

    if (product != null) {
      final raw = prefs.getString(_productCacheKey);
      Map<String, dynamic> map = {};
      if (raw != null && raw.isNotEmpty) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      map[productId.toString()] = product;
      await prefs.setString(_productCacheKey, jsonEncode(map));

      final rawCache = prefs.getString(_cacheKey);
      List<dynamic> cacheList = [];
      if (rawCache != null && rawCache.isNotEmpty) {
        try {
          cacheList = jsonDecode(rawCache) as List<dynamic>;
        } catch (_) {}
      }
      final exists = cacheList.any((p) {
        final pid = p['id'];
        final intPid = pid is int ? pid : int.tryParse(pid.toString()) ?? 0;
        return intPid == productId;
      });
      if (!exists) {
        cacheList.add(product);
        await prefs.setString(_cacheKey, jsonEncode(cacheList));
      }
    }

    final newSet = Set<int>.from(favoriteIdsNotifier.value);
    newSet.add(productId);
    favoriteIdsNotifier.value = newSet;

    try {
      await ApiService.authPost('/favorites', {'product_id': productId});
    } catch (_) {}
  }

  static Future<void> removeFavorite(int productId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getLocalFavoriteIds();
    ids.remove(productId);
    await prefs.setString(_localKey, jsonEncode(ids));

    final raw = prefs.getString(_productCacheKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.remove(productId.toString());
        await prefs.setString(_productCacheKey, jsonEncode(map));
      } catch (_) {}
    }

    final rawCache = prefs.getString(_cacheKey);
    if (rawCache != null && rawCache.isNotEmpty) {
      try {
        final cacheList = jsonDecode(rawCache) as List<dynamic>;
        final filtered = cacheList.where((p) {
          final pid = p['id'];
          final intPid = pid is int ? pid : int.tryParse(pid.toString()) ?? 0;
          return intPid != productId;
        }).toList();
        await prefs.setString(_cacheKey, jsonEncode(filtered));
      } catch (_) {}
    }

    final newSet = Set<int>.from(favoriteIdsNotifier.value);
    newSet.remove(productId);
    favoriteIdsNotifier.value = newSet;

    try {
      await ApiService.authDelete('/favorites/$productId');
    } catch (_) {}
  }

  static Future<bool> isFavorite(int productId) async {
    final ids = await getLocalFavoriteIds();
    return ids.contains(productId);
  }

  static Future<List<int>> getLocalFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
          .where((id) => id > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> toggleFavorite(
    int productId, {
    Map<String, dynamic>? product,
  }) async {
    if (await isFavorite(productId)) {
      await removeFavorite(productId);
    } else {
      await addFavorite(productId, product: product);
    }
  }

  static Future<void> syncLocalFavorites() async {
    if (!await ApiService.isLoggedIn()) return;
    final ids = await getLocalFavoriteIds();
    for (final id in ids) {
      try {
        await ApiService.authPost('/favorites', {'product_id': id});
      } catch (_) {}
    }
  }

  // ============================================================
  // STORES (new)
  // ============================================================

  static Future<List<dynamic>> fetchFavoriteStores() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> serverList = [];
    bool serverOk = false;

    try {
      final response = await ApiService.authGet('/favorites/stores');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        serverList = decoded is List
            ? decoded
            : (decoded['data'] as List? ?? []);
        serverOk = true;
      }
    } catch (_) {
      serverOk = false;
    }

    Map<String, dynamic> localStoreMap = {};
    final rawStoreCache = prefs.getString(_storeCacheKey);
    if (rawStoreCache != null && rawStoreCache.isNotEmpty) {
      try {
        localStoreMap = jsonDecode(rawStoreCache) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (serverOk) {
      final Set<int> serverIds = {};
      for (final store in serverList) {
        final dynamic rawId = store['id'];
        if (rawId == null) continue;
        final String idStr = rawId.toString();
        localStoreMap[idStr] = store;
        final intId = rawId is int ? rawId : int.tryParse(idStr) ?? 0;
        if (intId > 0) serverIds.add(intId);
      }
      await prefs.setString(_storeCacheKey, jsonEncode(localStoreMap));

      final mergedList = List<dynamic>.from(serverList);
      final localIds = await getLocalFavoriteStoreIds();

      for (final localId in localIds) {
        if (!serverIds.contains(localId)) {
          final localStore = localStoreMap[localId.toString()];
          if (localStore != null) {
            final alreadyInList = mergedList.any((s) {
              final sid = s['id'];
              final intSid = sid is int
                  ? sid
                  : int.tryParse(sid.toString()) ?? 0;
              return intSid == localId;
            });
            if (!alreadyInList) {
              mergedList.add(localStore);
            }
          }
        }
      }

      await prefs.setString(_cacheStoreKey, jsonEncode(mergedList));

      final allIds = mergedList
          .map((s) => s['id'])
          .where((id) => id != null)
          .map((id) => id is int ? id : int.tryParse(id.toString()) ?? 0)
          .where((id) => id > 0)
          .toList();
      await prefs.setString(_localStoreKey, jsonEncode(allIds));
      favoriteStoreIdsNotifier.value = allIds.toSet();

      return mergedList;
    }

    final cached = prefs.getString(_cacheStoreKey);
    if (cached != null && cached.isNotEmpty && cached != '[]') {
      try {
        final list = jsonDecode(cached) as List<dynamic>;
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }

    final fallback = localStoreMap.values.toList();
    if (fallback.isNotEmpty) {
      await prefs.setString(_cacheStoreKey, jsonEncode(fallback));
    }
    return fallback;
  }

  static Future<void> addFavoriteStore(
    int storeId, {
    Map<String, dynamic>? store,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getLocalFavoriteStoreIds();
    if (!ids.contains(storeId)) {
      ids.add(storeId);
      await prefs.setString(_localStoreKey, jsonEncode(ids));
    }

    if (store != null) {
      final raw = prefs.getString(_storeCacheKey);
      Map<String, dynamic> map = {};
      if (raw != null && raw.isNotEmpty) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      map[storeId.toString()] = store;
      await prefs.setString(_storeCacheKey, jsonEncode(map));

      final rawCache = prefs.getString(_cacheStoreKey);
      List<dynamic> cacheList = [];
      if (rawCache != null && rawCache.isNotEmpty) {
        try {
          cacheList = jsonDecode(rawCache) as List<dynamic>;
        } catch (_) {}
      }
      final exists = cacheList.any((s) {
        final sid = s['id'];
        final intSid = sid is int ? sid : int.tryParse(sid.toString()) ?? 0;
        return intSid == storeId;
      });
      if (!exists) {
        cacheList.add(store);
        await prefs.setString(_cacheStoreKey, jsonEncode(cacheList));
      }
    }

    final newSet = Set<int>.from(favoriteStoreIdsNotifier.value);
    newSet.add(storeId);
    favoriteStoreIdsNotifier.value = newSet;

    try {
      await ApiService.authPost('/favorites/stores', {'store_id': storeId});
    } catch (_) {}
  }

  static Future<void> removeFavoriteStore(int storeId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getLocalFavoriteStoreIds();
    ids.remove(storeId);
    await prefs.setString(_localStoreKey, jsonEncode(ids));

    final raw = prefs.getString(_storeCacheKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.remove(storeId.toString());
        await prefs.setString(_storeCacheKey, jsonEncode(map));
      } catch (_) {}
    }

    final rawCache = prefs.getString(_cacheStoreKey);
    if (rawCache != null && rawCache.isNotEmpty) {
      try {
        final cacheList = jsonDecode(rawCache) as List<dynamic>;
        final filtered = cacheList.where((s) {
          final sid = s['id'];
          final intSid = sid is int ? sid : int.tryParse(sid.toString()) ?? 0;
          return intSid != storeId;
        }).toList();
        await prefs.setString(_cacheStoreKey, jsonEncode(filtered));
      } catch (_) {}
    }

    final newSet = Set<int>.from(favoriteStoreIdsNotifier.value);
    newSet.remove(storeId);
    favoriteStoreIdsNotifier.value = newSet;

    try {
      await ApiService.authDelete('/favorites/stores/$storeId');
    } catch (_) {}
  }

  static Future<bool> isFavoriteStore(int storeId) async {
    final ids = await getLocalFavoriteStoreIds();
    return ids.contains(storeId);
  }

  static Future<List<int>> getLocalFavoriteStoreIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localStoreKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
          .where((id) => id > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> toggleFavoriteStore(
    int storeId, {
    Map<String, dynamic>? store,
  }) async {
    if (await isFavoriteStore(storeId)) {
      await removeFavoriteStore(storeId);
    } else {
      await addFavoriteStore(storeId, store: store);
    }
  }

  static Future<void> syncLocalFavoriteStores() async {
    if (!await ApiService.isLoggedIn()) return;
    final ids = await getLocalFavoriteStoreIds();
    for (final id in ids) {
      try {
        await ApiService.authPost('/favorites/stores', {'store_id': id});
      } catch (_) {}
    }
  }
}
