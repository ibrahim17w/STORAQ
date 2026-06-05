// lib/widgets/search/search_bottom_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lang/translations.dart';
import '../../services/marketplace_service.dart';
import '../product/product_card.dart';
import '../product/product_list_tile.dart';
import '../store/store_card.dart';
import '../store/store_list_tile.dart';

class SearchBottomSheet extends StatefulWidget {
  final List<dynamic> products;
  final List<dynamic> stores;
  final void Function(dynamic) onProductTap;
  final void Function(dynamic) onStoreTap;

  const SearchBottomSheet({
    super.key,
    required this.products,
    required this.stores,
    required this.onProductTap,
    required this.onStoreTap,
  });

  @override
  State<SearchBottomSheet> createState() => _SearchBottomSheetState();
}

class _SearchBottomSheetState extends State<SearchBottomSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<dynamic> _productResults = [];
  List<dynamic> _storeResults = [];
  List<String> _searchHistory = [];
  bool _hasSearched = false;
  static const String _historyKey = 'search_history';

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    if (mounted) setState(() => _searchHistory = history);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _searchHistory);
  }

  Future<void> _addToHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;
    _searchHistory.remove(trimmed);
    _searchHistory.insert(0, trimmed);
    if (_searchHistory.length > 20) {
      _searchHistory = _searchHistory.sublist(0, 20);
    }
    await _saveHistory();
  }

  Future<void> _removeFromHistory(String query) async {
    setState(() => _searchHistory.remove(query));
    await _saveHistory();
  }

  Future<void> _clearHistory() async {
    setState(() => _searchHistory.clear());
    await _saveHistory();
  }

  void _performSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _hasSearched = false;
        _productResults = [];
        _storeResults = [];
      });
      return;
    }

    final products = widget.products.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final desc = item['description']?.toString().toLowerCase() ?? '';
      final shop = item['shop_name']?.toString().toLowerCase() ?? '';
      final cat = item['category']?.toString().toLowerCase() ?? '';
      return name.contains(q) ||
          desc.contains(q) ||
          shop.contains(q) ||
          cat.contains(q);
    }).toList();

    final stores = widget.stores.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final city = item['city']?.toString().toLowerCase() ?? '';
      final country = item['country']?.toString().toLowerCase() ?? '';
      return name.contains(q) || city.contains(q) || country.contains(q);
    }).toList();

    setState(() {
      _hasSearched = true;
      _productResults = products;
      _storeResults = stores;
    });

    if (q.length >= 2) {
      _addToHistory(query);
      MarketplaceService.trackSearch(query).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => _performSearch(q),
              onChanged: (v) => _performSearch(v),
              decoration: InputDecoration(
                hintText: t('search') ?? 'Search',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasQuery
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: !hasQuery && _searchHistory.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(
                          children: [
                            Text(
                              t('recent_searches') ?? 'Recent Searches',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _clearHistory,
                              child: Text(t('clear_all') ?? 'Clear All'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _searchHistory.length,
                          itemBuilder: (context, i) {
                            final query = _searchHistory[i];
                            return Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.history, size: 20),
                                title: Text(query),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => _removeFromHistory(query),
                                ),
                                onTap: () {
                                  _controller.text = query;
                                  _controller.selection =
                                      TextSelection.collapsed(
                                        offset: query.length,
                                      );
                                  _performSearch(query);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : !hasQuery
                ? Center(
                    child: Text(
                      t('type_to_search') ?? 'Type to search products & stores',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : (_productResults.isEmpty && _storeResults.isEmpty)
                ? Center(
                    child: Text(
                      t('no_results_found') ?? 'No results found',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_storeResults.isNotEmpty) ...[
                        Text(
                          t('stores_results') ?? 'Stores',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 160,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _storeResults.length,
                            itemBuilder: (context, i) => StoreCard(
                              store: _storeResults[i],
                              onTap: () => widget.onStoreTap(_storeResults[i]),
                              isCompact: true,
                              width: 140,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_productResults.isNotEmpty) ...[
                        Text(
                          t('products_results') ?? 'Products',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ..._productResults.map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ProductListTile(
                              product: p,
                              onTap: () => widget.onProductTap(p),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
