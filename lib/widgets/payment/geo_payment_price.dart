import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/viewer_location_provider.dart';
import '../../services/currency_service.dart';
import '../../utils/payment_price_helper.dart';

/// Platform payment amount in one currency based on viewer geo (e.g. SYP in Syria, USD in USA).
class GeoPaymentPrice extends ConsumerWidget {
  final double? usdAmount;
  final Map<String, dynamic>? paymentPrices;
  final Map<String, dynamic>? paymentRates;
  final TextStyle? style;
  final String? label;

  const GeoPaymentPrice({
    super.key,
    required this.usdAmount,
    this.paymentPrices,
    this.paymentRates,
    this.style,
    this.label,
  });

  double? _resolveAmount(String currency) {
    final amounts = paymentPrices != null && paymentPrices!.isNotEmpty
        ? paymentPrices!
        : PaymentPriceHelper.paymentPricesForUsd(usdAmount, paymentRates);

    final raw = amounts[currency];
    if (raw is num) return raw.toDouble();
    if (raw != null) return double.tryParse(raw.toString());

    if (currency == 'USD') return usdAmount;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = ref.watch(viewerLocationProvider).paymentCurrency;
    final amount = _resolveAmount(currency);

    final textStyle = style ??
        theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);

    if (amount == null) {
      return Text('-', style: textStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Text(
            label!,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (label != null) const SizedBox(height: 4),
        Text(
          CurrencyService.formatPrice(amount, currency),
          style: textStyle,
        ),
      ],
    );
  }
}
