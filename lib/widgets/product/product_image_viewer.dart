import 'package:flutter/material.dart';
import '../cached_image.dart';

/// Swipeable product gallery with thumbnails and fullscreen zoom.
class ProductImageViewer extends StatefulWidget {
  final List<String> images;
  final double height;
  final BorderRadius borderRadius;

  const ProductImageViewer({
    super.key,
    required this.images,
    this.height = 340,
    this.borderRadius = BorderRadius.zero,
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  return GestureDetector(
                    onTap: () => ProductImageViewer.openGallery(
                      context,
                      images: images,
                      initialIndex: i,
                    ),
                    child: CachedAppImage(
                      imageUrl: images[i],
                      width: double.infinity,
                      height: widget.height,
                      fit: BoxFit.cover,
                      memCacheWidth: 900,
                      borderRadius: widget.borderRadius,
                    ),
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
        ),
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
