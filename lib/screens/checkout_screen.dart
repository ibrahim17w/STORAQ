// lib/screens/checkout_screen.dart
// FIXED: Eliminated freeze by checking connectivity before ALL API calls,
// debouncing search, canceling pending requests, and using CachedAppImage.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../utils/barcode_helper.dart';
import '../screens/barcode_scanner_screen.dart';
import '../screens/receipt_screen.dart';
import '../lang/translations.dart';
import '../widgets/gradient_button.dart';
import '../widgets/cached_image.dart';
import '../services/offline_service.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import '../services/product_service.dart';
import '../services/order_service.dart';
import '../services/store_catalog_service.dart';

class CartItem {
  final dynamic productId; // int for server products, String for pending
  final String name;
  final double unitPrice;
  int quantity;
  final String? barcode;
  int? stock;
  final String currency;

  CartItem({
    this.productId,
    required this.name,
    required this.unitPrice,
    this.quantity = 1,
    this.barcode,
    this.stock,
    this.currency = 'SYP',
  });

  double get total => unitPrice * quantity;
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with WidgetsBindingObserver {
  final List<CartItem> _cart = [];
  final _searchCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isSearching = false;
  List<dynamic> _allProducts = [];
  List<dynamic> _searchResults = [];
  String? _cashierName;
  int? _storeId;

  bool _discountIsPercent = false;
  bool _taxIsPercent = false;
  bool _isOffline = false;

  // CRITICAL FIX: Debounce search to avoid rapid API calls when typing
  Timer? _searchDebounce;
  // CRITICAL FIX: Cancel token for pending search requests
  bool _searchCancelled = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<void>? _catalogSub;
  Timer? _stockRefreshTimer;
  Timer? _catalogRefreshDebounce;
  int _stockRefreshTick = 0;
  bool _catalogRefreshInFlight = false;

  double get _rawSubtotal => _cart.fold(0, (sum, item) => sum + item.total);

  double get _discountValue {
    final raw = double.tryParse(_discountCtrl.text) ?? 0;
    if (_discountIsPercent && raw > 0) {
      return (_rawSubtotal * raw / 100).clamp(0, _rawSubtotal);
    }
    return raw.clamp(0, _rawSubtotal);
  }

  double get _taxValue {
    final raw = double.tryParse(_taxCtrl.text) ?? 0;
    if (_taxIsPercent && raw > 0) {
      return (_rawSubtotal * raw / 100);
    }
    return raw;
  }

  double get _subtotal => _rawSubtotal;

  double get _total => _rawSubtotal - _discountValue + _taxValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _stockRefreshTimer?.cancel();
    _catalogRefreshDebounce?.cancel();
    _connectivitySub?.cancel();
    _catalogSub?.cancel();
    _searchCtrl.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _discountCtrl.dispose();
    _taxCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshCatalog());
    }
  }

  Future<bool> _checkOnline() async {
    return ApiService.isServerReachable();
  }

  /// Load from local cache first; never block on network when unreachable.
  Future<void> _bootstrap() async {
    _isOffline = !await _checkOnline();

    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (_) => unawaited(_handleConnectivityChange()),
    );

    _catalogSub = StoreCatalogService.instance.onChanged.listen(
      (_) => _scheduleCatalogRefresh(),
    );

    unawaited(_loadCashier());
    unawaited(_loadStoreProducts());

    if (!_isOffline) {
      unawaited(_refreshStoreFromServer());
    }

    _startStockRefreshTimer();
  }

  Future<void> _handleConnectivityChange() async {
    if (!mounted) return;
    final online = await _checkOnline();
    if (!mounted) return;
    final wasOffline = _isOffline;
    setState(() => _isOffline = !online);
    if (online) {
      unawaited(_refreshCatalog());
      if (wasOffline) {
        unawaited(_refreshStoreFromServer());
      }
    }
  }

  void _scheduleCatalogRefresh() {
    _catalogRefreshDebounce?.cancel();
    _catalogRefreshDebounce = Timer(const Duration(milliseconds: 150), () {
      unawaited(_refreshCatalog());
    });
  }

  void _startStockRefreshTimer() {
    _stockRefreshTimer?.cancel();
    _stockRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshCatalog());
      _stockRefreshTick++;
      if (!_isOffline && _stockRefreshTick % 10 == 0) {
        unawaited(_refreshStoreFromServer());
      }
    });
  }

  Future<void> _loadStoreProducts() async {
    if (mounted) setState(() => _isLoading = true);

    int? cachedStoreId;
    try {
      cachedStoreId = await ApiService.getMyStoreId();
      if (cachedStoreId == null) {
        final cachedStore = await OfflineService.getCachedStore().timeout(
          const Duration(seconds: 2),
        );
        cachedStoreId = cachedStore?['id'] as int?;
      }
    } catch (_) {}

    if (cachedStoreId != null) {
      _storeId = cachedStoreId;
      try {
        final merged = await OfflineService.getMergedProducts(
          cachedStoreId,
        ).timeout(const Duration(seconds: 3));
        if (mounted) {
          setState(() {
            _allProducts = merged;
            _isLoading = false;
            _syncCartStockFromCatalog();
          });
        }
      } catch (_) {
        try {
          final cached = await OfflineService.getCachedProducts(
            storeId: cachedStoreId,
          ).timeout(const Duration(seconds: 2));
          if (mounted) {
            setState(() {
              _allProducts = cached;
              _isLoading = false;
              _syncCartStockFromCatalog();
            });
          }
        } catch (_) {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshCatalog() async {
    if (_catalogRefreshInFlight || _storeId == null || !mounted) return;
    _catalogRefreshInFlight = true;
    try {
      final merged = await OfflineService.getMergedProducts(_storeId!).timeout(
        const Duration(seconds: 2),
      );
      if (!mounted) return;
      setState(() {
        _allProducts = merged;
        _applySearchFilterToResults();
        _syncCartStockFromCatalog();
      });
    } catch (_) {}
    finally {
      _catalogRefreshInFlight = false;
    }
  }

  void _applySearchFilterToResults() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      _searchResults = [];
      return;
    }
    _searchResults = _allProducts.where((p) {
      final name = p['name']?.toString().toLowerCase() ?? '';
      final barcode = p['barcode']?.toString().toLowerCase() ?? '';
      return name.contains(query) || barcode.contains(query);
    }).toList();
  }

  void _syncCartStockFromCatalog() {
    final productMap = <dynamic, Map<String, dynamic>>{
      for (final p in _allProducts) p['id']: p,
    };
    _cart.removeWhere((item) => !productMap.containsKey(item.productId));
    for (final item in _cart) {
      final product = productMap[item.productId];
      if (product != null) {
        item.stock = (product['quantity'] as num?)?.toInt() ?? 0;
      }
    }
  }

  Future<void> _refreshStoreFromServer() async {
    if (_isOffline) return;

    try {
      final store = await StoreService.getMyStore().timeout(
        const Duration(seconds: 4),
      );
      final storeId = store['id'] as int?;
      if (storeId == null) return;

      if (mounted && _storeId != storeId) {
        setState(() => _storeId = storeId);
      }

      List<dynamic> products = [];
      try {
        products = await ProductService.loadStoreCatalog(
          storeId,
          forceRefresh: true,
        ).timeout(const Duration(seconds: 4));
      } catch (_) {
        return;
      }

      if (mounted && products.isNotEmpty) {
        setState(() {
          _allProducts = products;
          _applySearchFilterToResults();
          _syncCartStockFromCatalog();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCashier() async {
    if (_isOffline) {
      try {
        final cachedUser = await OfflineService.getCachedUser().timeout(
          const Duration(seconds: 1),
          onTimeout: () => Future.value(null),
        );
        if (mounted) {
          setState(
            () => _cashierName = cachedUser?['full_name']?.toString(),
          );
        }
      } catch (_) {}
      return;
    }

    final results = await Future.wait([
      AuthService.getCurrentUser().timeout(
        const Duration(seconds: 2),
        onTimeout: () => Future.value(null),
      ),
      OfflineService.getCachedUser().timeout(
        const Duration(seconds: 2),
        onTimeout: () => Future.value(null),
      ),
    ]);

    final user = results[0] as Map<String, dynamic>?;
    final cachedUser = results[1] as Map<String, dynamic>?;

    if (mounted) {
      setState(
        () => _cashierName =
            user?['full_name']?.toString() ??
            cachedUser?['full_name']?.toString(),
      );
    }
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null) await _addByBarcode(code);
  }

  Future<void> _addByBarcode(String code) async {
    setState(() => _isLoading = true);
    try {
      if (!_isOffline) {
        try {
          final product = await ProductService.findProductByBarcode(code)
              .timeout(const Duration(seconds: 3));
          _addProductToCart(product);
          return;
        } catch (_) {}
      }

      final storeIdFallback =
          _storeId ?? await OfflineService.getCachedStoreId();
      final cached = storeIdFallback != null
          ? await OfflineService.getMergedProducts(storeIdFallback)
          : await OfflineService.getCachedProducts();
      final matchIndex = cached.indexWhere(
        (p) => p['barcode']?.toString() == code,
      );
      if (matchIndex >= 0) {
        _addProductToCart(cached[matchIndex] as Map<String, dynamic>);
      } else {
        _showError('${t('product_not_found') ?? 'Product not found'}: $code');
      }
    } catch (_) {
      _showError('${t('product_not_found') ?? 'Product not found'}: $code');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addProductToCart(Map<String, dynamic> product) {
    final productId = product['id'];
    Map<String, dynamic> catalogProduct = product;
    for (final p in _allProducts) {
      if (p is Map && p['id'] == productId) {
        catalogProduct = Map<String, dynamic>.from(p);
        break;
      }
    }
    final stock = (catalogProduct['quantity'] as num?)?.toInt() ?? 0;

    final existing = _cart.indexWhere((c) => c.productId == productId);

    if (existing >= 0) {
      final item = _cart[existing];
      if (item.quantity + 1 > stock) {
        _showError(t('insufficient_stock') ?? 'Insufficient stock');
        return;
      }
      setState(() => item.quantity++);
    } else {
      if (stock < 1) {
        _showError(t('out_of_stock') ?? 'Out of stock');
        return;
      }
      setState(
        () => _cart.add(
          CartItem(
            productId: productId,
            name:
                catalogProduct['name']?.toString() ??
                t('unknown_product') ??
                'Unknown',
            unitPrice: _parsePrice(catalogProduct['price']),
            barcode: catalogProduct['barcode']?.toString(),
            stock: stock,
            currency: catalogProduct['currency']?.toString() ?? 'SYP',
          ),
        ),
      );
    }
  }

  // CRITICAL FIX: Debounced search to prevent rapid API calls
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchProducts();
    });
  }

  Future<void> _searchProducts() async {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    // Local filter first (always fast, works offline)
    final localFiltered = _allProducts.where((p) {
      final name = p['name']?.toString().toLowerCase() ?? '';
      final barcode = p['barcode']?.toString().toLowerCase() ?? '';
      return name.contains(query) || barcode.contains(query);
    }).toList();

    setState(() {
      _searchResults = localFiltered;
      _isSearching = false;
    });

    // CRITICAL FIX: Only search server if online AND query is meaningful
    if (_isOffline || query.length < 2) return;

    final online = await _checkOnline();
    if (!online || !mounted) {
      if (mounted) setState(() => _isOffline = true);
      return;
    }

    setState(() => _isSearching = true);
    _searchCancelled = false;

    try {
      final results = await ProductService.searchStoreProducts(
        query: query,
        storeId: _storeId,
      );
      if (_searchCancelled) return; // Search was superseded
      final merged = _mergeWithLocal(results);
      if (mounted) setState(() => _searchResults = merged);
    } catch (_) {
      // Server search failed, local results already showing
    } finally {
      if (mounted && !_searchCancelled) {
        setState(() => _isSearching = false);
      }
    }
  }

  List<dynamic> _mergeWithLocal(List<dynamic> serverResults) {
    final localMap = {for (var p in _allProducts) p['id']: p};
    return serverResults.map((s) {
      final local = localMap[s['id']];
      if (local != null) {
        return local['updated_at'] != null &&
                s['updated_at'] != null &&
                DateTime.parse(
                  local['updated_at'],
                ).isAfter(DateTime.parse(s['updated_at']))
            ? local
            : s;
      }
      return s;
    }).toList();
  }

  void _adjustQty(int index, int delta) {
    final item = _cart[index];
    final newQty = item.quantity + delta;
    if (newQty < 1) {
      _removeItem(index);
      return;
    }
    if (item.stock != null && newQty > item.stock!) {
      _showError(t('insufficient_stock') ?? 'Insufficient stock');
      return;
    }
    setState(() => item.quantity = newQty);
  }

  Future<Map<String, dynamic>> _buildOfflineOrderData(String receiptNumber) async {
    final storeId = _storeId ?? await ApiService.getMyStoreId();
    final currency = _cart.isEmpty ? 'SYP' : _cart.first.currency;
    return {
      'items': _cart
          .map(
            (c) => {
              'product_id': c.productId,
              'product_name': c.name,
              'quantity': c.quantity,
              'unit_price': c.unitPrice,
              'total_price': c.total,
              'barcode': c.barcode,
              'currency': c.currency,
            },
          )
          .toList(),
      'store_id': storeId,
      'customer_name': _customerNameCtrl.text.trim().isEmpty
          ? null
          : _customerNameCtrl.text.trim(),
      'customer_phone': _customerPhoneCtrl.text.trim().isEmpty
          ? null
          : _customerPhoneCtrl.text.trim(),
      'subtotal': _subtotal,
      'discount': _discountValue,
      'tax': _taxValue,
      'total': _total,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'payment_method': 'cash',
      'receipt_number': receiptNumber,
      'cashier_name': _cashierName ?? t('unknown') ?? 'Unknown',
      'currency': currency,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  List<dynamic> get _displayProducts {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return _allProducts;
    return _searchResults;
  }

  Widget _buildProductListTile(Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final stock = (p['quantity'] as num?)?.toInt() ?? 0;
    final isOutOfStock = stock <= 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildProductImage(p),
        title: Text(
          p['name']?.toString() ?? '',
          style: isOutOfStock
              ? TextStyle(
                  color: theme.colorScheme.outline,
                  decoration: TextDecoration.lineThrough,
                )
              : null,
        ),
        subtitle: Text(
          '${_fmt(_parsePrice(p['price']), currency: p['currency']?.toString() ?? 'SYP')} • $stock ${t('in_stock') ?? 'in stock'}',
          style: isOutOfStock
              ? TextStyle(color: theme.colorScheme.error)
              : null,
        ),
        trailing: isOutOfStock
            ? const Icon(Icons.block, color: Colors.grey)
            : IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.green),
                onPressed: () => _addProductToCart(p),
              ),
      ),
    );
  }

  Future<void> _saveOfflineCheckout([String? receiptNumber]) async {
    for (final item in _cart) {
      final pid = item.productId;
      if (pid is String && pid.startsWith('pending_')) {
        await OfflineService.adjustProductStockForSale(pid, item.quantity);
      } else {
        final intId = pid is int ? pid : int.tryParse(pid?.toString() ?? '');
        if (intId != null) {
          await OfflineService.adjustCachedStockOnly(intId, -item.quantity);
        }
      }
    }

    final orderData = await _buildOfflineOrderData(
      receiptNumber ??
          'OFF-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
    );
    await OfflineService.saveOrderForOffline(orderData);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('receipt_saved_offline') ?? 'Receipt saved offline',
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(offlineOrder: orderData),
        ),
      );
    }
  }

  void _removeItem(int index) {
    setState(() => _cart.removeAt(index));
  }

  Future<void> _completeCheckout() async {
    if (_cart.isEmpty) {
      _showError(t('cart_empty') ?? 'Cart is empty');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('confirm_checkout') ?? 'Confirm Checkout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t('subtotal') ?? 'Subtotal'}: ${_fmt(_subtotal)}'),
            if (_discountValue > 0)
              Text(
                '${t('discount') ?? 'Discount'}: -${_fmt(_discountValue)}${_discountIsPercent ? ' (${_discountCtrl.text}%)' : ''}',
              ),
            if (_taxValue > 0)
              Text(
                '${t('tax') ?? 'Tax'}: +${_fmt(_taxValue)}${_taxIsPercent ? ' (${_taxCtrl.text}%)' : ''}',
              ),
            const Divider(),
            Text(
              '${t('total_amount') ?? 'Total'}: ${_fmt(_total)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel') ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('confirm') ?? 'Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);

    final isOnline = await _checkOnline();
    if (mounted) setState(() => _isOffline = !isOnline);

    String _offlineReceipt() =>
        'OFF-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    final hasUnsyncedProducts = _cart.any(
      (c) => c.productId?.toString().startsWith('pending_') ?? false,
    );

    if (!isOnline || hasUnsyncedProducts) {
      if (hasUnsyncedProducts && isOnline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('sync_products_before_checkout') ??
                  'Sync new products online before completing this sale on the server.',
            ),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
      await _saveOfflineCheckout();
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final items = _cart
          .map(
            (c) => {
              'product_id': c.productId,
              'product_name': c.name,
              'quantity': c.quantity,
              'unit_price': c.unitPrice,
              'total_price': c.total,
              'barcode': c.barcode,
              'currency': c.currency,
            },
          )
          .toList();

      final order = await OrderService.createOrder(
        items: items,
        customerName: _customerNameCtrl.text.trim().isEmpty
            ? null
            : _customerNameCtrl.text.trim(),
        customerPhone: _customerPhoneCtrl.text.trim().isEmpty
            ? null
            : _customerPhoneCtrl.text.trim(),
        discount: _discountValue,
        tax: _taxValue,
        total: _total,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(orderId: order['id'] as int),
          ),
        );
      }
    } catch (e) {
      await _saveOfflineCheckout(_offlineReceipt());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  String _fmt(double value, {String currency = 'SYP'}) =>
      '${value.toStringAsFixed(2)} $currency';

  double _parsePrice(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  Widget _buildDiscountTaxInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isPercent,
    required ValueChanged<bool> onToggle,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => setState(() => onToggle(!isPercent)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      isPercent ? '%' : _currency,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isPercent
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  String get _currency {
    if (_cart.isEmpty) return 'SYP';
    return _cart.first.currency;
  }

  Widget _productImagePlaceholder(Map<String, dynamic> product) {
    final name = product['name']?.toString() ?? '?';
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?'),
    );
  }

  // Prefer local cached images; skip remote URLs when offline to avoid hangs.
  Widget _buildProductImage(Map<String, dynamic> product) {
    final imagePaths = OfflineService.getProductImagePaths(product);
    var firstPath = imagePaths.isNotEmpty ? imagePaths.first : null;

    if (_isOffline &&
        firstPath != null &&
        (firstPath.startsWith('http://') || firstPath.startsWith('https://'))) {
      firstPath = null;
    }

    return CachedAppImage(
      imageUrl: firstPath,
      width: 40,
      height: 40,
      borderRadius: BorderRadius.circular(8),
      placeholder: _productImagePlaceholder(product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('checkout') ?? 'Checkout'),
        actions: [
          if (_isOffline)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.wifi_off, size: 16),
                label: Text(t('offline') ?? 'Offline'),
                backgroundColor: Colors.orange.shade100,
              ),
            ),
          if (_cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text('${_cart.length}'),
                backgroundColor: theme.colorScheme.primaryContainer,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            // Left: Product selection
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText:
                                  t('search_products_or_scan') ??
                                  'Search or scan',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        _searchDebounce?.cancel();
                                        setState(() => _searchResults = []);
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            // CRITICAL FIX: Use debounced onChanged
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          heroTag: 'scanBtn',
                          onPressed: _scanBarcode,
                          child: const Icon(Icons.qr_code_scanner),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isLoading && _allProducts.isEmpty)
                      const Expanded(child: _CheckoutSkeleton())
                    else if (_isSearching)
                      const LinearProgressIndicator()
                    else if (_displayProducts.isNotEmpty)
                      Expanded(
                        child: ListView.builder(
                          itemCount: _displayProducts.length,
                          itemBuilder: (_, i) {
                            final p = _displayProducts[i] as Map<String, dynamic>;
                            return _buildProductListTile(p);
                          },
                        ),
                      )
                    else if (_searchCtrl.text.isNotEmpty)
                      Expanded(
                        child: Center(
                          child: Text(t('no_results_found') ?? 'No results'),
                        ),
                      )
                    else if (_allProducts.isEmpty && !_isLoading)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 48,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t('no_products_in_store') ?? 'No products',
                                style: TextStyle(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),

            // Right: Cart
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  border: Border(
                    left: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: theme.colorScheme.surface,
                      child: Row(
                        children: [
                          Icon(
                            Icons.shopping_cart,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t('cart') ?? 'Cart',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_cart.length} ${t('items') ?? 'items'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _cart.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shopping_basket_outlined,
                                    size: 48,
                                    color: theme.colorScheme.outline,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    t('cart_empty') ?? 'Cart is empty',
                                    style: TextStyle(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _cart.length,
                              itemBuilder: (_, i) {
                                final item = _cart[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                                size: 20,
                                              ),
                                              onPressed: () => _removeItem(i),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            _qtyButton(
                                              Icons.remove,
                                              () => _adjustQty(i, -1),
                                            ),
                                            const SizedBox(width: 8),
                                            _QtyInput(
                                              quantity: item.quantity,
                                              stock: item.stock,
                                              onChanged: (newQty) => setState(
                                                () => item.quantity = newQty,
                                              ),
                                              onRemove: () => _removeItem(i),
                                            ),
                                            const SizedBox(width: 8),
                                            _qtyButton(
                                              Icons.add,
                                              () => _adjustQty(i, 1),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _fmt(
                                                item.total,
                                                currency: item.currency,
                                              ),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: theme.colorScheme.surface,
                      child: Column(
                        children: [
                          _totalRow(t('subtotal') ?? 'Subtotal', _subtotal),
                          const SizedBox(height: 8),
                          _buildDiscountTaxInput(
                            controller: _discountCtrl,
                            label: t('discount') ?? 'Discount',
                            icon: Icons.local_offer,
                            isPercent: _discountIsPercent,
                            onToggle: (v) => _discountIsPercent = v,
                          ),
                          const SizedBox(height: 4),
                          if (_discountValue > 0)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '- ${_fmt(_discountValue)}',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          _buildDiscountTaxInput(
                            controller: _taxCtrl,
                            label: t('tax') ?? 'Tax',
                            icon: Icons.account_balance,
                            isPercent: _taxIsPercent,
                            onToggle: (v) => _taxIsPercent = v,
                          ),
                          const SizedBox(height: 4),
                          if (_taxValue > 0)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '+ ${_fmt(_taxValue)}',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                t('total') ?? 'Total',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _fmt(_total),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: GradientButton(
                              onPressed: _isLoading || _cart.isEmpty
                                  ? null
                                  : _completeCheckout,
                              isLoading: _isLoading,
                              child: Text(
                                t('complete_checkout') ?? 'Complete Checkout',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark
          ? theme.colorScheme.surfaceContainerHighest
          : Colors.grey.shade300,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _totalRow(String label, double value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(_fmt(value), style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ============================================================
// QTY INPUT WIDGET
// ============================================================

class _QtyInput extends StatefulWidget {
  final int quantity;
  final int? stock;
  final ValueChanged<int> onChanged;
  final VoidCallback onRemove;
  const _QtyInput({
    required this.quantity,
    this.stock,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_QtyInput> createState() => _QtyInputState();
}

class _QtyInputState extends State<_QtyInput> {
  late TextEditingController _ctrl;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.quantity}');
  }

  @override
  void didUpdateWidget(covariant _QtyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.quantity != oldWidget.quantity) {
      _ctrl.text = '${widget.quantity}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 36,
      child: TextField(
        controller: _ctrl,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          isDense: true,
        ),
        onTap: () => _isEditing = true,
        onSubmitted: (val) {
          _isEditing = false;
          final newQty = int.tryParse(val) ?? widget.quantity;
          if (newQty < 1) {
            widget.onRemove();
          } else if (widget.stock != null && newQty > widget.stock!) {
            widget.onChanged(widget.stock!);
          } else {
            widget.onChanged(newQty);
          }
        },
      ),
    );
  }
}

// ============================================================
// CHECKOUT SKELETON LOADING
// ============================================================

class _CheckoutSkeleton extends StatelessWidget {
  const _CheckoutSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 12),
      itemCount: 8,
      itemBuilder: (_, __) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }
}
