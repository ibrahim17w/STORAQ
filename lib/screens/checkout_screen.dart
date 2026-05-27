// lib/screens/checkout_screen.dart
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
  List<dynamic> _allProducts = []; // full store inventory
  List<dynamic> _searchResults = [];
  String? _cashierName;
  int? _storeId;

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get _tax => double.tryParse(_taxCtrl.text) ?? 0;
  double get _total => _subtotal - _discount + _tax;

  @override
  void initState() {
    super.initState();
    _loadCashier();
    _loadStoreProducts();
  }

  Future<void> _loadStoreProducts() async {
    setState(() => _isLoading = true);
    try {
      // Try to get my store first
      final store = await ApiService.getMyStore();
      _storeId = store['id'];
      final products = await ApiService.fetchProducts(
        _storeId!,
        useCache: true,
      );
      if (mounted) {
        setState(() {
          _allProducts = products;
          _searchResults = products; // show all by default
          _isLoading = false;
        });
      }
      // Also cache to local DB for offline
      await OfflineService.cacheProducts(_storeId!, products);
    } catch (e) {
      // Fallback: load from local cache if offline
      try {
        final cached = await OfflineService.getCachedProducts();
        if (mounted && cached.isNotEmpty) {
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

  Future<void> _loadCashier() async {
    try {
      final user = await ApiService.getCurrentUser();
      if (mounted) setState(() => _cashierName = user['full_name']?.toString());
    } catch (_) {}
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
      final product = await ApiService.findProductByBarcode(code);
      _addProductToCart(product);
    } catch (e) {
      _showError('${t('product_not_found')}: $code');
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
        _showError(t('insufficient_stock'));
        return;
      }
      setState(() => item.quantity++);
    } else {
      if (stock < 1) {
        _showError(t('out_of_stock'));
        return;
      }
      setState(
        () => _cart.add(
          CartItem(
            productId: product['id'],
            name: product['name']?.toString() ?? t('unknown_product'),
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
    // Local filter first (works offline)
    final localFiltered = _allProducts.where((p) {
      final name = p['name']?.toString().toLowerCase() ?? '';
      final barcode = p['barcode']?.toString().toLowerCase() ?? '';
      return name.contains(query) || barcode.contains(query);
    }).toList();

    setState(() {
      _searchResults = localFiltered;
      _isSearching = false;
    });

    // Also try server search for broader results
    if (query.length >= 2) {
      setState(() => _isSearching = true);
      try {
        final results = await ApiService.searchStoreProducts(
          query: query,
          storeId: _storeId,
        );
        // Merge server results with local, preferring local data for stock accuracy
        final merged = _mergeWithLocal(results);
        if (mounted) setState(() => _searchResults = merged);
      } catch (_) {
        // Keep local results on error
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
        // Use local stock if more recent
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
      _showError(t('insufficient_stock'));
      return;
    }
    setState(() => item.quantity = newQty);
  }

  void _removeItem(int index) {
    setState(() => _cart.removeAt(index));
  }

  Future<void> _completeCheckout() async {
    if (_cart.isEmpty) {
      _showError(t('cart_empty'));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('confirm_checkout')),
        content: Text('${t('total_amount')}: ${_fmt(_total)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);

    // Update local stock first (works offline)
    for (final item in _cart) {
      if (item.productId != null) {
        await OfflineService.updateLocalStock(item.productId!, -item.quantity);
      }
    }

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity != ConnectivityResult.none;

    if (!isOnline) {
      // Queue order for later sync
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
        'discount': _discount,
        'tax': _tax,
        'total': _total,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'payment_method': 'cash',
        'created_at': DateTime.now().toIso8601String(),
      };

      await OfflineService.queueOrder(orderData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${t('order_saved_offline')} — ${t('sync_when_online')}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        // Show local receipt instead of server receipt
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

    // Online: send to server
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
            },
          )
          .toList();

      final order = await ApiService.createOrder(
        items: items,
        customerName: _customerNameCtrl.text.trim().isEmpty
            ? null
            : _customerNameCtrl.text.trim(),
        customerPhone: _customerPhoneCtrl.text.trim().isEmpty
            ? null
            : _customerPhoneCtrl.text.trim(),
        discount: _discount,
        tax: _tax,
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
      // Server failed — queue locally and show offline receipt
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
        'discount': _discount,
        'tax': _tax,
        'total': _total,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'payment_method': 'cash',
        'created_at': DateTime.now().toIso8601String(),
      };
      await OfflineService.queueOrder(orderData);

      if (mounted) {
        final errMsg = e.toString();
        final shortErr = errMsg.length > 60
            ? '${errMsg.substring(0, 60)}...'
            : errMsg;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${t('server_error') ?? 'Server error'} — ${t('order_saved_offline') ?? 'Saved locally'}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('checkout')),
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
                    // Search + Scan
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: t('search_products_or_scan'),
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
                    // Product list (all inventory or filtered search)
                    if (_isSearching)
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
                                  '${_fmt(_parsePrice(p['price']), currency: p['currency']?.toString() ?? 'SYP')} • $stock ${t('in_stock')}',
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
                      Center(child: Text(t('no_results_found')))
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
                                t('no_products_in_store'),
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
                    // Cart header
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
                            t('cart'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_cart.length} ${t('items')}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    // Cart items
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
                                    t('cart_empty'),
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
                    // Totals
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: theme.colorScheme.surface,
                      child: Column(
                        children: [
                          _totalRow(t('subtotal'), _subtotal),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _discountCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: t('discount'),
                                    prefixIcon: const Icon(Icons.local_offer),
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
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _taxCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: t('tax'),
                                    prefixIcon: const Icon(
                                      Icons.account_balance,
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
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                t('total'),
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
                                t('complete_checkout'),
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
