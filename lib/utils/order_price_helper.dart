import '../services/currency_service.dart';

/// Shared checkout/receipt price resolution so display currency amounts stay
/// consistent from cart → order → receipt.
class OrderPriceHelper {
  static double parse(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  static Map<String, dynamic> normalizeItem(dynamic item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return Map<String, dynamic>.from(item);
    return {};
  }

  /// Original-currency line total (unit × qty, or stored total_price).
  static double lineTotalBase(Map<String, dynamic> item) {
    final total = parse(item['total_price']);
    if (total > 0) return total;
    final unit = parse(item['price'] ?? item['unit_price']);
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
    return unit * qty;
  }

  /// Line total in [targetCurrency], preferring per-item display prices saved
  /// at checkout, then converting from the item's original currency.
  static double lineTotalInCurrency(
    Map<String, dynamic> item, {
    required String? targetCurrency,
    dynamic exchangeRates,
    String fallbackCurrency = 'SYP',
  }) {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
    final displayUnit = parse(item['display_price']);
    final displayCurrency = item['display_currency']?.toString().trim();

    if (targetCurrency != null &&
        targetCurrency.isNotEmpty &&
        displayUnit > 0 &&
        displayCurrency != null &&
        displayCurrency.toLowerCase() == targetCurrency.toLowerCase()) {
      return displayUnit * qty;
    }

    final base = lineTotalBase(item);
    final fromCurrency =
        item['currency']?.toString().trim().isNotEmpty == true
            ? item['currency']!.toString().trim()
            : fallbackCurrency;

    if (targetCurrency == null || targetCurrency.isEmpty) {
      return base;
    }
    if (fromCurrency.toLowerCase() == targetCurrency.toLowerCase()) {
      return base;
    }

    final converted = CurrencyService.convertPrice(
      base,
      fromCurrency,
      targetCurrency,
      exchangeRates,
    );
    return converted ?? base;
  }

  static String formatAmount(double amount, String currency) {
    return CurrencyService.formatPrice(amount, currency);
  }
}
