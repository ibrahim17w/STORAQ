// lib/services/favorites_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class FavoritesService {
  static const String _localKey = 'local_favorite_ids';
  static const String _cacheKey = 'cached_favorites';

  static Future<List<dynamic>> fetchFavorites() async {
    try {
      final response = await ApiService.authGet('/favorites');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = decoded is List
            ? decoded
            : (decoded['data'] as List? ?? []);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(list));
        return list;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      return jsonDecode(cached) as List<dynamic>;
    }
    return [];
  }

  static Future<void> addFavorite(int productId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getLocalFavoriteIds();
    if (!ids.contains(productId)) {
      ids.add(productId);
      await prefs.setString(_localKey, jsonEncode(ids));
    }
    try {
      await ApiService.authPost('/favorites', {'product_id': productId});
    } catch (_) {}
  }

  static Future<void> removeFavorite(int productId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getLocalFavoriteIds();
    ids.remove(productId);
    await prefs.setString(_localKey, jsonEncode(ids));
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
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> toggleFavorite(int productId) async {
    if (await isFavorite(productId)) {
      await removeFavorite(productId);
    } else {
      await addFavorite(productId);
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
}
