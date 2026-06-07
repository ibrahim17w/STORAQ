// lib/services/auth_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'api_service.dart';
import 'offline_service.dart';
import 'store_service.dart';
import 'product_service.dart';
import 'order_service.dart';

class AuthService {
  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String role,
    Map<String, dynamic>? store,
    String preferredLanguage = 'en',
    String? turnstileToken,
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
    if (turnstileToken != null) body['turnstile_token'] = turnstileToken;

    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/auth/register',
      headers: ApiService.headers,
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
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/auth/login',
      headers: ApiService.headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      final token =
          (data['token'] ?? data['access_token'] ?? data['auth_token'])
              ?.toString();
      if (token == null || token.isEmpty) {
        throw Exception(
          'Login succeeded but server did not return a token. '
          'Check backend response field name.',
        );
      }
      await ApiService.setToken(token);
      await ApiService.setGuest(false);

      final storeCtx = data['user']?['store'] as Map<String, dynamic>?;
      if (storeCtx != null) await ApiService.setStoreContext(storeCtx);

      // Cache user for offline fallback
      if (data['user'] != null) {
        await OfflineService.cacheUser(data['user'] as Map<String, dynamic>);
      }

      await warmOfflineStoreData();

      return data;
    }
    throw Exception(
      data['error']?.toString() ?? data['message']?.toString() ?? response.body,
    );
  }

  static Future<Map<String, dynamic>> guestLogin() async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/auth/guest-login',
      headers: ApiService.headers,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      final token = data['token']?.toString();
      if (token != null) await ApiService.setToken(token);
      await ApiService.setGuest(true);
      await ApiService.clearStoreContext();
      return data;
    }
    throw Exception(data['error']?.toString() ?? 'Guest login failed');
  }

  static Future<void> logout() async {
    await ApiService.clearToken();
    await OfflineService.clearSessionCache();
  }

  static Future<void> resendVerification(String email) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/auth/resend-verification',
      headers: ApiService.headers,
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
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/auth/verify-email',
      headers: ApiService.headers,
      body: jsonEncode({'email': email, 'code': code}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Verification failed');
  }

  static Future<void> forgotPassword(String email) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/auth/forgot-password',
      headers: ApiService.headers,
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
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/auth/reset-password',
      headers: ApiService.headers,
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
  // USER PROFILE (moved from original ApiService)
  // ============================================================

  static Future<User> getCurrentUser() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/me',
      headers: await ApiService.authHeaders,
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      // Defensive fallback: inject cached store context if server omitted it
      if (data['store'] == null) {
        final cachedCtx = await ApiService.getStoreContext();
        if (cachedCtx != null) data['store'] = cachedCtx;
      }
      // Cache user for offline
      await OfflineService.cacheUser(data);
      return User.fromJson(data);
    }
    throw Exception(data['error']?.toString() ?? 'Failed');
  }

  static Future<User> uploadAvatar(File image) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/api/me/avatar'),
    );
    request.headers.addAll(await ApiService.multipartAuthHeaders);
    request.files.add(
      await http.MultipartFile.fromPath('avatar', image.path),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      await OfflineService.cacheUser(data);
      return User.fromJson(data);
    }
    throw Exception(data['error']?.toString() ?? 'Avatar upload failed');
  }

  static Future<User> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    final response = await ApiService.putWithTimeout(
      '${ApiService.baseUrl}/api/me',
      headers: await ApiService.authHeaders,
      body: jsonEncode({'full_name': fullName, 'phone': phone}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      await OfflineService.cacheUser(data);
      return User.fromJson(data);
    }
    throw Exception(data['error']?.toString() ?? 'Update failed');
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await ApiService.putWithTimeout(
      '${ApiService.baseUrl}/api/me/password',
      headers: await ApiService.authHeaders,
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
        .delete(
          Uri.parse('${ApiService.baseUrl}/api/me'),
          headers: await ApiService.authHeaders,
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      await ApiService.clearToken();
    } else {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Failed');
    }
  }

  static Future<void> updatePreferredLanguage(String lang) async {
    final response = await ApiService.putWithTimeout(
      '${ApiService.baseUrl}/api/me/language',
      headers: await ApiService.authHeaders,
      body: jsonEncode({'preferred_language': lang}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update language');
    }
  }

  /// Downloads store catalog, receipt settings, and recent orders for offline use.
  static Future<void> warmOfflineStoreData() async {
    try {
      final store = await StoreService.getMyStore();
      final storeId = store.intId;
      if (storeId == null) return;
      await ProductService.loadStoreCatalog(storeId, forceRefresh: true);
      await OrderService.loadReceiptSettings();
      try {
        await OrderService.fetchOrders(limit: 100, offset: 0);
      } catch (_) {}
    } catch (_) {}
  }
}
