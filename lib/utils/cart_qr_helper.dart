import 'dart:convert';

import '../config/app_links_config.dart';

class CartQrLine {
  final int productId;
  final int quantity;

  const CartQrLine({required this.productId, required this.quantity});
}

class CartQrPayload {
  final int version;
  final int storeId;
  final List<CartQrLine> items;

  const CartQrPayload({
    required this.version,
    required this.storeId,
    required this.items,
  });
}

/// Encodes/decodes customer shopping-cart payloads for in-store POS checkout.
class CartQrHelper {
  static const int currentVersion = 1;

  static String encode({
    required int storeId,
    required List<CartQrLine> items,
  }) {
    final cleaned = items
        .where((e) => e.productId > 0 && e.quantity > 0)
        .map((e) => [e.productId, e.quantity])
        .toList();
    final payload = {
      'v': currentVersion,
      's': storeId,
      'i': cleaned,
    };
    final b64 = _encodePayload(payload);
    return '${AppLinksConfig.deepLinkScheme}://cart/$b64';
  }

  static String webUrl({
    required int storeId,
    required List<CartQrLine> items,
  }) {
    final cleaned = items
        .where((e) => e.productId > 0 && e.quantity > 0)
        .map((e) => [e.productId, e.quantity])
        .toList();
    final payload = {
      'v': currentVersion,
      's': storeId,
      'i': cleaned,
    };
    final b64 = _encodePayload(payload);
    final base = AppLinksConfig.publicWebBase.replaceAll(RegExp(r'/+$'), '');
    return '$base/cart/$b64';
  }

  static CartQrPayload? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    Map<String, dynamic>? json;

    final direct = _tryParseJson(trimmed);
    if (direct != null) {
      json = direct;
    } else {
      final embedded = _extractEmbeddedPayload(trimmed);
      if (embedded != null) {
        json = _tryParseJson(embedded);
      }
    }

    if (json == null) return null;
    return _fromJson(json);
  }

  static String _encodePayload(Map<String, dynamic> payload) {
    return base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
  }

  static Map<String, dynamic>? _tryParseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static String? _extractEmbeddedPayload(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null) {
      if (uri.scheme.toLowerCase() == AppLinksConfig.deepLinkScheme &&
          uri.host.toLowerCase() == 'cart') {
        if (uri.pathSegments.isNotEmpty) {
          return _decodeBase64Url(uri.pathSegments.join('/'));
        }
        if (uri.queryParameters['d'] != null) {
          return _decodeBase64Url(uri.queryParameters['d']!);
        }
      }

      final path = uri.path;
      final cartPath = RegExp(r'^/cart/([^/?#]+)', caseSensitive: false)
          .firstMatch(path);
      if (cartPath != null) {
        return _decodeBase64Url(cartPath.group(1)!);
      }
    }

    final schemePrefix = RegExp(
      r'^storaq://cart/([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (schemePrefix != null) {
      return _decodeBase64Url(schemePrefix.group(1)!);
    }

    final marker = RegExp(
      r'STORAQ_CART:([A-Za-z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (marker != null) {
      return _decodeBase64Url(marker.group(1)!);
    }

    if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(raw)) {
      return _decodeBase64Url(raw);
    }

    return null;
  }

  static String? _decodeBase64Url(String value) {
    try {
      final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
      final pad = normalized.length % 4;
      final padded = pad == 0
          ? normalized
          : normalized + ('=' * (4 - pad));
      return utf8.decode(base64Url.decode(padded));
    } catch (_) {
      return null;
    }
  }

  static CartQrPayload? _fromJson(Map<String, dynamic> json) {
    final version = json['v'] is int
        ? json['v'] as int
        : int.tryParse(json['v']?.toString() ?? '') ?? 0;
    if (version != currentVersion) return null;

    final storeId = json['s'] is int
        ? json['s'] as int
        : int.tryParse(json['s']?.toString() ?? '') ?? 0;
    if (storeId <= 0) return null;

    final rawItems = json['i'];
    if (rawItems is! List || rawItems.isEmpty) return null;

    final lines = <CartQrLine>[];
    for (final entry in rawItems) {
      if (entry is! List || entry.length < 2) continue;
      final productId = entry[0] is int
          ? entry[0] as int
          : int.tryParse(entry[0]?.toString() ?? '') ?? 0;
      final quantity = entry[1] is int
          ? entry[1] as int
          : int.tryParse(entry[1]?.toString() ?? '') ?? 0;
      if (productId > 0 && quantity > 0) {
        lines.add(CartQrLine(productId: productId, quantity: quantity));
      }
    }

    if (lines.isEmpty) return null;
    return CartQrPayload(version: version, storeId: storeId, items: lines);
  }

  static int? parseProductId(dynamic id) {
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '');
  }
}
