import 'dart:convert';

import 'dart:io';

import 'package:http/http.dart' as http;

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



  static Future<Map<String, dynamic>> requestImageUpload(int ticketId) async {

    final response = await ApiService.postWithTimeout(

      '${ApiService.baseUrl}/api/support/tickets/$ticketId/request-image',

      headers: await ApiService.authHeaders,

      body: jsonEncode({}),

    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 201) return data;

    throw Exception(data['error']?.toString() ?? 'Failed to request image upload');

  }



  static Future<Map<String, dynamic>> uploadImage(

    int ticketId,

    File imageFile, {

    String? caption,

  }) async {

    final request = http.MultipartRequest(

      'POST',

      Uri.parse(

        '${ApiService.baseUrl}/api/support/tickets/$ticketId/messages/image',

      ),

    );

    request.headers.addAll(await ApiService.multipartAuthHeaders);

    request.files.add(

      await http.MultipartFile.fromPath('image', imageFile.path),

    );

    if (caption != null && caption.trim().isNotEmpty) {

      request.fields['caption'] = caption.trim();

    }



    final streamed = await request.send().timeout(const Duration(seconds: 60));

    final response = await http.Response.fromStream(streamed);

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 201) return data;

    throw Exception(data['error']?.toString() ?? 'Failed to upload image');

  }

  static Future<void> deleteTicket(int ticketId) async {
    final response = await ApiService.authDelete('/support/tickets/$ticketId');
    if (response.statusCode == 200) return;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(data['error']?.toString() ?? 'Failed to delete ticket');
  }

}

