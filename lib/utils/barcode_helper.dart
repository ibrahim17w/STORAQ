// lib/utils/barcode_helper.dart
// EAN-13 / UPC-A / Code128 / QR generation and validation

import 'dart:math';
import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';

class BarcodeHelper {
  // ==================== VALIDATION ====================

  static bool isValidEAN13(String code) {
    if (code.length != 13) return false;
    if (!RegExp(r'^\d{13}\$').hasMatch(code)) return false;
    return _eanChecksum(code.substring(0, 12)) == int.parse(code[12]);
  }

  static bool isValidUPC(String code) {
    if (code.length != 12) return false;
    if (!RegExp(r'^\d{12}\$').hasMatch(code)) return false;
    return _eanChecksum('0' + code.substring(0, 11)) == int.parse(code[11]);
  }

  static bool isValidCode128(String code) {
    // Code128 supports ASCII 32-127; allow printable chars
    if (code.isEmpty || code.length > 48) return false;
    return RegExp(r'^[ -~]+\$').hasMatch(code);
  }

  static bool isValidBarcode(String code) {
    if (code.isEmpty) return false;
    return isValidEAN13(code) || isValidUPC(code) || isValidCode128(code);
  }

  // ==================== GENERATION ====================

  /// Generate random EAN-13 barcode with valid checksum
  static String generateEAN13() {
    final rnd = Random.secure();
    final digits = List.generate(12, (_) => rnd.nextInt(10));
    final payload = digits.join();
    final checksum = _eanChecksum(payload);
    return payload + checksum.toString();
  }

  /// Generate UPC-A (12 digits)
  static String generateUPC() {
    final rnd = Random.secure();
    final digits = List.generate(11, (_) => rnd.nextInt(10));
    final payload = digits.join();
    final checksum = _eanChecksum('0' + payload);
    return payload + checksum.toString();
  }

  /// Generate Code128 from custom prefix + random suffix
  static String generateCode128({String prefix = 'MB'}) {
    final rnd = Random.secure();
    final suffix = List.generate(8, (_) => rnd.nextInt(10)).join();
    return '\$prefix-\$suffix';
  }

  static int _eanChecksum(String payload) {
    int sum = 0;
    for (int i = 0; i < payload.length; i++) {
      int digit = int.parse(payload[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    int mod = sum % 10;
    return mod == 0 ? 0 : 10 - mod;
  }

  // ==================== SVG RENDERING ====================

  /// Render barcode as SVG string for printing/display
  static String toSvg(String code, {String type = 'ean13', double width = 200, double height = 80}) {
    try {
      final bc = Barcode.fromType(_mapType(type));
      return bc.toSvg(code, width: width, height: height);
    } catch (e) {
      // Fallback to Code128 if specific type fails
      final fallback = Barcode.code128();
      return fallback.toSvg(code, width: width, height: height);
    }
  }

  static BarcodeType _mapType(String type) {
    switch (type.toLowerCase()) {
      case 'ean13': return BarcodeType.CodeEAN13;
      case 'upc':   return BarcodeType.CodeUPCA;
      case 'code128': return BarcodeType.Code128;
      case 'qr':    return BarcodeType.QrCode;
      default:      return BarcodeType.Code128;
    }
  }

  // ==================== FORMATTING ====================

  static String formatForDisplay(String code) {
    if (isValidEAN13(code)) {
      return '${code.substring(0, 1)} ${code.substring(1, 7)} ${code.substring(7, 13)}';
    }
    return code;
  }

  // ==================== CLIPBOARD ====================

  static Future<void> copyToClipboard(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
  }
}
