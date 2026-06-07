import '../config/app_links_config.dart';

/// Unified store QR / deep-link payloads for receipts and store owner QR codes.
class StoreQrHelper {
  static const scheme = AppLinksConfig.deepLinkScheme;

  /// In-app deep link (opens STORAQ directly when installed).
  static String storeDeepLink(int storeId) => '$scheme://store/$storeId';

  /// HTTPS link for printed QR codes — works in any camera app.
  /// Opens a smart landing page: app if installed, download page otherwise.
  static String storeWebUrl(int storeId) {
    final base = AppLinksConfig.publicWebBase.replaceAll(RegExp(r'/+$'), '');
    return '$base/s/$storeId';
  }

  /// Default payload for QR barcodes (use HTTPS so phone cameras work).
  static String storeQrPayload(int storeId) => storeWebUrl(storeId);

  static String downloadUrl({int? storeId}) {
    final base = AppLinksConfig.downloadUrl.replaceAll(RegExp(r'/+$'), '');
    if (storeId == null) return base;
    return '$base?store=$storeId';
  }

  static int? parseStoreId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final deepLink = RegExp(r'storaq://store/(\d+)', caseSensitive: false)
        .firstMatch(trimmed);
    if (deepLink != null) {
      return int.tryParse(deepLink.group(1)!);
    }

    final webShort = RegExp(r'/s/(\d+)(?:\?|#|$|/)', caseSensitive: false)
        .firstMatch(trimmed);
    if (webShort != null) {
      return int.tryParse(webShort.group(1)!);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      if (uri.scheme.toLowerCase() == scheme &&
          uri.host.toLowerCase() == 'store') {
        if (uri.pathSegments.isNotEmpty) {
          return int.tryParse(uri.pathSegments.first);
        }
      }

      final path = uri.path;
      final shortPath = RegExp(r'^/s/(\d+)$', caseSensitive: false).firstMatch(path);
      if (shortPath != null) {
        return int.tryParse(shortPath.group(1)!);
      }

      if (uri.pathSegments.length >= 2 &&
          uri.pathSegments[0].toLowerCase() == 'store') {
        return int.tryParse(uri.pathSegments[1]);
      }
      if (uri.pathSegments.length == 1 &&
          uri.pathSegments[0].toLowerCase() == 'store' &&
          uri.queryParameters['id'] != null) {
        return int.tryParse(uri.queryParameters['id']!);
      }
      if (uri.queryParameters['store'] != null) {
        return int.tryParse(uri.queryParameters['store']!);
      }
    }

    return int.tryParse(trimmed);
  }
}
