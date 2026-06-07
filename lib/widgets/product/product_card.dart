import 'package:flutter/material.dart';
import '../cached_image.dart';
import '../../services/offline_service.dart';
import '../../services/currency_service.dart';
import 'product_image_viewer.dart';

class ProductCard extends StatelessWidget {
  final dynamic product;
  final VoidCallback onTap;
  final bool isTrending;
  final bool isSponsored;
  final double? width;
  final bool showFavorite;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final String? trendingLabel;
  final String? sponsoredLabel;
  final Map<String, dynamic>? currencySettings;
  /// Tighter layout for fixed-height horizontal carousels on the home screen.
  final bool compact;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.isTrending = false,
    this.isSponsored = false,
    this.width = 164,
    this.showFavorite = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
    this.trendingLabel,
    this.sponsoredLabel,
    this.currencySettings,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productImages = OfflineService.getProductImagePaths(product);
    final info =
        CurrencyService.getProductDisplayInfo(product, currencySettings);

    final originalPrice = info['original_price'];
    final originalCurrency = info['original_currency'] as String;
    final displayPrice = info['display_price'];
    final displayCurrency = info['display_currency'] as String?;
    final showBoth = info['show_both'] == true;

    final hasDisplay = displayPrice != null && displayCurrency != null;
    final primaryText = hasDisplay
        ? CurrencyService.formatPrice(displayPrice, displayCurrency)
        : CurrencyService.formatPrice(originalPrice, originalCurrency);
    final showSecondary = hasDisplay && showBoth;
    final shopName = (product['shop_name'] ?? '').toString().trim();

    final cardWidth = width ?? 164;
    final imageSection = Stack(
      fit: StackFit.expand,
      children: [
                          ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            child: CachedAppImage(
                              imageUrl: productImages.isNotEmpty
                                  ? productImages.first
                                  : null,
                              fit: BoxFit.cover,
                              memCacheWidth: 400,
                            ),
                          ),
                          if (isTrending)
                            PositionedDirectional(
                              top: 8,
                              start: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  trendingLabel ?? 'HOT',
                                  style: TextStyle(
                                    color: theme.colorScheme.onError,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          if (isSponsored)
                            PositionedDirectional(
                              top: 8,
                              start: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  sponsoredLabel ?? 'SPONSORED',
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          if (showFavorite)
                            PositionedDirectional(
                              top: 8,
                              end: 8,
                              child: _CircleIconButton(
                                icon: isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                iconColor:
                                    isFavorite ? Colors.red : Colors.white,
                                onTap: onFavoriteToggle,
                              ),
                            ),
                          if (productImages.length > 1)
                            PositionedDirectional(
                              end: 8,
                              bottom: 8,
                              child: GestureDetector(
                                onTap: () => ProductImageViewer.openGallery(
                                  context,
                                  images: productImages,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.photo_library_outlined,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${productImages.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
      ],
    );

    final textSection = Padding(
      padding: EdgeInsets.fromLTRB(
        10,
        compact ? 6 : 10,
        10,
        compact ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            compact ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Text(
            product['name'] ?? '',
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.15,
              color: theme.colorScheme.onSurface,
            ),
          ),
          SizedBox(height: compact ? 3 : 6),
          Text(
            primaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 13 : 15,
              color: theme.colorScheme.primary,
            ),
          ),
          if (showSecondary)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                CurrencyService.formatPrice(
                  originalPrice,
                  originalCurrency,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: compact ? 10 : null,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (!compact && shopName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    final cardBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: cardWidth,
          width: cardWidth,
          child: imageSection,
        ),
        if (compact) Expanded(child: textSection) else textSection,
      ],
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: SizedBox(
        width: cardWidth,
        height: compact ? 252 : null,
        child: DecoratedBox(
          decoration: compactListCardDecoration(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.surfaceContainerLow
                  : Colors.white,
              child: InkWell(
                onTap: onTap,
                child: cardBody,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  const _CircleIconButton({
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}
