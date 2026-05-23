// explore_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../widgets/cached_image.dart';
import 'store_products_screen.dart';
import 'store_map_screen.dart';
import 'product_detail_screen.dart';
import 'package:latlong2/latlong.dart';

// ── Translation helper (same as home_screen) ──
String _tr(String key, {required String fallback}) {
  final result = t(key);
  if (result == null || result == key) return fallback;
  return result;
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<dynamic> _stores = [];
  List<dynamic> _products = [];
  List<dynamic> _filtered = [];
  bool _isLoading = true;
  // NEW: Grid/list view toggle
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _loadGridPreference();
    _loadData();
  }

  // NEW: Load grid preference
  Future<void> _loadGridPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _isGridView = prefs.getBool('explore_grid_view') ?? true);
  }

  // NEW: Toggle grid/list
  Future<void> _toggleViewMode() async {
    final newMode = !_isGridView;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('explore_grid_view', newMode);
    setState(() => _isGridView = newMode);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.fetchStores(),
        ApiService.fetchMarketplaceFeed(),
      ]);
      if (mounted) {
        setState(() {
          _stores = results[0];
          _products = results[1];
          _filtered = _stores;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Open the same bottom-sheet search from home_screen ──
  void _openSearch({String? initialQuery}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SearchBottomSheet(
        products: _products,
        stores: _stores,
        initialQuery: initialQuery,
        isGridView: _isGridView,
        onProductTap: (product) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product),
            ),
          );
        },
        onStoreTap: (store) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoreProductsScreen(storeId: store['id']),
            ),
          );
        },
      ),
    );
  }

  // ── Search by image using Gemini (free tier) ──
  Future<void> _openImageSearch() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    final mimeType = picked.mimeType ?? 'image/jpeg';

    bool dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ).then((_) => dialogOpen = false);

    String? query;
    String? errorMsg;

    try {
      query = await ApiService.searchByImage(bytes, mimeType: mimeType);
    } on ApiTimeoutException catch (e) {
      errorMsg = 'Image search timed out. Please try again.';
    } catch (e) {
      errorMsg = 'Image search failed: ${e.toString()}';
    }

    if (mounted && dialogOpen) {
      Navigator.of(context).pop();
    }

    if (!mounted) return;

    if (query != null && query.isNotEmpty) {
      _openSearch(initialQuery: query);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMsg ??
                (t('image_search_no_results') ??
                    'Could not identify product in image'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(t('explore') ?? 'Explore'),
          actions: [
            // NEW: Grid/list toggle in app bar
            IconButton(
              icon: Icon(
                _isGridView ? Icons.view_list : Icons.grid_view,
                size: 20,
              ),
              onPressed: _toggleViewMode,
              tooltip: _isGridView
                  ? (t('list_view') ?? 'List view')
                  : (t('grid_view') ?? 'Grid view'),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Search bar (same style as home_screen) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: GestureDetector(
                onTap: _openSearch,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Icon(
                        Icons.search,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t('search') ?? 'Search',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.4),
                            fontSize: 15,
                          ),
                        ),
                      ),
                      // Image search icon inside the bar
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _openImageSearch,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Icon(
                              Icons.camera_alt,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),

            // ── Store list ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _isGridView
                  ? _buildStoreGrid()
                  : _buildStoreList(),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Grid view for stores
  Widget _buildStoreGrid() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.start,
        children: _filtered.map((store) => _StoreCard(store: store)).toList(),
      ),
    );
  }

  // NEW: List view for stores (with image + description)
  Widget _buildStoreList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filtered.length,
      itemBuilder: (context, i) {
        final store = _filtered[i];
        final lat = double.tryParse(store['lat']?.toString() ?? '');
        final lng = double.tryParse(store['lng']?.toString() ?? '');
        final hasLocation = lat != null && lng != null;
        final description =
            store['location_description']?.toString() ??
            store['description']?.toString() ??
            '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoreProductsScreen(storeId: store['id']),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Store image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedAppImage(
                      imageUrl: store['image_url'],
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Store info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store['name'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${store['city'] ?? ''}, ${store['country'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        // NEW: Show description if available
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Map button
                  if (hasLocation)
                    IconButton(
                      icon: Icon(
                        Icons.map,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StoreLocationView(
                            target: LatLng(lat, lng),
                            targetStoreId: store['id'],
                            targetName: store['name']?.toString(),
                            targetImageUrl: store['image_url']?.toString(),
                            stores: _stores,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// NEW: Store card for grid view
class _StoreCard extends StatelessWidget {
  final dynamic store;

  const _StoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    final description =
        store['location_description']?.toString() ??
        store['description']?.toString() ??
        '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoreProductsScreen(storeId: store['id']),
        ),
      ),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: CachedAppImage(
                imageUrl: store['image_url'],
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 400,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${store['city'] ?? ''}, ${store['country'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                  // NEW: Show short description
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SEARCH BOTTOM SHEET (MATCHES home_screen.dart EXACTLY)
// ============================================================

class SearchBottomSheet extends StatefulWidget {
  final List<dynamic> products;
  final List<dynamic> stores;
  final String? initialQuery;
  final bool isGridView;
  final void Function(dynamic) onProductTap;
  final void Function(dynamic) onStoreTap;

  const SearchBottomSheet({
    super.key,
    required this.products,
    required this.stores,
    this.initialQuery,
    this.isGridView = true,
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
  bool _isGridView = true;
  static const String _historyKey = 'search_history';

  @override
  void initState() {
    super.initState();
    _isGridView = widget.isGridView;
    _focusNode.requestFocus();
    _loadHistory();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      _controller.selection = TextSelection.collapsed(
        offset: widget.initialQuery!.length,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(widget.initialQuery!);
      });
    }
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
    if (_searchHistory.length > 20)
      _searchHistory = _searchHistory.sublist(0, 20);
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

    final queryWords = q
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .toList();
    if (queryWords.isEmpty && q.length >= 1) {
      queryWords.add(q);
    }

    final products = widget.products.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final desc = item['description']?.toString().toLowerCase() ?? '';
      final shop = item['shop_name']?.toString().toLowerCase() ?? '';
      final cat = item['category']?.toString().toLowerCase() ?? '';
      return queryWords.any(
        (word) =>
            name.contains(word) ||
            desc.contains(word) ||
            shop.contains(word) ||
            cat.contains(word),
      );
    }).toList();

    final stores = widget.stores.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final city = item['city']?.toString().toLowerCase() ?? '';
      final country = item['country']?.toString().toLowerCase() ?? '';
      final description =
          item['location_description']?.toString().toLowerCase() ?? '';
      return queryWords.any(
        (word) =>
            name.contains(word) ||
            city.contains(word) ||
            country.contains(word) ||
            description.contains(word),
      );
    }).toList();

    setState(() {
      _hasSearched = true;
      _productResults = products;
      _storeResults = stores;
    });

    if (q.length >= 2) {
      _addToHistory(query);
      ApiService.trackSearch(query).catchError((_) {});
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
          // Search bar with grid/list toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: 8),
                // Grid/list toggle inside search sheet
                IconButton(
                  icon: Icon(
                    _isGridView ? Icons.view_list : Icons.grid_view,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                  tooltip: _isGridView
                      ? (t('list_view') ?? 'List view')
                      : (t('grid_view') ?? 'Grid view'),
                ),
              ],
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
                              child: Text(
                                _tr('clear_all', fallback: 'Clear All'),
                              ),
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
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.history, size: 20),
                              title: Text(query),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => _removeFromHistory(query),
                              ),
                              onTap: () {
                                _controller.text = query;
                                _controller.selection = TextSelection.collapsed(
                                  offset: query.length,
                                );
                                _performSearch(query);
                              },
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
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t('no_results_found') ?? 'No results found',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_controller.text.trim().split(' ').length > 1)
                            TextButton(
                              onPressed: () {
                                final words = _controller.text.trim().split(
                                  ' ',
                                );
                                final broader = words.take(2).join(' ');
                                _controller.text = broader;
                                _controller.selection = TextSelection.collapsed(
                                  offset: broader.length,
                                );
                                _performSearch(broader);
                              },
                              child: Text(
                                'Try broader search: "${_controller.text.trim().split(' ').take(2).join(' ')}"',
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_storeResults.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('stores_results') ?? 'Stores',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            // Toggle for store results
                            IconButton(
                              icon: Icon(
                                _isGridView ? Icons.view_list : Icons.grid_view,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _isGridView = !_isGridView),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _isGridView
                            ? SizedBox(
                                height: 160,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _storeResults.length,
                                  itemBuilder: (context, i) => _StoreSearchCard(
                                    store: _storeResults[i],
                                    onTap: widget.onStoreTap,
                                  ),
                                ),
                              )
                            : Column(
                                children: _storeResults
                                    .map(
                                      (s) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _StoreListTile(
                                          store: s,
                                          onTap: widget.onStoreTap,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                        const SizedBox(height: 16),
                      ],
                      if (_productResults.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('products_results') ?? 'Products',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _isGridView ? Icons.view_list : Icons.grid_view,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _isGridView = !_isGridView),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _isGridView
                            ? Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: _productResults
                                    .map(
                                      (p) => _ProductSearchCard(
                                        product: p,
                                        onTap: widget.onProductTap,
                                      ),
                                    )
                                    .toList(),
                              )
                            : Column(
                                children: _productResults
                                    .map(
                                      (p) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _ProductListTile(
                                          product: p,
                                          onTap: widget.onProductTap,
                                        ),
                                      ),
                                    )
                                    .toList(),
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

// ============================================================
// SEARCH RESULT WIDGETS (with images + descriptions)
// ============================================================

class _StoreSearchCard extends StatelessWidget {
  final dynamic store;
  final void Function(dynamic) onTap;

  const _StoreSearchCard({required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final description =
        store['location_description']?.toString() ??
        store['description']?.toString() ??
        '';

    return GestureDetector(
      onTap: () => onTap(store),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: CachedAppImage(
                imageUrl: store['image_url'],
                height: 90,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 300,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${store['city'] ?? ''}, ${store['country'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSearchCard extends StatelessWidget {
  final dynamic product;
  final void Function(dynamic) onTap;

  const _ProductSearchCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(product),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: CachedAppImage(
                imageUrl: product['image_url'],
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 400,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '\$${product['price']}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product['shop_name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreListTile extends StatelessWidget {
  final dynamic store;
  final void Function(dynamic) onTap;

  const _StoreListTile({required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final description =
        store['location_description']?.toString() ??
        store['description']?.toString() ??
        '';

    return GestureDetector(
      onTap: () => onTap(store),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              child: CachedAppImage(
                imageUrl: store['image_url'],
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                memCacheWidth: 200,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${store['city'] ?? ''}, ${store['country'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductListTile extends StatelessWidget {
  final dynamic product;
  final void Function(dynamic) onTap;

  const _ProductListTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(product),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              child: CachedAppImage(
                imageUrl: product['image_url'],
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                memCacheWidth: 300,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${product['price']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product['shop_name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
