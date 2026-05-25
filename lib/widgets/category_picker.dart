// lib/widgets/category_picker.dart
// Deduplicated category chips with clean modern UI

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
    this.multiSelect = true,
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
      final data = await ApiService.fetchCategories();
      final seen = <int>{};
      final deduped = <Map<String, dynamic>>[];
      for (final raw in data) {
        final cat = raw as Map<String, dynamic>;
        final id = cat['id'] as int?;
        if (id != null && !seen.contains(id)) {
          seen.add(id);
          deduped.add(cat);
        }
      }
      if (mounted) {
        setState(() {
          _categories = deduped;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Category load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(int id) {
    final current = List<int>.from(widget.selectedIds);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      if (widget.multiSelect) {
        current.add(id);
      } else {
        current
          ..clear()
          ..add(id);
      }
    }
    widget.onChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_categories.isEmpty) {
      return Text(
        t('no_categories_available'),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((cat) {
        final id = cat['id'] as int;
        final name = cat['name']?.toString() ?? 'Unknown';
        final selected = widget.selectedIds.contains(id);
        return ChoiceChip(
          label: Text(name),
          selected: selected,
          onSelected: (_) => _toggle(id),
          selectedColor: theme.colorScheme.primaryContainer,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          labelStyle: TextStyle(
            color: selected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          checkmarkColor: theme.colorScheme.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }
}
