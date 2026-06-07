import 'package:flutter/material.dart';
import '../../services/currency_service.dart';
import '../../utils/payment_price_helper.dart';

class MultiCurrencyPrice extends StatelessWidget {
  final double? usdAmount;
  final Map<String, dynamic>? paymentPrices;
  final Map<String, dynamic>? paymentRates;
  final TextStyle? primaryStyle;
  final TextStyle? secondaryStyle;
  final bool compact;
  final String? label;

  const MultiCurrencyPrice({
    super.key,
    required this.usdAmount,
    this.paymentPrices,
    this.paymentRates,
    this.primaryStyle,
    this.secondaryStyle,
    this.compact = false,
    this.label,
  });

  Map<String, dynamic> get _amounts {
    if (paymentPrices != null && paymentPrices!.isNotEmpty) {
      return paymentPrices!;
    }
    return PaymentPriceHelper.paymentPricesForUsd(usdAmount, paymentRates);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amounts = _amounts;
    final usd = usdAmount;

    if (usd == null && amounts.isEmpty) {
      return Text('-', style: primaryStyle ?? theme.textTheme.titleMedium);
    }

    final currencies = PaymentPriceHelper.orderedCurrencies(amounts);
    final primary = primaryStyle ??
        theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);
    final secondary = secondaryStyle ??
        TextStyle(fontSize: compact ? 12 : 13, color: theme.colorScheme.onSurfaceVariant);

    final usdText = usd != null
        ? CurrencyService.formatPrice(usd, 'USD')
        : (amounts['USD'] != null
            ? CurrencyService.formatPrice(amounts['USD'], 'USD')
            : null);

    if (compact) {
      final others = currencies
          .where((c) => c != 'USD')
          .map((c) => CurrencyService.formatPrice(amounts[c], c))
          .join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) Text(label!, style: secondary),
          if (usdText != null) Text(usdText, style: primary),
          if (others.isNotEmpty) Text(others, style: secondary),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: secondary),
          const SizedBox(height: 4),
        ],
        if (usdText != null) Text(usdText, style: primary),
        const SizedBox(height: 6),
        ...currencies.where((c) => c != 'USD').map((c) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              CurrencyService.formatPrice(amounts[c], c),
              style: secondary,
            ),
          );
        }),
      ],
    );
  }
}
