// lib/screens/checkout_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../utils/barcode_helper.dart';
import '../screens/barcode_scanner_screen.dart';
import '../screens/receipt_screen.dart';
import '../lang/translations.dart';
import '../widgets/gradient_button.dart';

class CartItem {
  final int? productId;
  final String name;
  final double unitPrice;
  int quantity;
  final String? barcode;
  final int? stock;

  CartItem({
    this.productId,
    required this.name,
    required this.unitPrice,
    this.quantity = 1,
    this.barcode,
    this.stock,
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
  List<dynamic> _searchResults = [];
  String? _cashierName;

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.total);
  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get _tax => double.tryParse(_taxCtrl.text) ?? 0;
  double get _total => _subtotal - _discount + _tax;

  @override
  void initState() {
    super.initState();
    _loadCashier();
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
            unitPrice: (product['price'] as num?)?.toDouble() ?? 0,
            barcode: product['barcode']?.toString(),
            stock: stock,
          ),
        ),
      );
    }
  }

  Future<void> _searchProducts() async {
    final query = _searchCtrl.text.trim();
    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await ApiService.searchStoreProducts(query: query);
      if (mounted) setState(() => _searchResults = results);
    } catch (_) {
      setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
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
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  String _fmt(double value) => '${value.toStringAsFixed(2)} SYP';

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
                    // Search results
                    if (_isSearching)
                      const LinearProgressIndicator()
                    else if (_searchResults.isNotEmpty)
                      Expanded(
                        child: ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (_, i) {
                            final p = _searchResults[i];
                            final stock = (p['quantity'] as num?)?.toInt() ?? 0;
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
                                title: Text(p['name']?.toString() ?? ''),
                                subtitle: Text(
                                  '${_fmt((p['price'] as num?)?.toDouble() ?? 0)} • $stock ${t('in_stock')}',
                                ),
                                trailing: IconButton(
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
                    else if (_searchCtrl.text.length >= 2)
                      Center(child: Text(t('no_results_found')))
                    else
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search,
                                size: 48,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t('type_to_search'),
                                style: TextStyle(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                                              _fmt(item.total),
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
    return Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18),
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
