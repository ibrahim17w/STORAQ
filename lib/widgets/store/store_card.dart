//lib/widgets/store/store_card.dart
import 'package:flutter/material.dart';
import '../cached_image.dart';
import '../product/product_image_viewer.dart';
import '../../utils/location_helper.dart';

class StoreCard extends StatelessWidget {
  final dynamic store;
  final VoidCallback onTap;
  final double? distanceKm;
  final bool isSponsored;
  final bool isCompact;
  final double? width;
  final String? sponsoredLabel;
  final bool showFavorite;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const StoreCard({
    super.key,
    required this.store,
    required this.onTap,
    this.distanceKm,
    this.isSponsored = false,
    this.isCompact = false,
    this.width = 148,
    this.sponsoredLabel,
    this.showFavorite = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  String _shortLocation(dynamic store) {
    final city = store['city']?.toString() ?? '';
    final country = store['country']?.toString() ?? '';
    if (city.isEmpty && country.isEmpty) return '';

    final parts = city
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final shortCity = parts.length > 2 ? '${parts[0]}, ${parts[1]}' : city;

    if (shortCity.isNotEmpty && country.isNotEmpty) {
      return '$shortCity, $country';
    }
    return shortCity.isNotEmpty ? shortCity : country;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description =
        store['location_description']?.toString() ??
        store['description']?.toString() ??
        '';
    final imageHeight = isCompact ? 82.0 : 90.0;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Container(
        width: width,
        decoration: compactListCardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: Stack(
                    children: [
                      CachedAppImage(
                        imageUrl: store['image_url'],
                        height: imageHeight,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        memCacheWidth: isCompact ? 280 : 360,
                      ),
                      if (showFavorite)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: onFavoriteToggle,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 16,
                                  color: isFavorite ? Colors.red : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        store['name'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: isCompact ? 11 : 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _shortLocation(store),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isCompact ? 9 : 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (description.isNotEmpty && !isSponsored) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact ? 8 : 9,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (isSponsored) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: theme.colorScheme.tertiary.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            sponsoredLabel ?? 'TOP',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                      if (distanceKm != null &&
                          distanceKm != double.infinity) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.near_me_outlined,
                              size: 10,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              LocationHelper.formatDistanceKm(distanceKm!),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
