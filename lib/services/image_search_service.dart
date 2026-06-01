import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'api_service.dart';

class ImageSearchService {
  static Future<Map<String, dynamic>> searchByImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiService.baseUrl}/api/search/image-similarity'),
      );
      request.headers.addAll(await ApiService.multipartAuthHeaders);

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
