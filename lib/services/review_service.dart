import 'dart:convert';
import 'api_service.dart';

enum ReviewTargetType { store, product }

class Review {
  final int id;
  final int targetId;
  final int userId;
  final int rating;
  final String? comment;
  final String? userName;
  final String createdAt;

  Review({
    required this.id,
    required this.targetId,
    required this.userId,
    required this.rating,
    this.comment,
    this.userName,
    required this.createdAt,
  });

  factory Review.fromJson(ReviewTargetType type, Map<String, dynamic> json) {
    final targetKey = type == ReviewTargetType.store ? 'store_id' : 'product_id';
    return Review(
      id: json['id'] as int,
      targetId: json[targetKey] as int,
      userId: json['user_id'] as int,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      userName: json['user_name'] as String?,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

class ReviewsPayload {
  final ReviewTargetType type;
  final int targetId;
  final String? targetName;
  final double rating;
  final int total;
  final List<Review> reviews;
  final Review? myReview;
  final bool canRequestRemoval;

  ReviewsPayload({
    required this.type,
    required this.targetId,
    this.targetName,
    required this.rating,
    required this.total,
    required this.reviews,
    this.myReview,
    this.canRequestRemoval = false,
  });

  factory ReviewsPayload.fromJson(ReviewTargetType type, Map<String, dynamic> json) {
    final list = (json['reviews'] as List<dynamic>? ?? [])
        .map((e) => Review.fromJson(type, e as Map<String, dynamic>))
        .toList();
    Review? mine;
    if (json['my_review'] != null) {
      mine = Review.fromJson(type, json['my_review'] as Map<String, dynamic>);
    }
    final idKey = type == ReviewTargetType.store ? 'store_id' : 'product_id';
    return ReviewsPayload(
      type: type,
      targetId: json[idKey] as int,
      targetName: json['product_name'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      total: json['total'] as int? ?? list.length,
      reviews: list,
      myReview: mine,
      canRequestRemoval: json['can_request_removal'] == true,
    );
  }
}

class ReviewService {
  static String _basePath(ReviewTargetType type, int id) {
    return type == ReviewTargetType.store
        ? '/api/stores/$id/reviews'
        : '/api/products/$id/reviews';
  }

  static Future<Map<String, String>> _authHeaders() async {
    final headers = Map<String, String>.from(ApiService.publicHeaders);
    final token = await ApiService.getToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static Future<ReviewsPayload> fetchReviews({
    required ReviewTargetType type,
    required int targetId,
  }) async {
    final response = await ApiService.getWithTimeout(
      '${ApiService.baseUrl}${_basePath(type, targetId)}',
      headers: await _authHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load reviews');
    }
    return ReviewsPayload.fromJson(
      type,
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> submitReview({
    required ReviewTargetType type,
    required int targetId,
    required int rating,
    String? comment,
  }) async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not logged in');

    final response = await ApiService.postWithTimeout(
      '${ApiService.baseUrl}${_basePath(type, targetId)}',
      headers: {
        ...ApiService.publicHeaders,
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      }),
    );
    if (response.statusCode != 201) {
      final body = jsonDecode(response.body);
      throw Exception(body['error']?.toString() ?? 'Failed to submit review');
    }
  }
}

// Backward-compatible aliases for store reviews
typedef StoreReview = Review;
typedef StoreReviewsPayload = ReviewsPayload;
