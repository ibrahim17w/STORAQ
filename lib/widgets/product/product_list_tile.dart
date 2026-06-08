import 'package:flutter/material.dart';
import '../cached_image.dart';
import '../../services/offline_service.dart';
import '../../services/currency_service.dart';
import '../../utils/location_helper.dart';
import 'product_image_viewer.dart';
import 'product_price_display.dart';
import 'product_sale_ribbon.dart';
import '../../lang/translations.dart';

class ProductListTile extends StatelessWidget {
  final dynamic product;
  final VoidCallback onTap;
  final double? distanceKm;
  final bool showFavorite;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final Map<String, dynamic>? currencySettings;
  final bool compact;
  final VoidCallback? onImageTap;

  const ProductListTile({
    super.key,
    required this.product,
    required this.onTap,
    this.distanceKm,
    this.showFavorite = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
    this.currencySettings,
    this.compact = false,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productImages = OfflineService.getProductImagePaths(product);
    final onSale = CurrencyService.isOnSale(product);
    final imageSize = compact ? 72.0 : 88.0;
    final qty = (product['quantity'] as num?)?.toInt() ?? 0;
    final extraImages = productImages.length > 1 ? productImages.length - 1 : 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: compactListCardDecoration(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onImageTap ??
                    (productImages.isNotEmpty
                        ? () => ProductImageViewer.openGallery(
                              context,
                              images: productImages,
                            )
                        : null),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(11),
                      ),
                      child: CachedAppImage(
                        imageUrl: productImages.isNotEmpty
                            ? productImages.first
                            : null,
                        width: imageSize,
                        height: imageSize,
                        fit: BoxFit.cover,
                        memCacheWidth: 240,
                      ),
                    ),
                    if (extraImages > 0)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+$extraImages',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (onSale)
                      ProductSaleRibbon(label: t('on_sale'), size: 40),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 12,
                    compact ? 8 : 10,
                    compact ? 8 : 10,
                    compact ? 8 : 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: compact ? 13 : 14,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ProductPriceDisplay(
                        product: product,
                        currencySettings: currencySettings,
                        compact: compact,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if ((product['shop_name'] ?? '').toString().isNotEmpty)
                            Expanded(
                              child: Text(
                                product['shop_name'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (distanceKm != null &&
                              distanceKm != double.infinity) ...[
                            Icon(
                              Icons.near_me_outlined,
                              size: 12,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              LocationHelper.formatDistanceKm(distanceKm!),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                          if (qty >= 0) ...[
                            const SizedBox(width: 8),
                            stockBadge(context, qty),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (showFavorite)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: isFavorite ? Colors.red : theme.colorScheme.outline,
                  ),
                  onPressed: onFavoriteToggle,
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 28, right: 6),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
