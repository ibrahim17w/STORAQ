// lib/utils/receipt_helper.dart
// Thermal printer formatting + PDF generation helpers

import 'dart:typed_data';
import 'package:intl/intl.dart';

class ReceiptLine {
  final String left;
  final String right;
  final bool bold;
  final bool separator;
  final bool center;
  final String? raw;

  const ReceiptLine({
    this.left = '',
    this.right = '',
    this.bold = false,
    this.separator = false,
    this.center = false,
    this.raw,
  });
}

class ReceiptHelper {
  static const int _thermalWidth = 48; // chars for 80mm thermal printer

  /// Build plain-text receipt formatted for thermal printers
  static String buildThermalText({
    required String storeName,
    required String storeAddress,
    String? storePhone,
    required String cashierName,
    required String receiptNumber,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    double discount = 0,
    double tax = 0,
    required double total,
    required String currency,
    String? footer,
    String? storeLogoBase64,
  }) {
    final buf = StringBuffer();
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');

    // Header
    buf.writeln(_center(storeName, _thermalWidth));
    if (storeAddress.isNotEmpty) {
      buf.writeln(_center(storeAddress, _thermalWidth));
    }
    if (storePhone != null && storePhone.isNotEmpty) {
      buf.writeln(_center(storePhone, _thermalWidth));
    }
    buf.writeln(_separator('-'));
    buf.writeln(_twoCol('Receipt #', receiptNumber, _thermalWidth));
    buf.writeln(_twoCol('Date', dateFmt.format(date), _thermalWidth));
    buf.writeln(_twoCol('Cashier', cashierName, _thermalWidth));
    buf.writeln(_separator('-'));

    // Items header
    buf.writeln(_twoCol('Item', 'Total', _thermalWidth));
    buf.writeln(_separator('-'));

    for (final item in items) {
      final name = item['product_name']?.toString() ?? 'Unknown';
      final qty = item['quantity'] ?? 1;
      final unit = (item['unit_price'] as num).toDouble();
      final lineTotal = (item['total_price'] as num).toDouble();

      // Product name (truncated if too long)
      buf.writeln(_truncate(name, _thermalWidth));
      // Qty x unit price = total
      final right =
          '${qty}x${_fmt(unit, currency)} = ${_fmt(lineTotal, currency)}';
      buf.writeln(_twoCol('', right, _thermalWidth));
    }

    buf.writeln(_separator('-'));

    // Totals
    buf.writeln(_twoCol('Subtotal', _fmt(subtotal, currency), _thermalWidth));
    if (discount > 0) {
      buf.writeln(
        _twoCol('Discount', '-${_fmt(discount, currency)}', _thermalWidth),
      );
    }
    if (tax > 0) {
      buf.writeln(_twoCol('Tax', _fmt(tax, currency), _thermalWidth));
    }
    buf.writeln(_separator('='));
    buf.writeln(_twoCol('TOTAL', _fmt(total, currency), _thermalWidth));
    buf.writeln(_separator('-'));

    // Footer
    if (footer != null && footer.isNotEmpty) {
      buf.writeln();
      buf.writeln(_center(footer, _thermalWidth));
    }

    // Barcode line
    buf.writeln();
    buf.writeln(_center('*' * 20, _thermalWidth));
    buf.writeln(_center(receiptNumber, _thermalWidth));
    buf.writeln(_center('*' * 20, _thermalWidth));

    return buf.toString();
  }

  /// Build HTML receipt for PDF export / web print
  static String buildHtmlReceipt({
    required String storeName,
    required String storeAddress,
    String? storePhone,
    String? storeLogoUrl,
    required String cashierName,
    required String receiptNumber,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    double discount = 0,
    double tax = 0,
    required double total,
    required String currency,
    String? footer,
    required bool isRTL,
  }) {
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');
    final dir = isRTL ? 'rtl' : 'ltr';
    final align = isRTL ? 'right' : 'left';
    final totalAlign = isRTL ? 'left' : 'right';

    final rows = items.map((item) {
      final name = _escapeHtml(item['product_name']?.toString() ?? 'Unknown');
      final qty = item['quantity'] ?? 1;
      final unit = (item['unit_price'] as num).toDouble();
      final lineTotal = (item['total_price'] as num).toDouble();
      return '''
        <tr>
          <td style="padding:6px 0;border-bottom:1px dashed #ccc;$align">
            <div style="font-weight:600;">$name</div>
            <div style="font-size:12px;color:#666;">$qty x ${_fmt(unit, currency)}</div>
          </td>
          <td style="padding:6px 0;border-bottom:1px dashed #ccc;text-align:$totalAlign;font-weight:600;">
            ${_fmt(lineTotal, currency)}
          </td>
        </tr>
      ''';
    }).join();

    return '''
<!DOCTYPE html>
<html lang="en" dir="$dir">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Receipt $receiptNumber</title>
<style>
  @media print {
    body { margin:0; }
    .receipt { box-shadow:none !important; margin:0 !important; max-width:100% !important; }
  }
  body { font-family: 'Segoe UI', Arial, sans-serif; background:#f5f5f5; margin:0; padding:20px; }
  .receipt { max-width:400px; margin:0 auto; background:#fff; padding:24px; border-radius:12px; box-shadow:0 4px 20px rgba(0,0,0,0.1); }
  .header { text-align:center; margin-bottom:16px; }
  .header img { max-height:60px; margin-bottom:8px; }
  .store-name { font-size:20px; font-weight:800; color:#2c3e50; }
  .store-info { font-size:13px; color:#666; margin-top:4px; }
  .meta { margin:16px 0; padding:12px 0; border-top:1px dashed #ddd; border-bottom:1px dashed #ddd; }
  .meta-row { display:flex; justify-content:space-between; font-size:13px; color:#555; margin:4px 0; }
  table { width:100%; border-collapse:collapse; margin:12px 0; }
  .totals { margin-top:16px; padding-top:12px; border-top:2px solid #333; }
  .total-row { display:flex; justify-content:space-between; margin:6px 0; font-size:14px; }
  .grand-total { font-size:18px; font-weight:800; color:#2c3e50; margin-top:8px; padding-top:8px; border-top:2px solid #333; }
  .footer { text-align:center; margin-top:20px; font-size:12px; color:#888; }
  .barcode-area { text-align:center; margin-top:16px; padding-top:12px; border-top:1px dashed #ddd; }
</style>
</head>
<body>
<div class="receipt">
  <div class="header">
    ${storeLogoUrl != null ? '<img src="$storeLogoUrl" alt="logo" />' : ''}
    <div class="store-name">${_escapeHtml(storeName)}</div>
    <div class="store-info">${_escapeHtml(storeAddress)}${storePhone != null ? '<br/>$storePhone' : ''}</div>
  </div>
  <div class="meta">
    <div class="meta-row"><span>Receipt #</span><span>$receiptNumber</span></div>
    <div class="meta-row"><span>Date</span><span>${dateFmt.format(date)}</span></div>
    <div class="meta-row"><span>Cashier</span><span>${_escapeHtml(cashierName)}</span></div>
  </div>
  <table>
    <tbody>$rows</tbody>
  </table>
  <div class="totals">
    <div class="total-row"><span>Subtotal</span><span>${_fmt(subtotal, currency)}</span></div>
    ${discount > 0 ? '<div class="total-row"><span>Discount</span><span>-${_fmt(discount, currency)}</span></div>' : ''}
    ${tax > 0 ? '<div class="total-row"><span>Tax</span><span>${_fmt(tax, currency)}</span></div>' : ''}
    <div class="grand-total"><span>TOTAL</span><span>${_fmt(total, currency)}</span></div>
  </div>
  ${footer != null && footer.isNotEmpty ? '<div class="footer">${_escapeHtml(footer)}</div>' : ''}
  <div class="barcode-area">
    <svg style="max-width:200px;" viewBox="0 0 200 60">
      <rect x="0" y="0" width="200" height="60" fill="white"/>
      <text x="100" y="35" text-anchor="middle" font-family="monospace" font-size="14">$receiptNumber</text>
    </svg>
  </div>
</div>
</body>
</html>
    ''';
  }

  // ==================== PRIVATE HELPERS ====================

  static String _center(String text, int width) {
    if (text.length >= width) return text;
    final pad = (width - text.length) ~/ 2;
    return ' ' * pad + text;
  }

  static String _twoCol(String left, String right, int width) {
    final rightLen = right.length;
    final avail = width - rightLen;
    if (avail <= 1) {
      if (rightLen > width) {
        return right.substring(0, width);
      }
      return ' ' * (width - rightLen) + right;
    }
    if (left.length >= avail) {
      return left.substring(0, avail - 1) + ' ' + right;
    }
    return left + ' ' * (avail - left.length) + right;
  }

  static String _separator(String char) => char * _thermalWidth;

  static String _truncate(String text, int max) {
    if (text.length <= max) return text;
    return text.substring(0, max - 3) + '...';
  }

  static String _fmt(double value, String currency) {
    return '$currency ${value.toStringAsFixed(2)}';
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
