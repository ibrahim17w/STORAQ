import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Universal image widget that handles:
/// - file:// prefixed local paths (offline cached images)
/// - Raw absolute paths (Windows: C:\..., Linux: /home/...)
/// - HTTP/HTTPS remote URLs
/// - Null/empty URLs (placeholder)
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

  static bool isLocalPath(String? url) {
    if (url == null || url.isEmpty) return false;
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return false;
    }
    if (trimmed.startsWith('file://')) return true;
    // Windows drive letter: C:\ or C:/
    if (trimmed.length > 2 && trimmed[1] == ':') return true;
    // Unix/Android absolute paths — but not web-style /uploads/ paths
    if (trimmed.startsWith('/') &&
        !trimmed.startsWith('/uploads/') &&
        !trimmed.startsWith('/api/')) {
      return true;
    }
    return false;
  }

  static String toLocalFilePath(String url) {
    var path = url.trim();
    while (path.startsWith('file://')) {
      path = path.substring(7);
    }
    return path.replaceAll('/', Platform.pathSeparator);
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder(context, Icons.image_not_supported);
    }

    if (isLocalPath(imageUrl)) {
      final file = File(toLocalFilePath(imageUrl!));
      final image = Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: memCacheWidth,
        errorBuilder: (_, __, ___) =>
            errorWidget ?? _buildPlaceholder(context, Icons.broken_image),
      );
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: image);
      }
      return image;
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
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        size: _placeholderIconSize(width, height),
      ),
    );
  }

  static double _placeholderIconSize(double? w, double? h) {
    if (w != null &&
        h != null &&
        w.isFinite &&
        h.isFinite &&
        w > 0 &&
        h > 0) {
      final minDim = w < h ? w : h;
      return (minDim * 0.3).clamp(16.0, 48.0);
    }
    return 32;
  }
}
