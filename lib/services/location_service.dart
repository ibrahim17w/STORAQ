import 'dart:convert';
import 'api_service.dart';

class LocationService {
  static Future<List<dynamic>> geocodeSearch(String query, String lang) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/geocode/search?q=${Uri.encodeComponent(query)}&lang=$lang',
      headers: ApiService.publicHeaders,
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
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/geocode/reverse?lat=$lat&lng=$lng&lang=$lang',
      headers: ApiService.publicHeaders,
      timeout: const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Reverse geocode failed');
  }
}
