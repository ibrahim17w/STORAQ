import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import '../utils/store_qr_helper.dart';

/// Handles incoming store deep links (cold start + while running).
class DeepLinkService {
  DeepLinkService._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _subscription;
  static int? _pendingStoreId;
  static final ValueNotifier<int?> pendingStoreIdNotifier = ValueNotifier(null);

  static int? get pendingStoreId => _pendingStoreId;

  static int? consumePendingStoreId() {
    final id = _pendingStoreId;
    _pendingStoreId = null;
    pendingStoreIdNotifier.value = null;
    return id;
  }

  static Future<void> init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      _handleUri(initial);
    } catch (_) {}

    await _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (_) {},
    );
  }

  static void _handleUri(Uri? uri) {
    if (uri == null) return;
    final storeId = StoreQrHelper.parseStoreId(uri.toString());
    if (storeId != null && storeId > 0) {
      _pendingStoreId = storeId;
      pendingStoreIdNotifier.value = storeId;
    }
  }

  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
