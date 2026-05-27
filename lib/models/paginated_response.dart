// lib/models/paginated_response.dart
class PaginatedResponse<T> {
  final List<T> data;
  final PaginationMeta pagination;

  PaginatedResponse({required this.data, required this.pagination});

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromJson,
  ) {
    return PaginatedResponse(
      data: (json['data'] as List<dynamic>?)?.map(fromJson).toList() ?? [],
      pagination: PaginationMeta.fromJson(
        json['pagination'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson(Object? Function(T) toJson) => {
    'data': data.map(toJson).toList(),
    'pagination': pagination.toJson(),
  };
}

class PaginationMeta {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  PaginationMeta({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) => PaginationMeta(
    page: (json['page'] as num?)?.toInt() ?? 1,
    limit: (json['limit'] as num?)?.toInt() ?? 20,
    total: (json['total'] as num?)?.toInt() ?? 0,
    totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'page': page,
    'limit': limit,
    'total': total,
    'total_pages': totalPages,
  };

  bool get hasNextPage => page < totalPages;
  int get nextPage => hasNextPage ? page + 1 : page;
}
