import 'dart:convert';
import 'api_service.dart';

class ReportService {
  static Future<void> submit({
    required String targetType,
    required int targetId,
    int? storeId,
    required String reason,
  }) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/reports',
      headers: await ApiService.authHeaders,
      body: jsonEncode({
        'target_type': targetType,
        'target_id': targetId,
        if (storeId != null) 'store_id': storeId,
        'reason': reason,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) return;
    final message = data is Map ? data['error']?.toString() : null;
    throw Exception(message ?? 'Failed to submit report');
  }
}
