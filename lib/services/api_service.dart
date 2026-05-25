// lib/services/api_service.dart
import 'dart:convert';
import 'dart:typed_data';
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

  static Future<void> setGuest(bool isGuest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', isGuest);
  }

  static Future<bool> isGuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_guest') ?? false;
  }

  static Future<bool> isLoggedInOrGuest() async {
    return (await isLoggedIn()) || (await isGuest());
  }

  static Future<void> logoutGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_guest');
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
    throw Exception(
      data['error']?.toString() ?? data['message']?.toString() ?? response.body,
    );
  }

  static Future<Map<String, dynamic>> guestLogin() async {
    final response = await _postWithTimeout(
      '$baseUrl/api/auth/guest-login',
      headers: headers,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      final token = data['token']?.toString();
      if (token != null) await setToken(token);
      return data;
    }
    throw Exception(data['error']?.toString() ?? 'Guest login failed');
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

  static Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) async {
    final response = await _postWithTimeout(
      '$baseUrl/api/auth/verify-email',
      headers: headers,
      body: jsonEncode({'email': email, 'code': code}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Verification failed');
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
  // CATEGORIES
  // ============================================================

  static Future<List<dynamic>> fetchCategories() async {
    final response = await _getWithTimeout(
      '$baseUrl/api/categories',
      headers: publicHeaders,
      useCache: true,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed to load categories');
  }

  // ============================================================
  // BARCODE
  // ============================================================

  static Future<Map<String, dynamic>?> lookupBarcode(String barcode) async {
    final response = await _getWithTimeout(
      '$baseUrl/api/products/barcode/$barcode',
      headers: publicHeaders,
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
        '$baseUrl/api/products/check-barcode?barcode=${Uri.encodeComponent(barcode)}';
    if (excludeId != null) url += '&exclude_id=$excludeId';
    final response = await _getWithTimeout(url, headers: publicHeaders);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Barcode check failed');
  }

  static Future<Map<String, dynamic>?> validateBarcode(String barcode) async {
    final response = await _getWithTimeout(
      '$baseUrl/api/products/barcode/validate?code=${Uri.encodeComponent(barcode)}',
      headers: publicHeaders,
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
    final response = await _getWithTimeout(
      '$baseUrl/api/products/barcode/$barcode',
      headers: publicHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Product not found');
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
    int? categoryId,
    int? lowStockThreshold,
    File? image,
    List<File>? extraImages,
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
    if (categoryId != null)
      request.fields['category_id'] = categoryId.toString();
    if (lowStockThreshold != null)
      request.fields['low_stock_threshold'] = lowStockThreshold.toString();
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
    if (categoryId != null)
      request.fields['category_id'] = categoryId.toString();
    if (lowStockThreshold != null)
      request.fields['low_stock_threshold'] = lowStockThreshold.toString();
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

  static Future<Map<String, dynamic>> updateMyStore({
    String? name,
    String? city,
    String? village,
    String? country,
    String? phone,
    double? lat,
    double? lng,
    String? cityId,
    String? countryCode,
    String? villageId,
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
    if (cityId != null) request.fields['city_id'] = cityId;
    if (countryCode != null) request.fields['country_code'] = countryCode;
    if (villageId != null) request.fields['village_id'] = villageId;
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
  // PRODUCT IMAGES
  // ============================================================

  static Future<List<dynamic>> fetchProductImages(int productId) async {
    final response = await _getWithTimeout(
      '$baseUrl/api/products/$productId/images',
      headers: publicHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  static Future<void> uploadProductImage(int productId, File image) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/products/$productId/images'),
    );
    request.headers.addAll(await multipartAuthHeaders);
    request.files.add(await http.MultipartFile.fromPath('image', image.path));
    final streamed = await request.send().timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 201) {
      throw Exception('Image upload failed');
    }
  }

  // ============================================================
  // CHECKOUT & ORDERS
  // ============================================================

  static Future<Map<String, dynamic>> checkout({
    required List<Map<String, dynamic>> items,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final response = await _postWithTimeout(
      '$baseUrl/api/checkout',
      headers: await authHeaders,
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
    double discount = 0,
    double tax = 0,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'items': items,
      'discount': discount,
      'tax': tax,
      'payment_method': paymentMethod,
    };
    if (customerName != null) body['customer_name'] = customerName;
    if (customerPhone != null) body['customer_phone'] = customerPhone;
    if (notes != null) body['notes'] = notes;

    final response = await _postWithTimeout(
      '$baseUrl/api/orders',
      headers: await authHeaders,
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
    final response = await _getWithTimeout(
      '$baseUrl/api/orders?limit=$limit&offset=$offset',
      headers: await authHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed to load orders');
  }

  static Future<Map<String, dynamic>> fetchOrder(int id) async {
    final response = await _getWithTimeout(
      '$baseUrl/api/orders/$id',
      headers: await authHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Order not found');
  }

  // ============================================================
  // RECEIPT SETTINGS
  // ============================================================

  static Future<Map<String, dynamic>> getReceiptSettings() async {
    final response = await _getWithTimeout(
      '$baseUrl/api/my-store/receipt-settings',
      headers: await authHeaders,
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

    final response = await _putWithTimeout(
      '$baseUrl/api/my-store/receipt-settings',
      headers: await authHeaders,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Update failed');
  }

  // ============================================================
  // PRODUCT SEARCH (for checkout)
  // ============================================================

  static Future<List<dynamic>> searchStoreProducts({
    required String query,
    int? storeId,
    int limit = 20,
  }) async {
    final url = storeId != null
        ? '$baseUrl/api/products/$storeId/search?q=${Uri.encodeComponent(query)}&limit=$limit'
        : '$baseUrl/api/products/search?q=${Uri.encodeComponent(query)}&limit=$limit';
    final response = await _getWithTimeout(
      url,
      headers: publicHeaders,
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  // ============================================================
  // LOW STOCK ALERTS
  // ============================================================

  static Future<List<dynamic>> fetchLowStockProducts() async {
    final response = await _getWithTimeout(
      '$baseUrl/api/my-store/low-stock',
      headers: await authHeaders,
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
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

  // ============================================================
  // GEOCODING / CANONICAL LOCATIONS
  // ============================================================

  static Future<List<dynamic>> geocodeSearch(String query, String lang) async {
    final response = await _getWithTimeout(
      '$baseUrl/api/geocode/search?q=${Uri.encodeComponent(query)}&lang=$lang',
      headers: publicHeaders,
      timeout: const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Geocode search failed');
  }

  static Future<Map<String, dynamic>> reverseGeocode(
    double lat,
    double lng,
    String lang,
  ) async {
    final response = await _getWithTimeout(
      '$baseUrl/api/geocode/reverse?lat=$lat&lng=$lng&lang=$lang',
      headers: publicHeaders,
      timeout: const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Reverse geocode failed');
  }

  // ============================================================
  // IMAGE SEARCH
  // ============================================================

  // ============================================================
  // VISUAL SIMILARITY SEARCH (CLIP embeddings)
  // ============================================================

  static Future<Map<String, dynamic>> searchByImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/search/image-similarity'),
      );
      request.headers.addAll(await multipartAuthHeaders);

      final ext = mimeType == 'image/png'
          ? '.png'
          : mimeType == 'image/webp'
          ? '.webp'
          : mimeType == 'image/gif'
          ? '.gif'
          : '.jpg';

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'search$ext',
        ),
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw ApiTimeoutException(
            'Image similarity search timed out after 30s',
          );
        },
      );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(
          data['error']?.toString() ??
              'Image search failed (${response.statusCode})',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      if (kDebugMode) print('Image search error: ' + e.toString());
      rethrow;
    }
  }
}

class ApiTimeoutException implements Exception {
  final String message;
  ApiTimeoutException(this.message);
  @override
  String toString() => message;
}
