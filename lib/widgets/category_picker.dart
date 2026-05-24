// lib/widgets/category_picker.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';

class CategoryPicker extends StatefulWidget {
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;
  final bool multiSelect;
  final String? hint;

  const CategoryPicker({
    super.key,
    required this.selectedIds,
    required this.onChanged,
    this.multiSelect = false,
    this.hint,
  });

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  List<dynamic> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.fetchCategories();
      if (mounted) setState(() { _categories = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openPicker() async {
    final result = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategoryBottomSheet(
        categories: _categories,
        selectedIds: widget.selectedIds,
        multiSelect: widget.multiSelect,
      ),
    );
    if (result != null) widget.onChanged(result);
  }

  String _displayLabel() {
    if (widget.selectedIds.isEmpty) return widget.hint ?? t('select_category');
    final names = _categories
        .where((c) => widget.selectedIds.contains(c['id']))
        .map((c) => c['name']?.toString() ?? '')
        .toList();
    if (names.isEmpty) return widget.hint ?? t('select_category');
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const SizedBox(height: 56, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: t('category'),
          prefixIcon: const Icon(Icons.category),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          _displayLabel(),
          style: TextStyle(
            color: widget.selectedIds.isEmpty ? theme.hintColor : theme.textTheme.bodyLarge?.color,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _CategoryBottomSheet extends StatefulWidget {
  final List<dynamic> categories;
  final List<int> selectedIds;
  final bool multiSelect;

  const _CategoryBottomSheet({
    required this.categories,
    required this.selectedIds,
    required this.multiSelect,
  });

  @override
  State<_CategoryBottomSheet> createState() => _CategoryBottomSheetState();
}

class _CategoryBottomSheetState extends State<_CategoryBottomSheet> {
  late List<int> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selectedIds);
  }

  List<dynamic> get _filtered => widget.categories.where((c) {
    final name = c['name']?.toString().toLowerCase() ?? '';
    return name.contains(_query.toLowerCase());
  }).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRTL = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t('select_category'),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: t('search_categories'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final cat = _filtered[i];
                  final id = cat['id'] as int;
                  final selected = _selected.contains(id);
                  return ListTile(
                    leading: Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                    title: Text(cat['name']?.toString() ?? ''),
                    subtitle: cat['parent_id'] != null
                        ? Text(
                            widget.categories
                                .firstWhere((c) => c['id'] == cat['parent_id'], orElse: () => {'name': ''})['name']
                                ?.toString() ?? '',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        if (widget.multiSelect) {
                          if (selected) {
                            _selected.remove(id);
                          } else {
                            _selected.add(id);
                          }
                        } else {
                          _selected = [id];
                        }
                      });
                      if (!widget.multiSelect) Navigator.pop(context, _selected);
                    },
                  );
                },
              ),
            ),
            if (widget.multiSelect)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text(t('confirm')),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
