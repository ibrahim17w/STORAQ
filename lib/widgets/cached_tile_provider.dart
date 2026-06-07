import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import '../config/map_tiles_config.dart';
import '../services/tile_cache_service.dart';

/// Fetches map tiles with disk cache + automatic free-source fallbacks.
class CachedNetworkTileProvider extends TileProvider {
  CachedNetworkTileProvider({Map<String, String>? headers})
      : super(
          headers: {
            'User-Agent': MapTilesConfig.userAgent,
            ...?headers,
          },
        );

  static final http.Client _client = http.Client();

  /// Last source that worked — tried first on the next tile for faster loads.
  static int _preferredSourceIndex = 0;

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) =>
      _FallbackTileImageProvider(
        coordinates: coordinates,
        options: options,
        headers: headers,
        httpClient: _client,
        cancelLoading: cancelLoading,
      );

  static String buildTileUrl(
    MapTileSource source,
    TileCoordinates coordinates,
    TileLayer options,
  ) {
    final zoom = (options.zoomOffset +
            (options.zoomReverse
                ? options.maxZoom - coordinates.z.toDouble()
                : coordinates.z.toDouble()))
        .round();

    final y = options.tms
        ? ((1 << zoom) - 1) - coordinates.y
        : coordinates.y;

    final subdomains = source.subdomains;
    final subdomain = subdomains.isEmpty
        ? ''
        : subdomains[(coordinates.x + coordinates.y) % subdomains.length];

    final retinaSuffix =
        options.resolvedRetinaMode == RetinaMode.server ? '@2x' : '';

    return source.urlTemplate
        .replaceAll('{z}', zoom.toString())
        .replaceAll('{x}', coordinates.x.toString())
        .replaceAll('{y}', y.toString())
        .replaceAll('{s}', subdomain)
        .replaceAll('{r}', retinaSuffix);
  }

  static List<MapTileSource> _orderedSources() {
    if (_preferredSourceIndex <= 0 ||
        _preferredSourceIndex >= MapTilesConfig.sources.length) {
      return MapTilesConfig.sources;
    }
    final preferred = MapTilesConfig.sources[_preferredSourceIndex];
    final rest = [
      for (var i = 0; i < MapTilesConfig.sources.length; i++)
        if (i != _preferredSourceIndex) MapTilesConfig.sources[i],
    ];
    return [preferred, ...rest];
  }

  static void _markPreferred(int index) {
    if (index >= 0 && index < MapTilesConfig.sources.length) {
      _preferredSourceIndex = index;
    }
  }
}

class _FallbackTileImageProvider
    extends ImageProvider<_FallbackTileImageProvider> {
  const _FallbackTileImageProvider({
    required this.coordinates,
    required this.options,
    required this.headers,
    required this.httpClient,
    required this.cancelLoading,
  });

  final TileCoordinates coordinates;
  final TileLayer options;
  final Map<String, String> headers;
  final http.Client httpClient;
  final Future<void> cancelLoading;

  @override
  Future<_FallbackTileImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FallbackTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      debugLabel: 'fallback_tile_${coordinates.z}_${coordinates.x}_${coordinates.y}',
    );
  }

  Future<Codec> _load(ImageDecoderCallback decode) async {
    if (await _isCancelled()) {
      return _decodeTransparent(decode);
    }

    final cached = await TileCacheService.getTileByCoord(
      coordinates.z,
      coordinates.x,
      coordinates.y,
    );
    if (cached != null) {
      try {
        return await _decodeBytes(cached, decode);
      } catch (_) {}
    }

    final sources = CachedNetworkTileProvider._orderedSources();
    Object? lastError;

    for (var i = 0; i < sources.length; i++) {
      if (await _isCancelled()) {
        return _decodeTransparent(decode);
      }

      final source = sources[i];
      final url = CachedNetworkTileProvider.buildTileUrl(
        source,
        coordinates,
        options,
      );

      final urlCached = await TileCacheService.getTile(url);
      if (urlCached != null) {
        try {
          await _persistTile(url, urlCached);
          CachedNetworkTileProvider._markPreferred(
            MapTilesConfig.sources.indexOf(source),
          );
          return await _decodeBytes(urlCached, decode);
        } catch (_) {}
      }

      try {
        final response = await httpClient
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final bytes = response.bodyBytes;
          await _persistTile(url, bytes);
          CachedNetworkTileProvider._markPreferred(
            MapTilesConfig.sources.indexOf(source),
          );
          return await _decodeBytes(bytes, decode);
        }
      } catch (e) {
        lastError = e;
      }
    }

    if (kDebugMode && lastError != null) {
      // ignore: avoid_print
      print('[STORAQ maps] All tile sources failed for '
          '${coordinates.z}/${coordinates.x}/${coordinates.y}: $lastError');
    }

    return _decodeTransparent(decode);
  }

  Future<void> _persistTile(String url, Uint8List bytes) async {
    await TileCacheService.saveTile(url, bytes);
    await TileCacheService.saveTileByCoord(
      coordinates.z,
      coordinates.x,
      coordinates.y,
      bytes,
    );
  }

  Future<bool> _isCancelled() {
    return cancelLoading
        .then((_) => true)
        .timeout(const Duration(microseconds: 1), onTimeout: () => false);
  }

  Future<Codec> _decodeBytes(Uint8List bytes, ImageDecoderCallback decode) =>
      ImmutableBuffer.fromUint8List(bytes).then(decode);

  Future<Codec> _decodeTransparent(ImageDecoderCallback decode) =>
      _decodeBytes(TileProvider.transparentImage, decode);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FallbackTileImageProvider &&
          coordinates == other.coordinates &&
          options.urlTemplate == other.options.urlTemplate;

  @override
  int get hashCode => Object.hash(coordinates, options.urlTemplate);
}
