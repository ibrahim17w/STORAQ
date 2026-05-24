// lib/widgets/product_image_gallery.dart
// FIXED: Unique keys, no double setState, max image enforcement, proper image picker

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../lang/translations.dart';

class ProductImageGallery extends StatefulWidget {
  final List<String> existingUrls;
  final List<File> newFiles;
  final ValueChanged<List<File>> onNewFilesChanged;
  final ValueChanged<List<String>> onExistingRemoved;
  final bool readOnly;
  final int? maxImages; // null = unlimited

  const ProductImageGallery({
    super.key,
    this.existingUrls = const [],
    this.newFiles = const [],
    required this.onNewFilesChanged,
    required this.onExistingRemoved,
    this.readOnly = false,
    this.maxImages,
  });

  @override
  State<ProductImageGallery> createState() => _ProductImageGalleryState();
}

class _ProductImageGalleryState extends State<ProductImageGallery> {
  late List<String> _urls;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _urls = List.from(widget.existingUrls);
  }

  @override
  void didUpdateWidget(covariant ProductImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update local URLs from parent if they actually changed
    if (_urls.length != widget.existingUrls.length ||
        !_urls.every((url) => widget.existingUrls.contains(url))) {
      _urls = List.from(widget.existingUrls);
    }
  }

  int get _totalImages => _urls.length + widget.newFiles.length;
  int get _remainingSlots {
    if (widget.maxImages == null) return 999;
    return (widget.maxImages! - _totalImages).clamp(0, 999);
  }

  bool get _canAddMore =>
      widget.maxImages == null || _totalImages < widget.maxImages!;

  Future<void> _pickImage() async {
    if (!_canAddMore) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum ${widget.maxImages} images allowed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('select_image_source')),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            icon: const Icon(Icons.camera_alt),
            label: Text(t('camera')),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: Text(t('gallery')),
          ),
        ],
      ),
    );

    if (source == null) return;

    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (picked != null) {
        final newFile = File(picked.path);
        // Only notify parent — DO NOT call setState here for newFiles
        // The parent controls newFiles via its own state
        final updated = [...widget.newFiles, newFile];
        widget.onNewFilesChanged(updated);
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  void _removeFile(int index) {
    // index is within newFiles range
    final updated = List<File>.from(widget.newFiles);
    updated.removeAt(index);
    widget.onNewFilesChanged(updated);
  }

  void _removeUrl(int index) {
    final removed = _urls[index];
    setState(() => _urls.removeAt(index));
    widget.onExistingRemoved([removed]);
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;

    final total = _urls.length + widget.newFiles.length;
    if (oldIndex < 0 || oldIndex >= total || newIndex < 0 || newIndex >= total)
      return;

    // Reordering URLs
    if (oldIndex < _urls.length && newIndex < _urls.length) {
      setState(() {
        final item = _urls.removeAt(oldIndex);
        _urls.insert(newIndex, item);
      });
      widget.onExistingRemoved([]); // trigger parent sync if needed
      return;
    }

    // Reordering Files
    final fileOldIndex = oldIndex - _urls.length;
    final fileNewIndex = newIndex - _urls.length;
    if (fileOldIndex >= 0 &&
        fileOldIndex < widget.newFiles.length &&
        fileNewIndex >= 0 &&
        fileNewIndex < widget.newFiles.length) {
      final updated = List<File>.from(widget.newFiles);
      final item = updated.removeAt(fileOldIndex);
      updated.insert(fileNewIndex, item);
      widget.onNewFilesChanged(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _totalImages;
    final max = widget.maxImages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (max != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  '$total / $max',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: total >= max
                        ? Colors.orange
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                if (total >= max)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Limit reached',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(
          height: 110,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: total + (widget.readOnly || !_canAddMore ? 0 : 1),
            onReorder: _reorder,
            proxyDecorator: (child, index, animation) => AnimatedBuilder(
              animation: animation,
              builder: (_, c) => Transform.scale(scale: 1.05, child: c),
              child: child,
            ),
            itemBuilder: (_, index) {
              // Add button
              if (!widget.readOnly && _canAddMore && index == total) {
                return Padding(
                  key: const ValueKey('__add_button__'),
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('add'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final isUrl = index < _urls.length;
              final url = isUrl ? _urls[index] : null;
              final fileIndex = index - _urls.length;
              final file = !isUrl && fileIndex < widget.newFiles.length
                  ? widget.newFiles[fileIndex]
                  : null;

              // FIXED: Use proper unique keys with actual index values
              final itemKey = isUrl
                  ? ValueKey('url_${url}_$index')
                  : ValueKey('file_${file?.path}_$index');

              return Padding(
                key: itemKey,
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 100,
                        height: 100,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: isUrl
                            ? Image.network(
                                url!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image),
                              )
                            : (file != null
                                  ? Image.file(file, fit: BoxFit.cover)
                                  : const Icon(Icons.broken_image)),
                      ),
                    ),
                    if (!widget.readOnly)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => isUrl
                              ? _removeUrl(index)
                              : _removeFile(fileIndex),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (index == 0)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t('main_image'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (!widget.readOnly)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t('drag_to_reorder'),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
