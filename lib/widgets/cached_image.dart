// lib/widgets/cached_image.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CachedAppImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedAppImage({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Handle local file paths (offline pending images)
    if (imageUrl != null &&
        (imageUrl!.startsWith('file:') || imageUrl!.startsWith('/'))) {
      // Try to show a local file icon since we can't easily display local files in web/desktop
      // without additional dependencies
      return _buildPlaceholder(context, Icons.image);
    }

    // Handle empty/null URL
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder(context, Icons.image_not_supported);
    }

    final image = CachedNetworkImage(
      imageUrl: imageUrl!,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      placeholder: (context, url) =>
          placeholder ?? _buildPlaceholder(context, Icons.image),
      errorWidget: (context, url, error) =>
          errorWidget ?? _buildPlaceholder(context, Icons.broken_image),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _buildPlaceholder(BuildContext context, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        icon,
        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
        size: (width != null && height != null)
            ? (width! < height! ? width! : height!) * 0.3
            : 32,
      ),
    );
  }
}
