// lib/widgets/product_image_gallery.dart
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
  final int maxImages;

  const ProductImageGallery({
    super.key,
    this.existingUrls = const [],
    this.newFiles = const [],
    required this.onNewFilesChanged,
    required this.onExistingRemoved,
    this.readOnly = false,
    this.maxImages = 4,
  });

  @override
  State<ProductImageGallery> createState() => _ProductImageGalleryState();
}

class _ProductImageGalleryState extends State<ProductImageGallery> {
  late List<File> _files;
  late List<String> _urls;

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.newFiles);
    _urls = List.from(widget.existingUrls);
  }

  int get _total => _urls.length + _files.length;
  bool get _atLimit => _total >= widget.maxImages;

  Future<void> _pickImage() async {
    if (_atLimit) return;

    final picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('select_image_source')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: Text(t('camera')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: Text(t('gallery')),
          ),
        ],
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked != null) {
      final newFiles = [..._files, File(picked.path)];
      setState(() => _files = newFiles);
      widget.onNewFilesChanged(_files);
    }
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
    widget.onNewFilesChanged(_files);
  }

  void _removeUrl(int index) {
    final removed = _urls[index];
    setState(() => _urls.removeAt(index));
    widget.onExistingRemoved([removed]);
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      if (oldIndex < _urls.length && newIndex < _urls.length) {
        final item = _urls.removeAt(oldIndex);
        _urls.insert(newIndex, item);
      } else if (oldIndex >= _urls.length && newIndex >= _urls.length) {
        final fOld = oldIndex - _urls.length;
        final fNew = newIndex - _urls.length;
        final item = _files.removeAt(fOld);
        _files.insert(fNew, item);
      }
    });
    widget.onNewFilesChanged(_files);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _urls.length + _files.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 110,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: total + (widget.readOnly ? 0 : 1),
            onReorder: _reorder,
            proxyDecorator: (child, index, animation) => AnimatedBuilder(
              animation: animation,
              builder: (_, c) => Transform.scale(scale: 1.05, child: c),
              child: child,
            ),
            itemBuilder: (_, index) {
              // Add button
              if (!widget.readOnly && index == total) {
                return Padding(
                  key: const ValueKey('add'),
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: _atLimit ? null : _pickImage,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: _atLimit
                            ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _atLimit
                              ? theme.colorScheme.outlineVariant.withOpacity(0.5)
                              : theme.colorScheme.outlineVariant,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _atLimit ? Icons.block : Icons.add_photo_alternate,
                            color: _atLimit
                                ? theme.colorScheme.onSurfaceVariant.withOpacity(0.4)
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _atLimit ? t('limit_reached') : t('add'),
                            style: TextStyle(
                              fontSize: 12,
                              color: _atLimit
                                  ? theme.colorScheme.onSurfaceVariant.withOpacity(0.4)
                                  : theme.colorScheme.primary,
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
              final file = !isUrl ? _files[index - _urls.length] : null;

              return Padding(
                key: ValueKey(isUrl ? 'url_$index' : 'file_$index'),
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
                            : Image.file(
                                file!,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    if (!widget.readOnly)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => isUrl
                              ? _removeUrl(index)
                              : _removeFile(index - _urls.length),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    if (index == 0)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
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
