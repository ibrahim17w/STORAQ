// lib/widgets/category_picker.dart
// FIXED: Offline category caching, deduplication, translations

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/categories_service.dart';
import '../services/offline_service.dart';
import '../lang/translations.dart';
import '../utils/category_helper.dart';
import '../models/category.dart';

class CategoryPicker extends StatefulWidget {
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;
  final bool multiSelect;

  const CategoryPicker({
    super.key,
    required this.selectedIds,
    required this.onChanged,
    this.multiSelect = false,
  });

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);

    try {
      // Try to fetch from server (with offline fallback built into service)
      final raw = await CategoriesService.fetchCategories();
      _setCategories(raw);
      setState(() => _isOffline = false);
    } catch (e) {
      // Final fallback: try cached directly
      try {
        final cached = await OfflineService.getCachedCategories();
        if (cached.isNotEmpty) {
          _setCategories(cached);
          setState(() => _isOffline = true);
        } else {
          setState(() {
            _categories = [];
            _loading = false;
            _isOffline = true;
          });
        }
      } catch (_) {
        setState(() {
          _categories = [];
          _loading = false;
          _isOffline = true;
        });
      }
    }
  }

  Map<String, dynamic>? _toCategoryMap(dynamic cat) {
    if (cat is Category) return cat.toJson();
    if (cat is Map<String, dynamic>) return cat;
    if (cat is Map) {
      try {
        return Map<String, dynamic>.from(cat);
      } catch (_) {}
    }
    return null;
  }

  void _setCategories(List<dynamic> raw) {
    // DEDUPLICATE: keep only first occurrence of each unique ID
    final seen = <int>{};
    final deduped = <Map<String, dynamic>>[];
    for (final cat in raw) {
      final map = _toCategoryMap(cat);
      if (map == null) continue;
      final id = map['id'] as int? ?? int.tryParse('${map['id']}') ?? 0;
      if (id > 0 && !seen.contains(id)) {
        seen.add(id);
        deduped.add(map);
      }
    }
    if (mounted) {
      setState(() {
        _categories = deduped;
        _loading = false;
      });
    }
  }

  String _displayName(Map<String, dynamic> cat) =>
      CategoryHelper.displayNameFromMap(cat);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_categories.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('no_categories') ?? 'No categories available',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_isOffline)
            Text(
              t('connect_to_load_categories') ??
                  'Connect to the internet to load categories',
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isOffline)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.wifi_off, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Text(
                  t('offline_categories') ?? 'Showing cached categories',
                  style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories.map((cat) {
            final id = cat['id'] as int? ?? 0;
            final isSelected = widget.selectedIds.contains(id);
            final displayName = _displayName(cat);
            final iconName = cat['icon']?.toString() ?? 'category';

            return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _parseIcon(iconName),
                    size: 16,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(displayName),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (widget.multiSelect) {
                  final updated = List<int>.from(widget.selectedIds);
                  if (selected) {
                    if (!updated.contains(id)) updated.add(id);
                  } else {
                    updated.remove(id);
                  }
                  widget.onChanged(updated);
                } else {
                  widget.onChanged(selected ? [id] : []);
                }
              },
              selectedColor: theme.colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  IconData _parseIcon(String name) {
    final map = <String, IconData>{
      'category': Icons.category,
      'restaurant': Icons.restaurant,
      'checkroom': Icons.checkroom,
      'devices': Icons.devices,
      'home': Icons.home,
      'healing': Icons.healing,
      'toys': Icons.toys,
      'directions_car': Icons.directions_car,
      'menu_book': Icons.menu_book,
      'sports': Icons.sports,
      'electronics': Icons.devices,
      'local_grocery_store': Icons.local_grocery_store,
      'face': Icons.face,
      'child_care': Icons.child_care,
      'build': Icons.build,
      'book': Icons.book,
      'fitness_center': Icons.fitness_center,
    };
    return map[name] ?? Icons.category;
  }
}
