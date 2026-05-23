//cached_image.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CachedAppImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final BorderRadius? borderRadius;

  const CachedAppImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _Placeholder(
        width: width,
        height: height,
        borderRadius: borderRadius,
      );
    }

    final img = CachedNetworkImage(
      imageUrl: imageUrl!,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      placeholder: (context, url) => _Placeholder(
        width: width,
        height: height,
        borderRadius: borderRadius,
        isLoading: true,
      ),
      errorWidget: (context, url, error) => _Placeholder(
        width: width,
        height: height,
        borderRadius: borderRadius,
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return img;
  }
}

class _Placeholder extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final bool isLoading;

  const _Placeholder({
    this.width,
    this.height,
    this.borderRadius,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final widget = Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.image_not_supported, color: Colors.grey.shade400),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: widget);
    }
    return widget;
  }
}
