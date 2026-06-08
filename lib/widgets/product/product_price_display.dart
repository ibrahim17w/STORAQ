import 'package:flutter/material.dart';
import '../../services/currency_service.dart';

/// Primary + optional strikethrough list price for marketplace products.
class ProductPriceDisplay extends StatelessWidget {
  final dynamic product;
  final Map<String, dynamic>? currencySettings;
  final TextStyle? priceStyle;
  final TextStyle? listPriceStyle;
  final CrossAxisAlignment alignment;
  final bool compact;

  const ProductPriceDisplay({
    super.key,
    required this.product,
    this.currencySettings,
    this.priceStyle,
    this.listPriceStyle,
    this.alignment = CrossAxisAlignment.start,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info =
        CurrencyService.getProductDisplayInfo(product, currencySettings);

    final listPrice = info['list_price'];
    final listCurrency = info['original_currency'] as String;
    final originalPrice = info['original_price'];
    final originalCurrency = info['original_currency'] as String;
    final displayPrice = info['display_price'];
    final displayCurrency = info['display_currency'] as String?;
    final showBoth = info['show_both'] == true;
    final onSale = info['is_on_sale'] == true;

    final hasDisplay = displayPrice != null && displayCurrency != null;
    final primaryText = hasDisplay
        ? CurrencyService.formatPrice(displayPrice, displayCurrency)
        : CurrencyService.formatPrice(originalPrice, originalCurrency);

    final defaultPriceStyle = priceStyle ??
        theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: compact ? 13 : 15,
          color: onSale ? theme.colorScheme.error : theme.colorScheme.primary,
        );

    final defaultListStyle = listPriceStyle ??
        theme.textTheme.labelSmall?.copyWith(
          fontSize: compact ? 10 : null,
          color: theme.colorScheme.onSurfaceVariant,
          decoration: TextDecoration.lineThrough,
          decorationColor: theme.colorScheme.onSurfaceVariant,
        );

    if (onSale) {
      final strikePrice = info['list_display_price'] ?? listPrice;
      final strikeCurrency =
          (info['list_display_currency'] ?? listCurrency) as String;
      return Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            CurrencyService.formatPrice(strikePrice, strikeCurrency),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: defaultListStyle,
          ),
          Text(
            primaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: defaultPriceStyle,
          ),
        ],
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          primaryText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: defaultPriceStyle,
        ),
        if (hasDisplay && showBoth)
          Text(
            CurrencyService.formatPrice(originalPrice, originalCurrency),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: compact ? 10 : null,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
