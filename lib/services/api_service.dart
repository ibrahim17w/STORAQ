import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
    return 'https://market-bridge-baug.onrender.com';
  }

  static final Map<String, dynamic> _cache = {};
  static final Map<String, DateTime> _cacheTime = {};
  static const Duration _cacheDuration = Duration(minutes: 2);

  static Map<String, String> get publicHeaders => {
    'Content-Type': 'application/json',
  };

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
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

  // ============================================================
  // HTTP HELPERS WITH TIMEOUT
  // ============================================================

  static Future<http.Response> _getWithTimeout(
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
        return http.Response(jsonEncode(_cache[cacheKey]), 200);
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

    if (useCache && response.statusCode == 200) {
      try {
        _cache[cacheKey] = jsonDecode(response.body);
        _cacheTime[cacheKey] = DateTime.now();
      } catch (_) {}
    }

    return response;
  }

  static Future<http.Response> _postWithTimeout(
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

  // FIX: Added PUT helper to match backend endpoints
  static Future<http.Response> _putWithTimeout(
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

  // ============================================================
  // AUTH
  // ============================================================

  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String role,
    Map<String, dynamic>? store,
    String preferredLanguage = 'en',
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'password': password,
      'role': role,
      'preferred_language': preferredLanguage,
    };
    if (store != null) body['store'] = store;

    final response = await _postWithTimeout(
      '$baseUrl/api/auth/register',
      headers: headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Registration failed');
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _postWithTimeout(
      '$baseUrl/api/auth/login',
      headers: headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      final token = data['token']?.toString();
      if (token != null) await setToken(token);
      return data;
    }
    // FIX: Show actual server response body for debugging instead of generic "Login failed"
    throw Exception(
      data['error']?.toString() ?? data['message']?.toString() ?? response.body,
    );
  }

  static Future<void> logout() async => clearToken();

  static Future<void> resendVerification(String email) async {
    final response = await _postWithTimeout(
      '$baseUrl/api/auth/resend-verification',
      headers: headers,
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Failed to resend');
    }
  }

  static Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await _getWithTimeout(
      '$baseUrl/api/me',
      headers: await authHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Failed');
  }

  // FIX: Use PUT instead of POST to match backend
  static Future<Map<String, dynamic>> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    final response = await _putWithTimeout(
      '$baseUrl/api/me',
      headers: await authHeaders,
      body: jsonEncode({'full_name': fullName, 'phone': phone}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Update failed');
  }

  // FIX: Use PUT instead of POST to match backend
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _putWithTimeout(
      '$baseUrl/api/me/password',
      headers: await authHeaders,
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Failed');
    }
  }

  static Future<void> deleteAccount() async {
    final response = await http
        .delete(Uri.parse('$baseUrl/api/me'), headers: await authHeaders)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      await clearToken();
    } else {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Failed');
    }
  }

  // FIX: Use PUT instead of POST to match backend
  static Future<void> updatePreferredLanguage(String lang) async {
    final response = await _putWithTimeout(
      '$baseUrl/api/me/language',
      headers: await authHeaders,
      body: jsonEncode({'preferred_language': lang}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update language');
    }
  }

  static Future<void> forgotPassword(String email) async {
    final response = await _postWithTimeout(
      '$baseUrl/api/auth/forgot-password',
      headers: headers,
      body: jsonEncode({'email': email}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed');
    }
  }

  static Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await _postWithTimeout(
      '$baseUrl/api/auth/reset-password',
      headers: headers,
      body: jsonEncode({
        'email': email,
        'code': code,
        'new_password': newPassword,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed');
    }
  }

  // ============================================================
  // STORES
  // ============================================================

  static Future<List<dynamic>> fetchStores() async {
    final response = await _getWithTimeout(
      '$baseUrl/api/stores',
      headers: publicHeaders,
      useCache: true,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed');
  }

  static Future<Map<String, dynamic>> fetchStore(int id) async {
    final response = await _getWithTimeout(
      '$baseUrl/api/stores/$id',
      headers: publicHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed');
  }

  static Future<Map<String, dynamic>> getMyStore() async {
    final response = await _getWithTimeout(
      '$baseUrl/api/my-store',
      headers: await authHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Failed');
  }

  // ============================================================
  // PRODUCTS
  // ============================================================

  static Future<List<dynamic>> fetchProducts(int storeId) async {
    final response = await _getWithTimeout(
      '$baseUrl/api/products/$storeId',
      headers: publicHeaders,
      useCache: true,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed');
  }

  static Future<Map<String, dynamic>> createProduct({
    required String name,
    required double price,
    required int quantity,
    String? description,
    String? barcode,
    File? image,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/products'),
    );
    request.headers.addAll(await multipartAuthHeaders);
    request.fields['name'] = name;
    request.fields['price'] = price.toString();
    request.fields['quantity'] = quantity.toString();
    if (description != null) request.fields['description'] = description;
    if (barcode != null) request.fields['barcode'] = barcode;
    if (image != null) {
      request.files.add(await http.MultipartFile.fromPath('image', image.path));
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
    File? image,
  }) async {
    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/products/$id'),
    );
    request.headers.addAll(await multipartAuthHeaders);
    request.fields['name'] = name;
    request.fields['price'] = price.toString();
    request.fields['quantity'] = quantity.toString();
    if (description != null) request.fields['description'] = description;
    if (barcode != null) request.fields['barcode'] = barcode;
    if (image != null) {
      request.files.add(await http.MultipartFile.fromPath('image', image.path));
    }

    final streamed = await request.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Failed');
  }

  static Future<Map<String, dynamic>> updateMyStore({
    String? name,
    String? city,
    String? village,
    String? country,
    String? phone,
    double? lat,
    double? lng,
    File? image,
  }) async {
    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/my-store'),
    );
    request.headers.addAll(await multipartAuthHeaders);
    if (name != null) request.fields['name'] = name;
    if (city != null) request.fields['city'] = city;
    if (village != null) request.fields['village'] = village;
    if (country != null) request.fields['country'] = country;
    if (phone != null) request.fields['phone'] = phone;
    if (lat != null) request.fields['lat'] = lat.toString();
    if (lng != null) request.fields['lng'] = lng.toString();
    if (image != null) {
      request.files.add(await http.MultipartFile.fromPath('image', image.path));
    }

    final streamed = await request.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('Server returned invalid data');
      }
    }

    String errorMsg;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      errorMsg =
          data['error']?.toString() ?? 'Failed (status ${response.statusCode})';
    } catch (_) {
      errorMsg =
          'Server error (${response.statusCode}). Please check your backend.';
    }
    throw Exception(errorMsg);
  }

  static Future<void> deleteProduct(int id) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/products/$id'),
          headers: await authHeaders,
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Failed');
    }
  }

  // ============================================================
  // MARKETPLACE & HOME SCREEN
  // ============================================================

  static Future<List<dynamic>> fetchMarketplaceFeed() async {
    final response = await _getWithTimeout(
      '$baseUrl/api/marketplace/feed',
      headers: publicHeaders,
      useCache: true,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed');
  }

  static Future<void> trackProductView(int productId) async {
    try {
      await _postWithTimeout(
        '$baseUrl/api/products/$productId/view',
        headers: await authHeaders,
      );
    } catch (_) {
      // Silently fail
    }
  }

  static Future<void> trackSearch(String query) async {
    try {
      await _postWithTimeout(
        '$baseUrl/api/search/track',
        headers: await authHeaders,
        body: jsonEncode({'query': query}),
      );
    } catch (_) {
      // Silently fail
    }
  }

  static Future<List<dynamic>> fetchTrendingProducts() async {
    try {
      final response = await _getWithTimeout(
        '$baseUrl/api/products/trending',
        headers: publicHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> fetchSponsoredStores() async {
    try {
      final response = await _getWithTimeout(
        '$baseUrl/api/stores/sponsored',
        headers: publicHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> fetchRecommendations() async {
    try {
      final response = await _getWithTimeout(
        '$baseUrl/api/recommendations',
        headers: await authHeaders,
        timeout: const Duration(seconds: 5),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  // NEW: Server-side geo filter for nearby products
  static Future<List<dynamic>> fetchNearbyProducts({
    required double lat,
    required double lng,
    double radiusKm = 15,
  }) async {
    try {
      final response = await _getWithTimeout(
        '$baseUrl/api/marketplace/nearby?lat=$lat&lng=$lng&radius=$radiusKm',
        headers: publicHeaders,
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }
}

// FIX: Renamed to avoid conflict with dart:async TimeoutException
class ApiTimeoutException implements Exception {
  final String message;
  ApiTimeoutException(this.message);
  @override
  String toString() => message;
}
