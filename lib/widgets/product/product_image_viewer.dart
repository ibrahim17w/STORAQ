import 'package:flutter/material.dart';
import '../cached_image.dart';

/// Swipeable product gallery with thumbnails and fullscreen zoom.
enum ProductImageDisplayStyle {
  /// Full-width banner crop — good for wide hero shots.
  banner,
  /// Framed square with contain — best for product photos of any aspect ratio.
  product,
  /// Swipeable stacked cards with peeking neighbors (product detail hero).
  cardCarousel,
}

class ProductImageViewer extends StatefulWidget {
  final List<String> images;
  final double height;
  final BorderRadius borderRadius;
  final ProductImageDisplayStyle displayStyle;

  const ProductImageViewer({
    super.key,
    required this.images,
    this.height = 340,
    this.borderRadius = BorderRadius.zero,
    this.displayStyle = ProductImageDisplayStyle.banner,
  });

  static void openGallery(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _FullscreenImageGallery(
        images: images,
        initialIndex: initialIndex.clamp(0, images.length - 1),
      ),
    );
  }

  @override
  State<ProductImageViewer> createState() => _ProductImageViewerState();
}

class _ProductImageViewerState extends State<ProductImageViewer> {
  int _index = 0;
  late final PageController _pageController;

  List<String> get _images =>
      widget.images.where((path) => path.trim().isNotEmpty).toList();

  bool get _isCardCarousel =>
      widget.displayStyle == ProductImageDisplayStyle.cardCarousel;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: _isCardCarousel ? 0.86 : 1.0,
    );
  }

  @override
  void didUpdateWidget(ProductImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images != widget.images) {
      _index = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectIndex(int next) {
    if (next == _index) return;
    setState(() => _index = next);
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final theme = Theme.of(context);

    if (images.isEmpty) {
      return Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: widget.borderRadius,
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final safeIndex = _index.clamp(0, images.length - 1);
    final hasMultiple = images.length > 1;
    final isProductStyle =
        widget.displayStyle == ProductImageDisplayStyle.product;
    final isCardCarousel = _isCardCarousel;
    final imageFit = (isProductStyle || isCardCarousel)
        ? BoxFit.contain
        : BoxFit.cover;
    final frameRadius = isCardCarousel
        ? BorderRadius.circular(18)
        : isProductStyle
            ? BorderRadius.circular(20)
            : widget.borderRadius;

    if (isCardCarousel) {
      return _buildCardCarousel(
        context,
        theme: theme,
        images: images,
        safeIndex: safeIndex,
        hasMultiple: hasMultiple,
        frameRadius: frameRadius,
      );
    }

    Widget buildMainImage(String url, {required double h, required int index}) {
      return GestureDetector(
        onTap: () => ProductImageViewer.openGallery(
          context,
          images: images,
          initialIndex: index,
        ),
        child: CachedAppImage(
          imageUrl: url,
          width: double.infinity,
          height: h,
          fit: imageFit,
          memCacheWidth: isProductStyle ? 1200 : 900,
          borderRadius: frameRadius,
        ),
      );
    }

    final gallery = SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isProductStyle)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: frameRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.surfaceContainerHighest,
                    theme.colorScheme.surfaceContainerLow,
                  ],
                ),
              ),
            ),
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              return Padding(
                padding: EdgeInsets.all(isProductStyle ? 20 : 0),
                child: buildMainImage(images[i], h: widget.height, index: i),
              );
            },
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => ProductImageViewer.openGallery(
                  context,
                  images: images,
                  initialIndex: safeIndex,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.zoom_out_map_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (hasMultiple)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (i) {
                  final active = i == safeIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isProductStyle)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: gallery,
          )
        else
          gallery,
        if (hasMultiple)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.35),
                ),
              ),
            ),
            child: SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final selected = i == safeIndex;
                  return GestureDetector(
                    onTap: () => _selectIndex(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.dividerColor.withValues(alpha: 0.6),
                          width: selected ? 2.5 : 1,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedAppImage(
                          imageUrl: images[i],
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          memCacheWidth: 140,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCardCarousel(
    BuildContext context, {
    required ThemeData theme,
    required List<String> images,
    required int safeIndex,
    required bool hasMultiple,
    required BorderRadius frameRadius,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final plateColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFECECEF);
    final cardColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final borderColor = theme.dividerColor.withValues(alpha: isDark ? 0.45 : 0.3);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: plateColor,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: borderColor),
                ),
              ),
            ),
          ),
          PageView.builder(
            controller: _pageController,
            padEnds: true,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  var page = _index.toDouble();
                  if (_pageController.hasClients &&
                      _pageController.position.haveDimensions) {
                    page = _pageController.page ?? page;
                  }
                  final delta = (page - i).abs();
                  final scale = (1 - delta * 0.07).clamp(0.9, 1.0);
                  final opacity = (1 - delta * 0.4).clamp(0.55, 1.0);
                  return Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: opacity, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 20),
                  child: GestureDetector(
                    onTap: () => ProductImageViewer.openGallery(
                      context,
                      images: images,
                      initialIndex: i,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: frameRadius,
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: frameRadius,
                        child: CachedAppImage(
                          imageUrl: images[i],
                          width: double.infinity,
                          height: widget.height - 40,
                          fit: BoxFit.contain,
                          memCacheWidth: 1200,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 14,
            right: 20,
            child: Material(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => ProductImageViewer.openGallery(
                  context,
                  images: images,
                  initialIndex: safeIndex,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.zoom_out_map_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (hasMultiple)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (i) {
                  final active = i == safeIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullscreenImageGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullscreenImageGallery({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullscreenImageGallery> createState() =>
      _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<_FullscreenImageGallery> {
  late final PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int delta) {
    final next = (_current + delta).clamp(0, widget.images.length - 1);
    if (next == _current) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final hasMultiple = images.length > 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                return InteractiveViewer(
                  minScale: 0.9,
                  maxScale: 3,
                  child: Center(
                    child: CachedAppImage(
                      imageUrl: images[i],
                      fit: BoxFit.contain,
                      memCacheWidth: 1200,
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.45),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (hasMultiple)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_current + 1} / ${images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            if (hasMultiple && _current > 0)
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.45),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.chevron_left, size: 32),
                    onPressed: () => _goTo(-1),
                  ),
                ),
              ),
            if (hasMultiple && _current < images.length - 1)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.45),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.chevron_right, size: 32),
                    onPressed: () => _goTo(1),
                  ),
                ),
              ),
            if (hasMultiple)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final selected = i == _current;
                      return GestureDetector(
                        onTap: () {
                          _pageController.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.35),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: CachedAppImage(
                              imageUrl: images[i],
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              memCacheWidth: 120,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Edgeless card shell — soft shadow on light mode, raised surface on dark.
BoxDecoration compactListCardDecoration(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: isDark ? theme.colorScheme.surfaceContainerLow : Colors.white,
    borderRadius: BorderRadius.circular(14),
    boxShadow: isDark
        ? null
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
  );
}

Widget stockBadge(BuildContext context, int quantity, {String? label}) {
  final inStock = quantity > 0;
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: inStock
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : theme.colorScheme.errorContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          inStock ? Icons.check_circle_outline : Icons.cancel_outlined,
          size: 14,
          color: inStock ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        const SizedBox(width: 4),
        Text(
          label ?? '$quantity',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: inStock
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
        ),
      ],
    ),
  );
}
