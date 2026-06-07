import 'dart:convert';
import 'api_service.dart';

class ChatService {
  static Future<List<Map<String, dynamic>>> fetchConversations() async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}/api/chat/conversations',
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    }
    throw Exception('Failed to load conversations');
  }

  static Future<Map<String, dynamic>> startConversation(int storeId) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/chat/conversations',
      headers: await ApiService.authHeaders,
      body: jsonEncode({'store_id': storeId}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }
    throw Exception(data['error']?.toString() ?? 'Failed to start chat');
  }

  static Future<List<Map<String, dynamic>>> fetchMessages(
    int conversationId, {
    String? since,
  }) async {
    var url = '${ApiService.baseUrl}/api/chat/conversations/$conversationId/messages';
    if (since != null && since.isNotEmpty) {
      url += '?since=${Uri.encodeComponent(since)}';
    }
    final response = await ApiService.getWithTimeout(
      url,
      headers: await ApiService.authHeaders,
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    }
    throw Exception('Failed to load messages');
  }

  static Future<Map<String, dynamic>> sendMessage(
    int conversationId,
    String body,
  ) async {
    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}/api/chat/conversations/$conversationId/messages',
      headers: await ApiService.authHeaders,
      body: jsonEncode({'body': body}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 201) return data;
    throw Exception(data['error']?.toString() ?? 'Failed to send message');
  }
}
