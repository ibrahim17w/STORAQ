import 'dart:convert';
import 'dart:core';
import 'dart:typed_data';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'prefs_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class ApiService {
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;

    if (kDebugMode) {
      if (Platform.isAndroid) return 'http://10.0.2.2:3000';
      if (Platform.isIOS) return 'http://localhost:3000';
      return 'http://localhost:3000';
    }
    return 'https://https://storaq.onrender.com';
  }

  static final Map<String, String> _cache = {};
  static final Map<String, DateTime> _cacheTime = {};
  static const Duration _cacheDuration = Duration(minutes: 2);

  static Map<String, String> get publicHeaders => {
    'Content-Type': 'application/json',
  };

  static Future<String?> getToken() async {
    final prefs = await PrefsService.instance;
    return prefs.getString('token');
  }

  static Future<void> setToken(String token) async {
    final prefs = await PrefsService.instance;
    await prefs.setString('token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await PrefsService.instance;
    await prefs.remove('token');
    await prefs.remove('store_context');
    await prefs.remove('is_guest');
  }

  static Future<void> setGuest(bool isGuest) async {
    final prefs = await PrefsService.instance;
    await prefs.setBool('is_guest', isGuest);
  }

  static Future<bool> isGuest() async {
    final prefs = await PrefsService.instance;
    return prefs.getBool('is_guest') ?? false;
  }

  static Future<bool> isLoggedInOrGuest() async {
    return (await isLoggedIn()) || (await isGuest());
  }

  static Future<void> logoutGuest() async {
    final prefs = await PrefsService.instance;
    await prefs.remove('is_guest');
    await prefs.remove('token');
    await prefs.remove('store_context');
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
  };

  static Future<Map<String, String>> get authHeaders async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> get multipartAuthHeaders async {
    final token = await getToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Future<Map<String, dynamic>?> decodeToken() async {
    final token = await getToken();
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    return jsonDecode(payload) as Map<String, dynamic>;
  }

  static Future<String?> getUserRole() async {
    final payload = await decodeToken();
    return payload?['role'] as String?;
  }

  // ==================== STORE CONTEXT (Owner / Worker) ====================

  static Future<void> setStoreContext(Map<String, dynamic> context) async {
    final prefs = await PrefsService.instance;
    await prefs.setString('store_context', jsonEncode(context));
  }

  static Future<Map<String, dynamic>?> getStoreContext() async {
    final prefs = await PrefsService.instance;
    final raw = prefs.getString('store_context');
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearStoreContext() async {
    final prefs = await PrefsService.instance;
    await prefs.remove('store_context');
  }

  static Future<bool> isStoreOwner() async {
    final ctx = await getStoreContext();
    return ctx?['role'] == 'owner';
  }

  static Future<bool> isStoreWorker() async {
    final ctx = await getStoreContext();
    return ctx?['role'] == 'worker';
  }

  static Future<bool> canManageInventory() async {
    final ctx = await getStoreContext();
    if (ctx == null) return false;
    if (ctx['role'] == 'owner') return true;
    return ctx['can_manage_inventory'] == true;
  }

  static Future<int?> getMyStoreId() async {
    final ctx = await getStoreContext();
    final id = ctx?['store_id'];
    if (id is int) return id;
    if (id is String) return int.tryParse(id);
    return null;
  }

  static Future<String?> getStoreStatus() async {
    final ctx = await getStoreContext();
    return ctx?['status']?.toString();
  }

  /// True only when the device has network and the API responds (not just Wi‑Fi).
  static Future<bool> isServerReachable() async {
    try {
      final connectivity = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 1),
      );
      if (connectivity.contains(ConnectivityResult.none)) return false;
    } catch (_) {
      return false;
    }

    try {
      final response = await http
          .head(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // AUTH HTTP HELPERS
  // ============================================================

  static Future<http.Response> authGet(String path) async {
    return await getWithTimeout(
      '$baseUrl/api$path',
      headers: await authHeaders,
    );
  }

  static Future<http.Response> authPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    return await postWithTimeout(
      '$baseUrl/api$path',
      headers: await authHeaders,
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> authPut(
    String path,
    Map<String, dynamic> body,
  ) async {
    return await putWithTimeout(
      '$baseUrl/api$path',
      headers: await authHeaders,
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> authDelete(String path) async {
    return await http
        .delete(Uri.parse('$baseUrl/api$path'), headers: await authHeaders)
        .timeout(const Duration(seconds: 8));
  }

  // ============================================================
  // HTTP HELPERS WITH TIMEOUT
  // ============================================================

  static Future<http.Response> getWithTimeout(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
    bool useCache = false,
  }) async {
    final cacheKey = 'GET:$url';

    if (useCache && _cache.containsKey(cacheKey)) {
      final cachedTime = _cacheTime[cacheKey];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) < _cacheDuration) {
        return http.Response(
          _cache[cacheKey]!,
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
    }

    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(
          timeout,
          onTimeout: () {
            throw ApiTimeoutException(
              'Request to $url timed out after ${timeout.inSeconds}s',
            );
          },
        );

    if (useCache && response.statusCode == 200 && response.body.isNotEmpty) {
      _cache[cacheKey] = response.body;
      _cacheTime[cacheKey] = DateTime.now();
    }

    return response;
  }

  static Future<http.Response> postWithTimeout(
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return await http
        .post(Uri.parse(url), headers: headers, body: body)
        .timeout(
          timeout,
          onTimeout: () {
            throw ApiTimeoutException(
              'Request to $url timed out after ${timeout.inSeconds}s',
            );
          },
        );
  }

  static Future<http.Response> putWithTimeout(
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return await http
        .put(Uri.parse(url), headers: headers, body: body)
        .timeout(
          timeout,
          onTimeout: () {
            throw ApiTimeoutException(
              'Request to $url timed out after ${timeout.inSeconds}s',
            );
          },
        );
  }
}

class ApiTimeoutException implements Exception {
  final String message;
  ApiTimeoutException(this.message);
  @override
  String toString() => message;
}
