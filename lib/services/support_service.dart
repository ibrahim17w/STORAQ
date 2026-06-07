import 'dart:convert';
import 'api_service.dart';

class SupportService {
  static Future<List<Map<String, dynamic>>> fetchTickets() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/support/tickets',
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    }
    throw Exception('Failed to load support tickets');
  }

  static Future<Map<String, dynamic>> createTicket({
    required String subject,
    required String body,
    String category = 'general',
  }) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/support/tickets',
      headers: await ApiService.authHeaders,
      body: jsonEncode({
        'subject': subject,
        'body': body,
        'category': category,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Failed to create ticket');
  }

  static Future<Map<String, dynamic>> fetchTicketThread(int ticketId) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/support/tickets/$ticketId/messages',
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(data['error']?.toString() ?? 'Failed to load ticket');
  }

  static Future<Map<String, dynamic>> sendReply(
    int ticketId,
    String body,
  ) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/support/tickets/$ticketId/messages',
      headers: await ApiService.authHeaders,
      body: jsonEncode({'body': body}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Failed to send reply');
  }
}
