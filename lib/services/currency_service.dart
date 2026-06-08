// lib/services/currency_service.dart
//
// Multi-currency display support. This service is ADDITIVE: it never mutates
// the product's real `price`/`currency`. It only resolves a separate "display"
// price for showing converted values to customers, and works fully offline by
// caching the store's currency settings and converting client-side.
import 'dart:convert';
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'offline_service.dart';
import '../models/models.dart';

class CurrencyService {
  // ============================================================
  // SETTINGS (server + offline cache)
  // ============================================================

  /// Fetches currency settings from the server, falling back to the cached
  /// store JSON when offline / on any failure. Always returns a normalized map:
  /// `{display_currency, show_both_prices, exchange_rates}`.
  static Future<CurrencySettings> getCurrencySettings() async {
    try {
      final response = await ApiService.authGet('/my-store/currency-settings');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CurrencySettings.fromLegacyMap(_normalizeSettings(data));
      }
    } catch (_) {
      // fall through to cached store
    }

    try {
      final store = await OfflineService.getCachedStore();
      if (store != null) {
        return CurrencySettings.fromLegacyMap(_normalizeSettings({
          'display_currency': store['display_currency'],
          'show_both_prices': store['show_both_prices'],
          'exchange_rates': store['exchange_rates'],
        }));
      }
    } catch (_) {}

    return CurrencySettings.fromLegacyMap(_normalizeSettings(const {}));
  }

  /// Updates settings on the server. The backend recalculates all product
  /// display prices. Returns the normalized, saved settings.
  static Future<CurrencySettings> updateCurrencySettings(
    String? displayCurrency,
    bool showBothPrices,
    List<Map<String, dynamic>> exchangeRates,
  ) async {
    final response = await ApiService.authPut('/my-store/currency-settings', {
      'display_currency': displayCurrency,
      'show_both_prices': showBothPrices,
      'exchange_rates': exchangeRates,
    });
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return CurrencySettings.fromLegacyMap(_normalizeSettings(data));
    }
    throw Exception(
      data['error']?.toString() ?? 'Failed to update currency settings',
    );
  }

  /// Asks the server to refresh any `is_auto` rates from the free FX APIs.
  /// Returns normalized settings plus `updated` (int) and `warnings` (List<String>).
  static Future<Map<String, dynamic>> refreshAutoRates() async {
    final response = await ApiService.authPost(
      '/my-store/currency-settings/refresh-auto',
      const {},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      final normalized = _normalizeSettings(data);
      normalized['updated'] = data['updated'] is num
          ? (data['updated'] as num).toInt()
          : 0;
      normalized['warnings'] = (data['warnings'] is List)
          ? (data['warnings'] as List).map((e) => e.toString()).toList()
          : <String>[];
      return normalized;
    }
    throw Exception(
      data['error']?.toString() ?? 'Failed to refresh automatic rates',
    );
  }

  static Map<String, dynamic> _normalizeSettings(Map<String, dynamic> data) {
    final displayCurrency = data['display_currency']?.toString();
    return {
      'display_currency':
          (displayCurrency != null && displayCurrency.trim().isNotEmpty)
          ? displayCurrency.trim()
          : null,
      'show_both_prices': data['show_both_prices'] == true,
      'exchange_rates': parseRates(data['exchange_rates']),
    };
  }

  /// Coerces a raw exchange-rates value (List, JSON string, or null) into a
  /// list of mutable maps.
  static List<Map<String, dynamic>> parseRates(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    return [];
  }

  // ============================================================
  // CONVERSION (client-side, offline-capable)
  // ============================================================

  /// Converts [originalPrice] from [originalCurrency] to [displayCurrency].
  /// Tries a direct (or inverse) rate first, then a USD bridge.
  /// Returns null when no usable rate exists.
  static double? convertPrice(
    dynamic originalPrice,
    String originalCurrency,
    String displayCurrency,
    dynamic exchangeRates,
  ) {
    final amount = _toDouble(originalPrice);
    if (amount == null) return null;
    final rates = parseRates(exchangeRates);

    final direct = _findDirectRate(rates, originalCurrency, displayCurrency);
    if (direct != null) return amount * direct;

    final fromToUsd = _findDirectRate(rates, originalCurrency, 'USD');
    final usdToTarget = _findDirectRate(rates, 'USD', displayCurrency);
    if (fromToUsd != null && usdToTarget != null) {
      return amount * fromToUsd * usdToTarget;
    }
    return null;
  }

  static double? _findDirectRate(
    List<Map<String, dynamic>> rates,
    String from,
    String to,
  ) {
    final f = from.trim().toLowerCase();
    final t = to.trim().toLowerCase();
    if (f.isEmpty || t.isEmpty) return null;
    if (f == t) return 1;

    for (final r in rates) {
      final rf = (r['from']?.toString() ?? '').trim().toLowerCase();
      final rt = (r['to']?.toString() ?? '').trim().toLowerCase();
      final rate = _toDouble(r['rate']);
      if (rate == null || rate <= 0) continue;
      if (rf == f && rt == t) return rate;
    }
    for (final r in rates) {
      final rf = (r['from']?.toString() ?? '').trim().toLowerCase();
      final rt = (r['to']?.toString() ?? '').trim().toLowerCase();
      final rate = _toDouble(r['rate']);
      if (rate == null || rate <= 0) continue;
      if (rf == t && rt == f) return 1 / rate;
    }
    return null;
  }

  // ============================================================
  // FORMATTING
  // ============================================================

  /// Consistent price formatting: trims trailing ".00" and appends the
  /// currency symbol/code. Handles free-text currencies (e.g. "ل.س").
  static String formatPrice(dynamic price, String currency) {
    final amount = _toDouble(price) ?? 0;
    final symbol = currencySymbol(currency);
    final code = currency.trim().toUpperCase();
    if (code == 'SYP') {
      final hasFraction = (amount - amount.roundToDouble()).abs() > 0.001;
      return '${_formatNumber(amount, maxDecimals: hasFraction ? 1 : 0)} $symbol'
          .trim();
    }
    return '${_formatNumber(amount)} $symbol'.trim();
  }

  static String formatRate(dynamic rate) {
    final amount = _toDouble(rate);
    if (amount == null) return '-';
    if ((amount - amount.roundToDouble()).abs() < 0.0000001) {
      return NumberFormat('#,##0', 'en').format(amount);
    }
    var text = amount.toStringAsFixed(6);
    text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return text;
  }

  static String _formatNumber(double amount, {int? maxDecimals}) {
    if (maxDecimals != null) {
      if (maxDecimals == 0) {
        return NumberFormat('#,##0', 'en').format(amount.round());
      }
      final pattern = '#,##0.${'0' * maxDecimals}';
      return NumberFormat(pattern, 'en').format(amount);
    }
    final isWhole = (amount - amount.roundToDouble()).abs() < 0.001;
    final pattern = isWhole ? '#,##0' : '#,##0.00';
    return NumberFormat(pattern, 'en').format(amount);
  }

  /// Maps common ISO codes to their symbol; falls back to the raw currency
  /// string (so free-text currencies still render correctly).
  static String currencySymbol(String currency) {
    final c = currency.trim();
    if (c.isEmpty) return '';
    const symbols = {
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'TRY': '₺',
      'JPY': '¥',
      'CNY': '¥',
      'RUB': '₽',
      'INR': '₹',
    };
    return symbols[c.toUpperCase()] ?? c;
  }

  // ============================================================
  // PRODUCT DISPLAY RESOLUTION
  // ============================================================

  static bool isOnSale(dynamic product) {
    if (product is! Map) return false;
    final listPrice = _toDouble(product['price']) ?? 0;
    final salePrice = _toDouble(product['sale_price']);
    if (salePrice == null || salePrice <= 0) return false;
    if (product['is_on_sale'] == true) return salePrice < listPrice;
    return salePrice < listPrice;
  }

  static double effectiveProductPrice(dynamic product) {
    if (product is! Map) return 0;
    if (isOnSale(product)) {
      return _toDouble(product['sale_price']) ?? _toDouble(product['price']) ?? 0;
    }
    return _toDouble(product['price']) ?? 0;
  }

  /// Resolves how a product's price should be displayed given the store's
  /// currency settings. Prefers the server-precomputed `display_price` when it
  /// matches the configured display currency; otherwise converts client-side.
  ///
  /// Returns: `{list_price, original_price, original_currency, display_price,
  /// display_currency, show_both, is_on_sale, sale_price}`. `display_price`/
  /// `display_currency` are null when no conversion is possible (callers should
  /// show only the original).
  static Map<String, dynamic> getProductDisplayInfo(
    dynamic product,
    Map<String, dynamic>? currencySettings,
  ) {
    final listPrice = _toDouble(product is Map ? product['price'] : null) ?? 0;
    final onSale = isOnSale(product);
    final salePrice = onSale ? _toDouble((product as Map)['sale_price']) : null;
    final originalPrice = onSale ? (salePrice ?? listPrice) : listPrice;
    final originalCurrency =
        ((product is Map ? product['currency']?.toString() : null) ?? 'SYP')
            .trim();

    final settings = currencySettings ?? const {};
    final showBoth = settings['show_both_prices'] == true;

    // Store-owner display price from the server (same as home / product cards).
    final storeDisplay = _readStoreDisplayPrice(
      product,
      originalPrice,
      originalCurrency,
    );
    final displayCurrency = settings['display_currency']?.toString().trim();
    final rates = parseRates(settings['exchange_rates']);

    if (storeDisplay != null) {
      return _withListDisplayPrice(
        {
          'list_price': listPrice,
          'sale_price': salePrice,
          'is_on_sale': onSale,
          'original_price': originalPrice,
          'original_currency': originalCurrency,
          'display_price': storeDisplay['display_price'],
          'display_currency': storeDisplay['display_currency'],
          'show_both': showBoth,
        },
        listPrice: listPrice,
        originalCurrency: originalCurrency,
        onSale: onSale,
        rates: rates,
      );
    }

    double? displayPrice;
    String? resolvedDisplayCurrency;

    if (displayCurrency != null && displayCurrency.isNotEmpty) {
      if (displayCurrency.toLowerCase() == originalCurrency.toLowerCase()) {
        displayPrice = null;
        resolvedDisplayCurrency = null;
      } else {
        final converted = convertPrice(
          originalPrice,
          originalCurrency,
          displayCurrency,
          rates,
        );
        if (converted != null) {
          displayPrice = converted;
          resolvedDisplayCurrency = displayCurrency;
        }
      }
    }

    return _withListDisplayPrice(
      {
        'list_price': listPrice,
        'sale_price': salePrice,
        'is_on_sale': onSale,
        'original_price': originalPrice,
        'original_currency': originalCurrency,
        'display_price': displayPrice,
        'display_currency': resolvedDisplayCurrency,
        'show_both': showBoth,
      },
      listPrice: listPrice,
      originalCurrency: originalCurrency,
      onSale: onSale,
      rates: rates,
    );
  }

  static Map<String, dynamic> _withListDisplayPrice(
    Map<String, dynamic> info, {
    required double listPrice,
    required String originalCurrency,
    required bool onSale,
    required dynamic rates,
  }) {
    if (!onSale) return info;

    final displayCurrency = info['display_currency']?.toString().trim();
    if (displayCurrency == null || displayCurrency.isEmpty) return info;

    if (displayCurrency.toLowerCase() == originalCurrency.toLowerCase()) {
      return {
        ...info,
        'list_display_price': listPrice,
        'list_display_currency': originalCurrency,
      };
    }

    final converted = convertPrice(
      listPrice,
      originalCurrency,
      displayCurrency,
      rates,
    );
    if (converted == null) return info;

    return {
      ...info,
      'list_display_price': converted,
      'list_display_currency': displayCurrency,
    };
  }

  /// Primary price string for marketplace UI (display price when available).
  static String formatResolvedProductPrice(
    dynamic product, [
    Map<String, dynamic>? currencySettings,
  ]) {
    final info = getProductDisplayInfo(product, currencySettings);
    final displayPrice = info['display_price'];
    final displayCurrency = info['display_currency']?.toString();
    if (displayPrice != null &&
        displayCurrency != null &&
        displayCurrency.isNotEmpty) {
      return formatPrice(displayPrice, displayCurrency);
    }
    return formatPrice(info['original_price'], info['original_currency'] as String);
  }

  static double resolvedProductUnitPrice(
    dynamic product, [
    Map<String, dynamic>? currencySettings,
  ]) {
    final info = getProductDisplayInfo(product, currencySettings);
    final displayPrice = info['display_price'];
    if (displayPrice is num) return displayPrice.toDouble();
    final original = info['original_price'];
    if (original is num) return original.toDouble();
    return effectiveProductPrice(product);
  }

  static String? resolvedProductCurrency(
    dynamic product, [
    Map<String, dynamic>? currencySettings,
  ]) {
    final info = getProductDisplayInfo(product, currencySettings);
    final displayCurrency = info['display_currency']?.toString();
    if (displayCurrency != null && displayCurrency.isNotEmpty) {
      return displayCurrency;
    }
    return info['original_currency']?.toString();
  }

  static Map<String, dynamic>? _readStoreDisplayPrice(
    dynamic product,
    double originalPrice,
    String originalCurrency,
  ) {
    if (product is! Map) return null;
    final serverDisplayPrice = _toDouble(product['display_price']);
    final serverDisplayCurrency =
        product['display_currency']?.toString().trim();
    if (serverDisplayPrice == null ||
        serverDisplayCurrency == null ||
        serverDisplayCurrency.isEmpty) {
      return null;
    }
    final sameAmount = (serverDisplayPrice - originalPrice).abs() < 0.0001;
    final differentCurrency =
        originalCurrency.toLowerCase() != serverDisplayCurrency.toLowerCase();
    if (sameAmount && differentCurrency) return null;
    return {
      'display_price': serverDisplayPrice,
      'display_currency': serverDisplayCurrency,
    };
  }

  /// Returns a product's price normalized to the store's display currency,
  /// for use in sorting and price-range filtering so that products priced in
  /// different currencies are compared on the same basis. Falls back to the
  /// original price when no conversion is possible.
  static double comparablePrice(
    dynamic product,
    Map<String, dynamic>? currencySettings,
  ) {
    return resolvedProductUnitPrice(product, currencySettings);
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }
}
