// lib/screens/checkout_screen.dart
// FIXED: Offline product loading now correctly filters by storeId in catch block

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../utils/barcode_helper.dart';
import '../screens/barcode_scanner_screen.dart';
import '../screens/receipt_screen.dart';
import '../lang/translations.dart';
import '../widgets/gradient_button.dart';
import '../services/offline_service.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import '../services/product_service.dart';
import '../services/order_service.dart';

class CartItem {
  final int? productId;
  final String name;
  final double unitPrice;
  int quantity;
  final String? barcode;
  final int? stock;
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

class _CheckoutScreenState extends State<CheckoutScreen> {
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

  // NEW: Percentage toggle states
  bool _discountIsPercent = false;
  bool _taxIsPercent = false;

  /// Raw subtotal = sum of all item totals
  double get _rawSubtotal => _cart.fold(0, (sum, item) => sum + item.total);

  /// Discount value (calculated from percentage or flat)
  double get _discountValue {
    final raw = double.tryParse(_discountCtrl.text) ?? 0;
    if (_discountIsPercent && raw > 0) {
      return (_rawSubtotal * raw / 100).clamp(0, _rawSubtotal);
    }
    return raw.clamp(0, _rawSubtotal);
  }

  /// Tax value (calculated from percentage or flat)
  double get _taxValue {
    final raw = double.tryParse(_taxCtrl.text) ?? 0;
    if (_taxIsPercent && raw > 0) {
      return (_rawSubtotal * raw / 100);
    }
    return raw;
  }

  /// Subtotal shown on receipt = raw subtotal (before discount/tax)
  double get _subtotal => _rawSubtotal;

  /// Total = subtotal - discount + tax
  double get _total => _rawSubtotal - _discountValue + _taxValue;

  @override
  void initState() {
    super.initState();
    // Load both in parallel for faster startup
    Future.wait([_loadCashier(), _loadStoreProducts()]);
  }

  Future<void> _loadStoreProducts() async {
    if (mounted) setState(() => _isLoading = true);

    // ── Phase 1: Load from local cache immediately (never blocks UI) ──
    int? cachedStoreId;
    try {
      final cachedStore = await OfflineService.getCachedStore().timeout(
        const Duration(seconds: 2),
      );
      cachedStoreId = cachedStore?['id'] as int?;
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
            _searchResults = merged;
            _isLoading = false;
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
              _searchResults = cached;
              _isLoading = false;
            });
          }
        } catch (_) {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    }

    // ── Phase 2: Refresh from server in background (non-blocking) ──
    _refreshStoreFromServer(cachedStoreId);
  }

  Future<void> _refreshStoreFromServer(int? knownStoreId) async {
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
        products = await ProductService.fetchProducts(
          storeId,
          useCache: true,
        ).timeout(const Duration(seconds: 4));
        await OfflineService.cacheProducts(storeId, products);
      } catch (_) {
        if (knownStoreId != null) {
          products = await OfflineService.getMergedProducts(
            knownStoreId,
          ).timeout(const Duration(seconds: 2));
        }
      }

      if (mounted && products.isNotEmpty) {
        setState(() {
          _allProducts = products;
          _searchResults = products;
        });
      }
    } catch (_) {
      // Server unavailable — cached data already on screen, nothing to do
      if (mounted && _allProducts.isEmpty) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCashier() async {
    // Try both sources in parallel — with strict timeouts so offline never hangs
    final results = await Future.wait([
      AuthService.getCurrentUser()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => Future.value(null),
          )
          .catchError((_) => null),
      OfflineService.getCachedUser()
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => Future.value(null),
          )
          .catchError((_) => null),
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
      final product = await ProductService.findProductByBarcode(code);
      _addProductToCart(product);
    } catch (e) {
      // Offline fallback: search in cached products by barcode
      try {
        final storeIdFallback =
            _storeId ?? await OfflineService.getCachedStoreId();
        final cached = storeIdFallback != null
            ? await OfflineService.getCachedProducts(storeId: storeIdFallback)
            : await OfflineService.getCachedProducts();
        final match = cached.firstWhere(
          (p) => p['barcode']?.toString() == code,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          _addProductToCart(match);
        } else {
          _showError('${t('product_not_found') ?? 'Product not found'}: $code');
        }
      } catch (_) {
        _showError('${t('product_not_found') ?? 'Product not found'}: $code');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addProductToCart(Map<String, dynamic> product) {
    final existing = _cart.indexWhere((c) => c.productId == product['id']);
    final stock = (product['quantity'] as num?)?.toInt() ?? 0;

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
            productId: product['id'],
            name:
                product['name']?.toString() ??
                t('unknown_product') ??
                'Unknown',
            unitPrice: _parsePrice(product['price']),
            barcode: product['barcode']?.toString(),
            stock: stock,
            currency: product['currency']?.toString() ?? 'SYP',
          ),
        ),
      );
    }
  }

  Future<void> _searchProducts() async {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _searchResults = _allProducts);
      return;
    }
    final localFiltered = _allProducts.where((p) {
      final name = p['name']?.toString().toLowerCase() ?? '';
      final barcode = p['barcode']?.toString().toLowerCase() ?? '';
      return name.contains(query) || barcode.contains(query);
    }).toList();

    setState(() {
      _searchResults = localFiltered;
      _isSearching = false;
    });

    if (query.length >= 2) {
      setState(() => _isSearching = true);
      try {
        final results = await ProductService.searchStoreProducts(
          query: query,
          storeId: _storeId,
        );
        final merged = _mergeWithLocal(results);
        if (mounted) setState(() => _searchResults = merged);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _isSearching = false);
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

    // Check connectivity FIRST before touching stock
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = !connectivity.contains(ConnectivityResult.none);

    String _offlineReceipt() =>
        'OFF-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    if (!isOnline) {
      // OFFLINE: adjust cached stock only (no sync record to avoid double-deduction)
      for (final item in _cart) {
        if (item.productId != null) {
          await OfflineService.adjustCachedStockOnly(
            item.productId!,
            -item.quantity,
          );
        }
      }

      final orderData = {
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
        'receipt_number': _offlineReceipt(),
        'cashier_name': _cashierName ?? t('unknown') ?? 'Unknown',
        'created_at': DateTime.now().toIso8601String(),
      };

      await OfflineService.queueOrder(orderData);

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
      setState(() => _isLoading = false);
      return;
    }

    // ONLINE: send to server
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
        subtotal: _subtotal,
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
      // Server failed mid-checkout: queue offline
      for (final item in _cart) {
        if (item.productId != null) {
          await OfflineService.adjustCachedStockOnly(
            item.productId!,
            -item.quantity,
          );
        }
      }

      final orderData = {
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
        'receipt_number': _offlineReceipt(),
        'cashier_name': _cashierName ?? t('unknown') ?? 'Unknown',
        'created_at': DateTime.now().toIso8601String(),
      };
      await OfflineService.queueOrder(orderData);

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

  // NEW: Build discount/tax input with percentage toggle
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
                  // Percent toggle
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('checkout') ?? 'Checkout'),
        actions: [
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
                                        setState(() => _searchResults = []);
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (_) => _searchProducts(),
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
                    // FIXED: Added skeleton loading when loading with no products
                    if (_isLoading && _allProducts.isEmpty)
                      const Expanded(child: _CheckoutSkeleton())
                    else if (_isSearching)
                      const LinearProgressIndicator()
                    else if (_searchResults.isNotEmpty)
                      Expanded(
                        child: ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (_, i) {
                            final p = _searchResults[i];
                            final stock = (p['quantity'] as num?)?.toInt() ?? 0;
                            final isOutOfStock = stock <= 0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  child: Text(
                                    p['name']
                                            ?.toString()
                                            .substring(0, 1)
                                            .toUpperCase() ??
                                        '?',
                                  ),
                                ),
                                title: Text(
                                  p['name']?.toString() ?? '',
                                  style: isOutOfStock
                                      ? TextStyle(
                                          color: theme.colorScheme.outline,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        )
                                      : null,
                                ),
                                subtitle: Text(
                                  '${_fmt(_parsePrice(p['price']), currency: p['currency']?.toString() ?? 'SYP')} • $stock ${t('in_stock') ?? 'in stock'}',
                                  style: isOutOfStock
                                      ? TextStyle(
                                          color: theme.colorScheme.error,
                                        )
                                      : null,
                                ),
                                trailing: isOutOfStock
                                    ? const Icon(
                                        Icons.block,
                                        color: Colors.grey,
                                      )
                                    : IconButton(
                                        icon: const Icon(
                                          Icons.add_circle,
                                          color: Colors.green,
                                        ),
                                        onPressed: () => _addProductToCart(p),
                                      ),
                              ),
                            );
                          },
                        ),
                      )
                    else if (_searchCtrl.text.isNotEmpty)
                      Center(child: Text(t('no_results_found') ?? 'No results'))
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
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                  ),
                                              child: Text(
                                                '${item.quantity}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
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
                          // NEW: Discount with percentage toggle
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
                          // NEW: Tax with percentage toggle
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _discountCtrl.dispose();
    _taxCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
