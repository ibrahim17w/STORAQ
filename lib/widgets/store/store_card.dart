// lib/widgets/store/store_card.dart
import 'package:flutter/material.dart';
import '../cached_image.dart';

class StoreCard extends StatelessWidget {
  final dynamic store;
  final VoidCallback onTap;
  final double? distanceKm;
  final bool isSponsored;
  final bool isCompact;
  final double? width;
  final String? sponsoredLabel;

  const StoreCard({
    super.key,
    required this.store,
    required this.onTap,
    this.distanceKm,
    this.isSponsored = false,
    this.isCompact = false,
    this.width = 160,
    this.sponsoredLabel,
  });

  /// Keep only the first 2 parts of a long geocoding string
  String _shortLocation(dynamic store) {
    final city = store['city']?.toString() ?? '';
    final country = store['country']?.toString() ?? '';
    if (city.isEmpty && country.isEmpty) return '';

    // If city is a long comma-separated address, take first 2 chunks
    final parts = city
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final shortCity = parts.length > 2 ? '${parts[0]}, ${parts[1]}' : city;

    if (shortCity.isNotEmpty && country.isNotEmpty)
      return '$shortCity, $country';
    return shortCity.isNotEmpty ? shortCity : country;
  }

  @override
  Widget build(BuildContext context) {
    final description =
        store['location_description']?.toString() ??
        store['description']?.toString() ??
        '';

    // FIX: default image reduced from 120 → 90 to fit 140px parent
    final imageHeight = isCompact ? 90 : (isSponsored ? 80 : 90);
    final padding = isCompact
        ? const EdgeInsets.fromLTRB(8, 6, 8, 4)
        : const EdgeInsets.fromLTRB(10, 6, 10, 4); // tighter vertical padding

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: isSponsored ? const EdgeInsets.symmetric(horizontal: 4) : null,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: CachedAppImage(
                imageUrl: store['image_url'],
                height: imageHeight.toDouble(),
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: isCompact ? 300 : 400,
              ),
            ),
            Padding(
              padding: padding,
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
                  const SizedBox(height: 2), // was 3
                  Text(
                    _shortLocation(store),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isCompact ? 9 : 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  if (description.isNotEmpty && !isSponsored) ...[
                    const SizedBox(height: 2), // was 3
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isCompact ? 8 : 9,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  if (isSponsored) ...[
                    const SizedBox(height: 3), // was 4
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sponsoredLabel ?? 'TOP',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                  if (distanceKm != null && distanceKm != double.infinity) ...[
                    const SizedBox(height: 3), // was 4
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 10,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${distanceKm!.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
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
    );
  }
}
