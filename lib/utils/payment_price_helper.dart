import '../services/currency_service.dart';

class PaymentPriceHelper {
  static double? tierUsdPrice(Map<String, dynamic> tier) {
    final raw = tier['price_usd_monthly'] ?? tier['priceUsdMonthly'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  static Map<String, dynamic> paymentPricesForTier(Map<String, dynamic> tier) {
    final fromTier = tier['payment_prices'];
    if (fromTier is Map) {
      return Map<String, dynamic>.from(fromTier);
    }
    return {};
  }

  static Map<String, dynamic> paymentPricesForUsd(
    double? usd,
    Map<String, dynamic>? paymentRates,
  ) {
    if (usd == null || paymentRates == null) return {};
    final rates = paymentRates['rates'];
    if (rates is! Map) return {};
    final amounts = <String, dynamic>{};
    rates.forEach((cur, rate) {
      final r = _toDouble(rate);
      if (r == null) return;
      final converted = usd * r;
      amounts[cur.toString()] =
          cur.toString().toUpperCase() == 'SYP'
              ? converted.round()
              : _round(converted);
    });
    return amounts;
  }

  static List<String> orderedCurrencies(
    Map<String, dynamic> amounts, {
    List<String>? preferredOrder,
  }) {
    const defaultOrder = [
      'USD', 'SYP', 'EUR', 'GBP', 'TRY', 'SAR', 'AED', 'JOD', 'QAR', 'CAD', 'CHF',
    ];
    final order = preferredOrder ?? defaultOrder;
    final keys = amounts.keys.map((k) => k.toString().toUpperCase()).toSet();
    final sorted = <String>[];
    for (final c in order) {
      if (keys.contains(c)) sorted.add(c);
    }
    for (final c in keys) {
      if (!sorted.contains(c)) sorted.add(c);
    }
    return sorted;
  }

  static String formatRate(dynamic rate) {
    final n = _toDouble(rate);
    if (n == null) return '-';
    if (n == n.roundToDouble()) return n.toStringAsFixed(0);
    final s = n.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return s.isEmpty ? n.toString() : s;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  static double _round(double v) => (v * 1000000).round() / 1000000;
}
