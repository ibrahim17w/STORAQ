import 'package:flutter/material.dart';
import '../cached_image.dart';
import '../product/product_image_viewer.dart';

class StoreListTile extends StatelessWidget {
  final dynamic store;
  final VoidCallback onTap;
  final bool showFavorite;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const StoreListTile({
    super.key,
    required this.store,
    required this.onTap,
    this.showFavorite = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description =
        store['location_description']?.toString() ??
        store['description']?.toString() ??
        '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: compactListCardDecoration(context),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(11),
                ),
                child: CachedAppImage(
                  imageUrl: store['image_url'],
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  memCacheWidth: 180,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store['name'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${store['city'] ?? ''}, ${store['country'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.chevron_right,
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
