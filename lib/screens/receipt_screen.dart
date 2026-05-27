// lib/screens/receipt_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../utils/receipt_helper.dart';
import '../lang/translations.dart';

class ReceiptScreen extends StatefulWidget {
  final int? orderId;
  final Map<String, dynamic>? offlineOrder;
  const ReceiptScreen({super.key, this.orderId, this.offlineOrder});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _store;
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    if (widget.offlineOrder != null) {
      _loadOffline();
    } else {
      _loadOnline();
    }
  }

  Future<void> _loadOffline() async {
    try {
      final store = await ApiService.getMyStore().catchError((_) => null);
      final settings = await ApiService.getReceiptSettings().catchError(
        (_) => null,
      );
      if (mounted) {
        setState(() {
          _order = widget.offlineOrder;
          _store = store ?? {'name': t('my_store')};
          _settings =
              settings ??
              {
                'footer_message': 'Thank you!',
                'show_logo': false,
                'show_barcode': false,
                'currency_symbol': 'SYP',
              };
          _loading = false;
          _isOffline = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOnline() async {
    try {
      final order = await ApiService.fetchOrder(widget.orderId!);
      final store = await ApiService.getMyStore();
      final settings = await ApiService.getReceiptSettings();
      if (mounted) {
        setState(() {
          _order = order;
          _store = store;
          _settings = settings;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  String get _currency => _settings?['currency_symbol']?.toString() ?? 'SYP';

  String _fmt(dynamic value) {
    final d = (value as num?)?.toDouble() ?? 0;
    return '$_currency ${d.toStringAsFixed(2)}';
  }

  Future<void> _copyReceipt() async {
    final text = _buildThermalText();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('receipt_copied')),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _shareReceipt() async {
    final text = _buildThermalText();
    await Share.share(
      text,
      subject:
          '${t('receipt')} #${_order?['receipt_number'] ?? widget.orderId}',
    );
  }

  String _buildThermalText() {
    if (_order == null) return '';
    final items = List<Map<String, dynamic>>.from(_order!['items'] ?? []);
    return ReceiptHelper.buildThermalText(
      storeName: _store?['name']?.toString() ?? t('my_store'),
      storeAddress: _store?['city']?.toString() ?? '',
      storePhone: _store?['phone']?.toString(),
      cashierName: _order!['cashier_name']?.toString() ?? t('unknown'),
      receiptNumber:
          _order!['receipt_number']?.toString() ?? '${_order!['id']}',
      date: DateTime.parse(
        _order!['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      ),
      items: items,
      subtotal: (_order!['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (_order!['discount'] as num?)?.toDouble() ?? 0,
      tax: (_order!['tax'] as num?)?.toDouble() ?? 0,
      total: (_order!['total'] as num?)?.toDouble() ?? 0,
      currency: _currency,
      footer: _settings?['footer_message']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('receipt')),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _order != null ? _copyReceipt : null,
            tooltip: t('copy'),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _order != null ? _shareReceipt : null,
            tooltip: t('share'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _order == null
          ? Center(child: Text(t('order_not_found')))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _buildReceiptCard(theme),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildReceiptCard(ThemeData theme) {
    final items = List<Map<String, dynamic>>.from(_order!['items'] ?? []);
    final date =
        DateTime.tryParse(_order!['created_at']?.toString() ?? '') ??
        DateTime.now();

    // FIX: Pre-compute bools outside the widget tree
    final discountVal = (_order!['discount'] as num?)?.toDouble() ?? 0;
    final taxVal = (_order!['tax'] as num?)?.toDouble() ?? 0;
    final hasDiscount = discountVal > 0;
    final hasTax = taxVal > 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Store header
            if (_settings?['show_logo'] == true && _store?['image_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _store!['image_url'],
                  height: 60,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              _store?['name']?.toString() ?? t('my_store'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (_store?['city'] != null)
              Text(
                _store!['city'].toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            const Divider(height: 24),

            // Meta
            _receiptRow(
              t('receipt_number'),
              _order!['receipt_number']?.toString() ?? '${_order!['id']}',
            ),
            _receiptRow(
              t('date'),
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
            ),
            _receiptRow(
              t('cashier'),
              _order!['cashier_name']?.toString() ?? t('unknown'),
            ),
            if (_order!['customer_name'] != null)
              _receiptRow(t('customer'), _order!['customer_name'].toString()),
            const Divider(height: 24),

            // Items header
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    t('item'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    t('qty'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    t('total'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map((item) {
              final name = item['product_name']?.toString() ?? t('unknown');
              final qty = item['quantity'] ?? 1;
              final total = (item['total_price'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(child: Text('$qty', textAlign: TextAlign.center)),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _fmt(total),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 24),

            // Totals — FIXED: use pre-computed bools
            _totalRow(t('subtotal'), _order!['subtotal']),
            if (hasDiscount)
              _totalRow(t('discount'), _order!['discount'], isNegative: true),
            if (hasTax) _totalRow(t('tax'), _order!['tax']),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t('total'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _fmt(_order!['total']),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            if (_settings?['footer_message'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  _settings!['footer_message'].toString(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            // Barcode
            if (_settings?['show_barcode'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.qr_code,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _order!['receipt_number']?.toString() ??
                              '${_order!['id']}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyReceipt,
                    icon: const Icon(Icons.copy),
                    label: Text(t('copy')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      _showError(t('printer_not_connected'));
                    },
                    icon: const Icon(Icons.print),
                    label: Text(t('print')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, dynamic value, {bool isNegative = false}) {
    final val = (value as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            isNegative ? '-${_fmt(val)}' : _fmt(val),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }
}
