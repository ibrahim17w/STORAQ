// lib/services/store_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'offline_service.dart';
import '../models/models.dart';

class StoreService {
  static Future<List<Store>> fetchStores() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/stores',
      headers: ApiService.publicHeaders,
      useCache: true,
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      List<dynamic> items;
      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map && decoded.containsKey('data')) {
        items = decoded['data'] as List<dynamic>;
      } else {
        items = [];
      }
      return items
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load stores');
  }

  static Future<Store> fetchStore(int id) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/stores/$id',
      headers: ApiService.publicHeaders,
    );
    if (response.statusCode == 200) {
      return Store.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Failed');
  }

  static Future<Store> getMyStore() async {
    try {
      final response = await ApiService.getWithTimeout(
        '${ApiService.baseUrl}/api/my-store',
        headers: await ApiService.authHeaders,
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        await OfflineService.cacheStore(data);
        return Store.fromJson(data);
      }
      throw Exception(data['error']?.toString() ?? 'Failed');
    } catch (e) {
      // Offline fallback: return cached store on ANY failure (network, server down, timeout)
      final storeId = await ApiService.getMyStoreId();
      final cached = storeId != null
          ? await OfflineService.getCachedStore(storeId: storeId)
          : await OfflineService.getCachedStore();
      if (cached != null) return Store.fromJson(cached);
      // Last resort: build minimal store from store context so UI doesn't crash
      final ctx = await ApiService.getStoreContext();
      if (storeId != null) {
        return Store.fromJson({
          'id': storeId,
          'name': ctx?['store_name'] ?? 'My Store',
          'role': ctx?['role'] ?? 'owner',
        });
      }
      rethrow;
    }
  }

  static Future<Store> updateMyStore({
    String? name,
    String? city,
    String? village,
    String? locationDescription,
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
      Uri.parse('${ApiService.baseUrl}/api/my-store'),
    );
    request.headers.addAll(await ApiService.multipartAuthHeaders);
    if (name != null) request.fields['name'] = name;
    if (city != null) request.fields['city'] = city;
    if (village != null) request.fields['village'] = village;
    if (locationDescription != null) {
      request.fields['location_description'] = locationDescription;
    }
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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await OfflineService.cacheStore(data);
      try {
        return Store.fromJson(data);
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

  // ==================== STAFF MANAGEMENT ====================

  static Future<List<dynamic>> fetchMyStoreStaff() async {
    final response = await ApiService.authGet('/my-store/staff');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed to load staff');
  }

  static Future<Map<String, dynamic>> inviteStaffMember({
    required String email,
    bool canManageInventory = false,
  }) async {
    final response = await ApiService.authPost('/my-store/staff', {
      'email': email,
      'can_manage_inventory': canManageInventory,
    });
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Failed to invite staff');
  }

  static Future<void> removeStaffMember(int staffId) async {
    final response = await ApiService.authDelete('/my-store/staff/$staffId');
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed');
    }
  }

  static Future<Map<String, dynamic>> updateStaffPermissions(
    int staffId, {
    required bool canManageInventory,
  }) async {
    final response = await ApiService.authPut(
      '/my-store/staff/$staffId/permissions',
      {'can_manage_inventory': canManageInventory},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error']?.toString() ?? 'Failed');
  }

  // ==================== INVITATIONS (Worker) ====================
  static Future<List<dynamic>> fetchMyInvitations() async {
    final response = await ApiService.authGet('/stores/my-invitations');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  static Future<void> acceptInvitation(int invitationId) async {
    final response = await ApiService.authPost(
      '/stores/my-invitations/$invitationId/accept',
      {},
    );
    if (response.statusCode != 200) {
      throw Exception(
        jsonDecode(response.body)['error'] ?? 'Failed to accept invitation',
      );
    }
    // After accepting, refresh store context from server
    final userResponse = await ApiService.authGet('/me');
    if (userResponse.statusCode == 200) {
      final userData = jsonDecode(userResponse.body) as Map<String, dynamic>;
      final storeCtx = userData['store'] as Map<String, dynamic>?;
      if (storeCtx != null) await ApiService.setStoreContext(storeCtx);
    }
  }

  static Future<void> rejectInvitation(int invitationId) async {
    final response = await ApiService.authPost(
      '/stores/my-invitations/$invitationId/reject',
      {},
    );
    if (response.statusCode != 200) {
      throw Exception(
        jsonDecode(response.body)['error'] ?? 'Failed to reject invitation',
      );
    }
  }
}
