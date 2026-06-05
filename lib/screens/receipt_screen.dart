// lib/screens/receipt_screen.dart
// FIXED: Offline receipts render immediately without blocking on network calls

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../services/store_service.dart';
import '../services/order_service.dart';
import '../services/offline_service.dart';

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

  final GlobalKey _printKey = GlobalKey();

  /// Configure this later to your app store / download link
  static const String _appDownloadUrl = 'https://marketbridge.app/download';

  @override
  void initState() {
    super.initState();
    if (widget.offlineOrder != null) {
      _loadOffline();
    } else {
      _loadOnline();
    }
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadOffline() async {
    // CRITICAL FIX: Render the receipt IMMEDIATELY with what we have.
    // Do NOT wait for network calls. Fire async enrichment in background.
    if (mounted) {
      setState(() {
        _order = widget.offlineOrder;
        _store = {'name': t('my_store') ?? 'My Store'};
        _settings = {
          'footer_message': t('thank_you') ?? 'Thank you for your purchase!',
          'show_logo': false,
          'show_barcode': true,
          'currency_symbol': 'SYP',
        };
        _loading = false;
      });
    }

    // Background enrichment: try to load store + settings from cache/server
    // but never block the UI or revert to loading state.
    _enrichOfflineData();
  }

  Future<void> _enrichOfflineData() async {
    try {
      Map<String, dynamic>? store;
      Map<String, dynamic>? settings;

      // Try cached store first (fast, no network)
      try {
        store = await OfflineService.getCachedStore();
      } catch (_) {}

      settings = await OrderService.getReceiptSettingsOffline();

      // Try server (may fail if offline)
      try {
        store ??= await StoreService.getMyStore();
      } catch (_) {}
      try {
        settings = await OrderService.loadReceiptSettings();
      } catch (_) {}

      if (mounted && store != null) {
        setState(() => _store = store);
      }
      if (mounted && settings != null) {
        setState(() => _settings = settings);
      }
    } catch (_) {
      // Never crash — receipt is already visible with defaults
    }
  }

  Future<void> _loadOnline() async {
    try {
      final response = await OrderService.fetchOrder(widget.orderId!);

      final orderRow = response['order'] as Map<String, dynamic>? ?? {};
      final items = response['items'] as List<dynamic>? ?? [];
      final flattenedOrder = <String, dynamic>{...orderRow, 'items': items};

      Map<String, dynamic>? store;
      Map<String, dynamic>? settings;

      try {
        store = await StoreService.getMyStore();
      } catch (_) {
        store = await OfflineService.getCachedStore();
      }
      try {
        settings = await OrderService.loadReceiptSettings();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _order = flattenedOrder;
          _store = store ?? {'name': t('my_store') ?? 'My Store'};
          _settings =
              settings ??
              {
                'footer_message':
                    t('thank_you') ?? 'Thank you for your purchase!',
                'show_logo': true,
                'show_barcode': true,
                'currency_symbol': 'SYP',
              };
          _loading = false;
        });
      }
    } catch (e) {
      // Server failed — try to find this order in offline orders
      try {
        final offlineOrders = await OfflineService.getOfflineOrders();
        final match = offlineOrders.firstWhere(
          (o) =>
              o['id'] == widget.orderId?.toString() ||
              o['receipt_number'] == widget.orderId?.toString(),
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          if (mounted) {
            setState(() {
              _order = match;
              _store = {'name': t('my_store') ?? 'My Store'};
              _settings = {
                'footer_message':
                    t('thank_you') ?? 'Thank you for your purchase!',
                'show_logo': true,
                'show_barcode': true,
                'currency_symbol': 'SYP',
              };
              _loading = false;
            });
          }
          return;
        }
      } catch (_) {}

      // No offline match found — show error but don't crash
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${t('order_not_found') ?? 'Order not found'}: ${e.toString().split('\n').first}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ==================== PRICE / HELPERS ====================

  String get _currency => _settings?['currency_symbol']?.toString() ?? 'SYP';

  double _parsePrice(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String)
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  String _fmt(dynamic value) {
    final d = _parsePrice(value);
    return '$_currency ${d.toStringAsFixed(2)}';
  }

  String get _receiptNumber =>
      _order?['receipt_number']?.toString() ??
      _order?['id']?.toString() ??
      'OFFLINE';

  List<Map<String, dynamic>> get _items =>
      List<Map<String, dynamic>>.from(_order?['items'] ?? []);

  double _itemTotal(Map<String, dynamic> item) {
    final tp = _parsePrice(item['total_price']);
    if (tp > 0) return tp;
    final p = _parsePrice(item['price']);
    final q = (item['quantity'] as num?)?.toDouble() ?? 1.0;
    return p * q;
  }

  double get _computedSubtotal {
    final stored = _parsePrice(_order?['subtotal']);
    if (stored > 0) return stored;
    return _items.fold<double>(0, (sum, item) => sum + _itemTotal(item));
  }

  double get _computedDiscount {
    if (_order?.containsKey('discount') == true) {
      return _parsePrice(_order!['discount']);
    }
    final subtotal = _computedSubtotal;
    final total = _parsePrice(_order?['total']);
    if (total > 0 && total < subtotal) {
      return (subtotal - total).clamp(0.0, subtotal);
    }
    return 0;
  }

  double get _computedTax {
    if (_order?.containsKey('tax') == true) {
      return _parsePrice(_order!['tax']);
    }
    return 0;
  }

  double get _computedTotal {
    final stored = _parsePrice(_order?['total']);
    final computed = _computedSubtotal - _computedDiscount + _computedTax;

    if (stored <= 0) return computed;

    final diffFromSubtotal = (stored - _computedSubtotal).abs();
    if (diffFromSubtotal < 0.01 &&
        (_computedDiscount > 0 || _computedTax > 0)) {
      return computed;
    }

    if ((stored - computed).abs() < 0.01) return stored;

    return computed;
  }

  String _translatedAddress(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    String result = raw;
    final replacements = {
      'Governorate': t('governorate') ?? 'Governorate',
      'District': t('district') ?? 'District',
      'Subdistrict': t('subdistrict') ?? 'Subdistrict',
      'Syria': t('syria') ?? 'Syria',
      'governorate': t('governorate') ?? 'governorate',
      'district': t('district') ?? 'district',
      'subdistrict': t('subdistrict') ?? 'subdistrict',
      'syria': t('syria') ?? 'syria',
    };
    replacements.forEach((en, tr) {
      result = result.replaceAll(en, tr);
    });
    return result;
  }

  // ==================== PDF CAPTURE ====================

  Future<Uint8List> _captureReceiptImage() async {
    final context = _printKey.currentContext;
    if (context == null) {
      throw Exception('Receipt not ready. Please wait and try again.');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    final renderObject = context.findRenderObject();
    if (renderObject == null || renderObject is! RenderRepaintBoundary) {
      throw Exception('Receipt render object not found.');
    }
    final image = await renderObject.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to encode receipt image.');
    return byteData.buffer.asUint8List();
  }

  Future<pw.Document> _buildPdf() async {
    final bytes = await _captureReceiptImage();
    final pdfImage = pw.MemoryImage(bytes);

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                boxShadow: const [
                  pw.BoxShadow(
                    color: PdfColors.grey300,
                    blurRadius: 6,
                    offset: PdfPoint(0, 3),
                  ),
                ],
              ),
              child: pw.ClipRRect(
                horizontalRadius: 8,
                verticalRadius: 8,
                child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
              ),
            ),
          );
        },
      ),
    );
    return pdf;
  }

  // ==================== EXPORT / PRINT / SHARE ====================

  Future<void> _exportPdf() async => _generatePdfAndSave();
  Future<void> _printPdf() async => _generatePdfAndPrint();
  Future<void> _shareReceipt() async => _generatePdfAndShare();

  Future<void> _generatePdfAndSave() async {
    try {
      final pdf = await _buildPdf();
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/receipt_$_receiptNumber.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('pdf_saved') ?? 'PDF saved'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: t('open') ?? 'Open',
              onPressed: () => OpenFilex.open(file.path),
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('PDF export error: $e\n$st');
      if (mounted) _showError('${t('export_failed') ?? 'Export failed'}: $e');
    }
  }

  Future<void> _generatePdfAndPrint() async {
    try {
      final pdf = await _buildPdf();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e, st) {
      debugPrint('Print error: $e\n$st');
      if (mounted) _showError('${t('print_failed') ?? 'Print failed'}: $e');
    }
  }

  Future<void> _generatePdfAndShare() async {
    try {
      final pdf = await _buildPdf();
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/receipt_$_receiptNumber.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([
        XFile(file.path),
      ], text: '${t('receipt')}: #$_receiptNumber');
    } catch (e, st) {
      debugPrint('Share receipt error: $e\n$st');
      if (mounted) _showError('${t('share_failed') ?? 'Share failed'}: $e');
    }
  }

  // ==================== RECEIPT CONTENT ====================

  Widget _buildReceiptContent(ThemeData theme, {bool isPrint = false}) {
    final items = _items;
    final date =
        DateTime.tryParse(_order?['created_at']?.toString() ?? '') ??
        DateTime.now();

    final subtotal = _computedSubtotal;
    final discount = _computedDiscount;
    final tax = _computedTax;
    final total = _computedTotal;
    final hasDiscount = _order?.containsKey('discount') == true || discount > 0;
    final hasTax = _order?.containsKey('tax') == true || tax > 0;

    final bool isDark = theme.brightness == Brightness.dark;
    final Color totalBoxBg = isDark
        ? const Color(0xFF2D3142)
        : const Color(0xFFEEF2FF);
    final Color totalBoxBorder = isDark
        ? const Color(0xFF4A5568)
        : const Color(0xFF4338CA);
    final Color totalLabelColor = isDark
        ? Colors.white
        : const Color(0xFF1E1B4B);
    final Color totalValueColor = isDark
        ? const Color(0xFF63B3ED)
        : const Color(0xFF312E81);

    // FIXED: Use cashier_name from order (survives account deletion)
    // Falls back to cashier_id only if cashier_name is missing (legacy orders)
    final cashierName =
        _order?['cashier_name']?.toString() ??
        _order?['cashier']?.toString() ??
        _order?['cashier_id']?.toString() ??
        t('unknown');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo
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
        if (_settings?['show_logo'] == true && _store?['image_url'] != null)
          const SizedBox(height: 12),

        // Store name
        Text(
          _store?['name']?.toString() ?? t('my_store'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),

        // City / address (translated)
        if (_store?['city'] != null)
          Text(
            _translatedAddress(_store!['city'].toString()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        const Divider(height: 24),

        // Meta rows
        _receiptRow(t('receipt_number'), _receiptNumber, theme),
        _receiptRow(
          t('date'),
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
          theme,
        ),
        // FIXED: Display proper cashier name from order
        _receiptRow(t('cashier'), cashierName, theme),
        if (_order?['customer_name'] != null)
          _receiptRow(
            t('customer'),
            _order!['customer_name'].toString(),
            theme,
          ),
        const Divider(height: 24),

        // Offline badge
        if (_order?['receipt_number']?.toString().startsWith('OFF-') ?? false)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Text(
                  t('offline_receipt') ?? 'Offline Receipt',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

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

        // Items
        ...items.map((item) {
          final name =
              item['product_name']?.toString() ??
              item['name']?.toString() ??
              t('unknown');
          final qty = item['quantity'] ?? 1;
          final itemTotal = _itemTotal(item);
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
                    _fmt(itemTotal),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          );
        }),

        const Divider(height: 24),

        // Subtotal
        _totalRow(t('subtotal'), subtotal),
        if (hasDiscount) _totalRow(t('discount'), discount, isNegative: true),
        if (hasTax) _totalRow(t('tax'), tax),
        const SizedBox(height: 12),

        // Total box
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: totalBoxBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: totalBoxBorder, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t('total'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: totalLabelColor,
                ),
              ),
              Text(
                _fmt(total),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: totalValueColor,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ),

        // Footer
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Text(
            _settings?['footer_message']?.toString() ??
                t('thank_you') ??
                'Thank you for your purchase!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        // QR Code
        if (_settings?['show_barcode'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: Column(
                children: [
                  BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: _appDownloadUrl,
                    width: 100,
                    height: 100,
                    color: theme.colorScheme.primary,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _receiptNumber,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReceiptCard(ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildReceiptContent(theme),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: Text(t('export_pdf') ?? 'Export PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _printPdf,
                    icon: const Icon(Icons.print),
                    label: Text(t('print') ?? 'Print'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrintableReceipt(ThemeData theme) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildReceiptContent(theme, isPrint: true),
      ),
    );
  }

  Widget _receiptRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            isNegative ? '-${_fmt(value)}' : _fmt(value),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lightTheme = ThemeData.light().copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t('receipt')),
        actions: [
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
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _buildReceiptCard(theme),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -10000,
                    top: 0,
                    child: RepaintBoundary(
                      key: _printKey,
                      child: SizedBox(
                        width: 420,
                        child: Material(
                          color: Colors.white,
                          child: Theme(
                            data: lightTheme,
                            child: _buildPrintableReceipt(lightTheme),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
