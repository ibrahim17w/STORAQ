import 'package:flutter_map/flutter_map.dart';
import '../widgets/cached_tile_provider.dart';

/// Free map tile sources (no API keys). Ordered by preference for Syria/restricted networks.
class MapTileSource {
  final String urlTemplate;
  final List<String> subdomains;

  const MapTileSource(this.urlTemplate, this.subdomains);
}

class MapTilesConfig {
  MapTilesConfig._();

  /// Identifies the app to tile servers (required by OSM usage policy).
  static const String userAgentPackageName = 'com.example.storaq';

  static const String userAgent =
      'STORAQ/1.0 (+https://storaq.app; contact@storaq.app)';

  /// All free sources tried in order when the primary CDN is slow or blocked.
  static const List<MapTileSource> sources = [
    MapTileSource(
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
      ['a', 'b', 'c', 'd'],
    ),
    MapTileSource(
      'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
      ['a', 'b', 'c'],
    ),
    MapTileSource(
      'https://tiles.openfreemap.org/osm/{z}/{x}/{y}.png',
      [],
    ),
    MapTileSource(
      'https://maps.wikimedia.org/osm-intl/{z}/{x}/{y}.png',
      [],
    ),
  ];

  static MapTileSource get primary => sources.first;

  /// Shared [TileLayer] for every map screen — same look, automatic fallbacks.
  static TileLayer standardTileLayer() => TileLayer(
        urlTemplate: primary.urlTemplate,
        subdomains: primary.subdomains,
        maxZoom: 20,
        userAgentPackageName: userAgentPackageName,
        tileProvider: CachedNetworkTileProvider(),
      );
}
