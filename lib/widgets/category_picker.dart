// lib/widgets/category_picker.dart
// FIXED: Deduplicates categories, supports translations via t() function

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';

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

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final raw = await ApiService.fetchCategories();
      // DEDUPLICATE: keep only first occurrence of each unique name
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final cat in raw) {
        if (cat is Map<String, dynamic>) {
          final name = cat['name']?.toString() ?? '';
          final key = name.toLowerCase().trim();
          if (key.isNotEmpty && !seen.contains(key)) {
            seen.add(key);
            deduped.add(cat);
          }
        }
      }
      if (mounted) {
        setState(() {
          _categories = deduped;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Translate category name using your translation system.
  /// Falls back to original English name if no translation found.
  String _displayName(Map<String, dynamic> cat) {
    final rawName = cat['name']?.toString() ?? 'Unknown';

    // Create a translation key from the category name
    // e.g. "Food & Beverages" -> "cat_food_beverages"
    final key = _makeTranslationKey(rawName);

    // Try to get translated version
    final translated = _safeTranslate(key);

    // If translation returns the key itself (not found), use original
    if (translated == key || translated.isEmpty) {
      return rawName;
    }
    return translated;
  }

  /// Converts category name to a safe translation key
  String _makeTranslationKey(String name) {
    return 'cat_' +
        name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
            .trim()
            .replaceAll(RegExp(r'\s+'), '_');
  }

  /// Safe wrapper around t() that won't crash if key missing
  String _safeTranslate(String key) {
    try {
      return t(key);
    } catch (_) {
      return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_categories.isEmpty) {
      return Text(
        t('no_categories'),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return Wrap(
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
      'electronics':
          Icons.devices, // Icons.electronics doesn't exist in Flutter
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
