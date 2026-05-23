//cached_tile_provider.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import '../services/tile_cache_service.dart';

/// Simple HTTP client that caches responses to file system
class _CachingHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();

    // Try cache first
    final cached = await TileCacheService.getTile(url);
    if (cached != null) {
      // Return cached response
      return http.StreamedResponse(
        Stream.fromIterable([cached]),
        200,
        request: request,
        headers: {
          'content-type': 'image/png',
          'content-length': cached.length.toString(),
        },
      );
    }

    // Fetch from network
    final response = await _inner.send(request);
    if (response.statusCode == 200) {
      final bytes = await response.stream.toBytes();
      // Save to cache
      await TileCacheService.saveTile(url, bytes);
      // Return new response with the bytes
      return http.StreamedResponse(
        Stream.fromIterable([bytes]),
        response.statusCode,
        request: request,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
      );
    }

    return response;
  }

  @override
  void close() {
    _inner.close();
  }
}

class CachedNetworkTileProvider extends NetworkTileProvider {
  static final _client = _CachingHttpClient();

  CachedNetworkTileProvider({super.headers}) : super(httpClient: _client);

  // Multiple free tile sources ordered by likelihood of working in restricted regions
  static List<String> get syriaFallbackUrls => [
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
    'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
    'https://maps.wikimedia.org/osm-intl/{z}/{x}/{y}.png',
    'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
  ];
}
