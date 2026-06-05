import 'dart:async';

/// Broadcasts when the local product catalog changes (cache, pending, stock).
/// Checkout and other screens subscribe for instant updates.
class StoreCatalogService {
  StoreCatalogService._();
  static final StoreCatalogService instance = StoreCatalogService._();

  final _controller = StreamController<void>.broadcast();

  Stream<void> get onChanged => _controller.stream;

  void notifyChanged() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }
}
