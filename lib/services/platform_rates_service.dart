import 'dart:convert';
import 'api_service.dart';

class PlatformRatesService {
  static Map<String, dynamic>? _cache;
  static DateTime? _cacheAt;
  static const _cacheDuration = Duration(minutes: 15);

  static Future<Map<String, dynamic>> getPaymentRates({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cache != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < _cacheDuration) {
      return _cache!;
    }

    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/platform/payment-rates',
      headers: ApiService.publicHeaders,
      timeout: const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _cache = data;
      _cacheAt = DateTime.now();
      return data;
    }
    if (_cache != null) return _cache!;
    throw Exception('Failed to load payment rates');
  }
}
