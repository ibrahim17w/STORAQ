// explore_screen.dart (FIXED – inline search, modern transparent bar, distance on image-search closest)
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
import 'login_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import '../utils/location_helper.dart';
import 'package:geolocator/geolocator.dart';

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
  bool _isGridView = true;

  // ── Location / distance sort ──
  Position? _userPosition;
  bool _sortByClosest = false;
  bool _locationLoading = false;

  // ── Image search state ──
  bool _isImageSearchActive = false;
  List<dynamic> _imageSearchResults = [];
  Uint8List? _imageSearchBytes;
  String _imageSearchSort =
      'similarity'; // 'similarity' | 'price_asc' | 'price_desc' | 'closest'

  // ── Inline text search state ──
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<dynamic> _searchProductResults = [];
  List<dynamic> _searchStoreResults = [];
  List<String> _searchHistory = [];
  bool _hasSearched = false;
  static const String _historyKey = 'search_history';

  // ── Pending views (for tracking) ──
  static final List<String> _pendingViews = [];
  static Timer? _viewFlushTimer;

  @override
  void initState() {
    super.initState();
    _loadGridPreference();
    _loadData();
    _loadHistory();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadGridPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _isGridView = prefs.getBool('explore_grid_view') ?? true);
  }

  // ── Location for closest-store sort ──
  Future<void> _initLocation() async {
    setState(() => _locationLoading = true);
    final pos = await LocationHelper.getCurrentPosition();
    if (mounted) {
      setState(() {
        _userPosition = pos;
        _locationLoading = false;
      });
    }
  }

  double _distanceToStore(dynamic store) {
    if (_userPosition == null) return double.infinity;
    final sLat = store['lat'];
    final sLng = store['lng'];
    if (sLat == null || sLng == null) return double.infinity;
    final lat = sLat is num
        ? sLat.toDouble()
        : double.tryParse(sLat.toString());
    final lng = sLng is num
        ? sLng.toDouble()
        : double.tryParse(sLng.toString());
    if (lat == null || lng == null) return double.infinity;
    return LocationHelper.distanceKm(
      _userPosition!.latitude,
      _userPosition!.longitude,
      lat,
      lng,
    );
  }

  // NEW: distance from user to the store that sells this product
  double _distanceToProduct(dynamic product) {
    if (_userPosition == null) return double.infinity;

    // Try shop_id first
    final shopId = product['shop_id'];
    if (shopId != null) {
      for (final store in _stores) {
        if (store['id'] == shopId) {
          return _distanceToStore(store);
        }
      }
    }

    // Fallback: match by shop_name -> store name
    final shopName = product['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty) {
      for (final store in _stores) {
        if (store['name']?.toString() == shopName) {
          return _distanceToStore(store);
        }
      }
    }

    return double.infinity;
  }

  List<dynamic> _sortStoresByDistance(List<dynamic> stores) {
    if (_userPosition == null || !_sortByClosest) return stores;
    final sorted = List<dynamic>.from(stores);
    sorted.sort((a, b) {
      final da = _distanceToStore(a);
      final db = _distanceToStore(b);
      return da.compareTo(db);
    });
    return sorted;
  }

  Future<void> _toggleViewMode() async {
    final newMode = !_isGridView;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('explore_grid_view', newMode);
    setState(() => _isGridView = newMode);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    // Get location in parallel with data loading
    _initLocation();
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

  Future<bool> _requireAuth() async {
    final isGuest = await ApiService.isGuest();
    final isLoggedIn = await ApiService.isLoggedIn();
    if (!isGuest || isLoggedIn) return true;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GuestAuthSheet(),
    );
    return result == true;
  }

  // NEW: Enrich product with shop_id if missing (fallback via stores list or store_id)
  dynamic _enrichProductWithStoreInfo(dynamic product) {
    if (product['shop_id'] != null) return product;

    final shopName = product['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty && _stores.isNotEmpty) {
      for (final store in _stores) {
        if (store['name']?.toString() == shopName) {
          final enriched = Map<String, dynamic>.from(product);
          enriched['shop_id'] = store['id'];
          return enriched;
        }
      }
    }

    if (product['store_id'] != null) {
      final enriched = Map<String, dynamic>.from(product);
      enriched['shop_id'] = product['store_id'];
      return enriched;
    }

    return product;
  }

  void _onProductTap(dynamic product) async {
    final canProceed = await _requireAuth();
    if (!canProceed) return;

    final enriched = _enrichProductWithStoreInfo(product);
    _trackProductView(enriched);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: enriched)),
    );
  }

  void _trackProductView(dynamic product) {
    final productName = product['name']?.toString() ?? '';
    if (productName.isEmpty) return;
    _pendingViews.remove(productName);
    _pendingViews.insert(0, productName);
    if (_pendingViews.length > 20) _pendingViews.removeLast();
    _viewFlushTimer?.cancel();
    _viewFlushTimer = Timer(const Duration(seconds: 2), _flushViews);
    final productId = product['id'];
    if (productId != null) {
      ApiService.trackProductView(productId).catchError((_) {});
    }
  }

  static Future<void> _flushViews() async {
    if (_pendingViews.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'recent_product_views',
      List<String>.from(_pendingViews),
    );
  }

  // ── Inline search logic ──
  void _onSearchChanged() {
    _performInlineSearch(_searchController.text);
  }

  void _performInlineSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _hasSearched = false;
        _searchProductResults = [];
        _searchStoreResults = [];
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

    final products = _products.where((item) {
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

    final stores = _stores.where((item) {
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
      _searchProductResults = products;
      _searchStoreResults = stores;
    });

    if (q.length >= 2) {
      _addToHistory(query);
      ApiService.trackSearch(query).catchError((_) {});
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

  // ── Search by image using CLIP embeddings ──
  Future<void> _openImageSearch() async {
    // Dismiss keyboard if inline search is active
    _searchFocusNode.unfocus();

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

    if (!mounted) return;
    final shouldSearch = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ImageSearchPreviewSheet(
        imageBytes: bytes,
        onSearch: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );

    if (shouldSearch != true || !mounted) return;
    await _performImageSearch(bytes, mimeType);
  }

  Future<void> _performImageSearch(Uint8List bytes, String mimeType) async {
    bool dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ).then((_) => dialogOpen = false);

    Map<String, dynamic>? result;
    String? errorMsg;
    bool isServerError = false;

    try {
      result = await ApiService.searchByImage(bytes, mimeType: mimeType);
    } on ApiTimeoutException catch (e) {
      errorMsg =
          t('image_search_timeout') ??
          'Image search timed out. Please try again.';
      isServerError = true;
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('model not loaded') ||
          errStr.contains('currently unavailable')) {
        errorMsg =
            t('image_search_model_unavailable') ??
            'Image search is temporarily unavailable. Please try again later.';
        isServerError = true;
      } else if (errStr.contains('socket') ||
          errStr.contains('connection') ||
          errStr.contains('network')) {
        errorMsg =
            t('image_search_network_error') ??
            'Network error. Please check your connection and try again.';
        isServerError = true;
      } else if (errStr.contains('429') || errStr.contains('too many')) {
        errorMsg =
            t('image_search_rate_limited') ??
            'Too many searches. Please wait a minute and try again.';
        isServerError = true;
      } else {
        errorMsg =
            t('image_search_failed') ??
            'Image search failed. Please try again.';
        isServerError = true;
      }
    }

    if (mounted && dialogOpen) Navigator.of(context).pop();
    if (!mounted) return;

    final results = result?['results'] as List<dynamic>?;
    if (results != null && results.isNotEmpty) {
      if (mounted) {
        setState(() {
          _isImageSearchActive = true;
          _imageSearchResults = results;
          _imageSearchBytes = bytes;
          _imageSearchSort = 'similarity';
        });
      }
    } else if (errorMsg != null) {
      if (mounted) {
        setState(() => _isImageSearchActive = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          duration: const Duration(seconds: 4),
          action: isServerError
              ? SnackBarAction(
                  label: t('retry') ?? 'Retry',
                  onPressed: () => _performImageSearch(bytes, mimeType),
                )
              : null,
        ),
      );
    } else {
      if (mounted) {
        setState(() => _isImageSearchActive = false);
      }
      final reason = result?['reason'] as String?;
      String noResultMsg;
      if (reason == 'out_of_stock') {
        noResultMsg =
            t('image_search_out_of_stock') ??
            'We found similar products but they are currently out of stock.';
      } else {
        noResultMsg =
            t('image_search_no_similar_products') ??
            'No visually similar products found in the marketplace. Try a different image or angle.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(noResultMsg),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchController.text.trim().isNotEmpty;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(t('explore') ?? 'Explore'),
          actions: [
            // Closest stores toggle
            if (!_isImageSearchActive && !isSearching)
              IconButton(
                icon: Icon(
                  _sortByClosest ? Icons.near_me : Icons.near_me_disabled,
                  size: 20,
                  color: _sortByClosest
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: () async {
                  if (_userPosition == null) {
                    await _initLocation();
                  }
                  if (mounted) {
                    setState(() => _sortByClosest = !_sortByClosest);
                  }
                },
                tooltip: _sortByClosest
                    ? (t('closest_first_on') ?? 'Closest first: ON')
                    : (t('closest_first_off') ?? 'Closest first: OFF'),
              ),
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
            // ── Modern inline search bar (blends with scaffold in both themes) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _searchFocusNode.hasFocus
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
                        : Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.12),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      _isImageSearchActive ? Icons.image_search : Icons.search,
                      size: 20,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.35),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchFocusNode.unfocus(),
                        decoration: InputDecoration(
                          hintText: _isImageSearchActive
                              ? (t('image_search_results') ??
                                    'Image Search Results')
                              : (t('search') ?? 'Search'),
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.35),
                            fontSize: 15,
                          ),
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    // Camera / Clear button
                    if (!_isImageSearchActive)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _openImageSearch,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Icon(
                              Icons.camera_alt,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ),
                    if (_isImageSearchActive)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            setState(() {
                              _isImageSearchActive = false;
                              _imageSearchResults = [];
                              _imageSearchBytes = null;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.error.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),

            if (_isImageSearchActive) _buildImageSearchHeader(),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _isImageSearchActive
                  ? _buildImageSearchResults()
                  : isSearching
                  ? _buildInlineSearchResults()
                  : _isGridView
                  ? _buildStoreGrid()
                  : _buildStoreList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Inline Search Results (products first, then stores) ──
  Widget _buildInlineSearchResults() {
    final hasQuery = _searchController.text.trim().isNotEmpty;

    if (!hasQuery && _searchHistory.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  t('recent_searches') ?? 'Recent Searches',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearHistory,
                  child: Text(_tr('clear_all', fallback: 'Clear All')),
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
                      _searchController.text = query;
                      _searchController.selection = TextSelection.collapsed(
                        offset: query.length,
                      );
                      _performInlineSearch(query);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    if (!hasQuery) {
      return Center(
        child: Text(
          t('type_to_search') ?? 'Type to search products & stores',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    if (_searchProductResults.isEmpty && _searchStoreResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
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
              if (_searchController.text.trim().split(' ').length > 1)
                TextButton(
                  onPressed: () {
                    final words = _searchController.text.trim().split(' ');
                    final broader = words.take(2).join(' ');
                    _searchController.text = broader;
                    _searchController.selection = TextSelection.collapsed(
                      offset: broader.length,
                    );
                    _performInlineSearch(broader);
                  },
                  child: Text(
                    'Try broader search: "${_searchController.text.trim().split(' ').take(2).join(' ')}"',
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── PRODUCTS FIRST ──
        if (_searchProductResults.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  t('products_results') ?? 'Products',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isGridView ? Icons.view_list : Icons.grid_view,
                  size: 18,
                ),
                onPressed: () => setState(() => _isGridView = !_isGridView),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _isGridView
              ? Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _searchProductResults
                      .map(
                        (p) => _ProductSearchCard(
                          product: p,
                          onTap: _onProductTap,
                        ),
                      )
                      .toList(),
                )
              : Column(
                  children: _searchProductResults
                      .map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ProductListTile(
                            product: p,
                            onTap: _onProductTap,
                          ),
                        ),
                      )
                      .toList(),
                ),
          const SizedBox(height: 20),
        ],

        // ── STORES SECOND ──
        if (_searchStoreResults.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  t('stores_results') ?? 'Stores',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isGridView ? Icons.view_list : Icons.grid_view,
                  size: 18,
                ),
                onPressed: () => setState(() => _isGridView = !_isGridView),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _isGridView
              ? SizedBox(
                  height: 160,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _searchStoreResults.length,
                    itemBuilder: (context, i) => _StoreSearchCard(
                      store: _searchStoreResults[i],
                      onTap: (store) async {
                        final canProceed = await _requireAuth();
                        if (!canProceed) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoreProductsScreen(
                              storeId: store['id'],
                              storeName:
                                  store['name']?.toString() ?? 'Unknown Store',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                )
              : Column(
                  children: _searchStoreResults
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _StoreListTile(
                            store: s,
                            onTap: (store) async {
                              final canProceed = await _requireAuth();
                              if (!canProceed) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StoreProductsScreen(
                                    storeId: store['id'],
                                    storeName:
                                        store['name']?.toString() ??
                                        'Unknown Store',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
        ],
      ],
    );
  }

  // ── Image Search Results Header ──
  Widget _buildImageSearchHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Searched image thumbnail + result count
          Row(
            children: [
              if (_imageSearchBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    _imageSearchBytes!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_imageSearchResults.length} ${_imageSearchResults.length == 1 ? (t('result') ?? 'result') : (t('results') ?? 'results')}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('tap_product_to_view') ??
                          'Tap a product to view details',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Sort chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              children: [
                _buildSortChip(
                  label: t('best_match') ?? 'Best Match',
                  value: 'similarity',
                  icon: Icons.auto_awesome,
                ),
                _buildSortChip(
                  label: t('cheapest_first') ?? 'Cheapest First',
                  value: 'price_asc',
                  icon: Icons.arrow_upward,
                ),
                _buildSortChip(
                  label: t('expensive_first') ?? 'Expensive First',
                  value: 'price_desc',
                  icon: Icons.arrow_downward,
                ),
                // NEW: Closest first for image search results
                if (_userPosition != null)
                  _buildSortChip(
                    label: t('closest_first') ?? 'Closest First',
                    value: 'closest',
                    icon: Icons.near_me,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _imageSearchSort == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.primary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      onSelected: (_) {
        setState(() => _imageSearchSort = value);
      },
    );
  }

  List<dynamic> _getSortedImageResults() {
    final results = List<dynamic>.from(_imageSearchResults);
    switch (_imageSearchSort) {
      case 'price_asc':
        results.sort((a, b) {
          final pa = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
          final pb = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
          return pa.compareTo(pb);
        });
        break;
      case 'price_desc':
        results.sort((a, b) {
          final pa = double.tryParse(a['price']?.toString() ?? '0') ?? 0;
          final pb = double.tryParse(b['price']?.toString() ?? '0') ?? 0;
          return pb.compareTo(pa);
        });
        break;
      case 'closest':
        if (_userPosition != null) {
          results.sort((a, b) {
            final da = _distanceToProduct(a);
            final db = _distanceToProduct(b);
            return da.compareTo(db);
          });
        }
        break;
      case 'similarity':
      default:
        results.sort((a, b) {
          final sa = (a['similarity_score'] as num?) ?? 0;
          final sb = (b['similarity_score'] as num?) ?? 0;
          return sb.compareTo(sa); // highest first
        });
        break;
    }
    return results;
  }

  Widget _buildImageSearchResults() {
    final results = _getSortedImageResults();
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              t('no_results_found') ?? 'No results found',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (_isGridView) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: results.map((product) {
            final similarity = product['similarity_score'] as num? ?? 0;
            final distance = _distanceToProduct(product);
            final showDistance =
                _imageSearchSort == 'closest' && distance != double.infinity;
            return GestureDetector(
              onTap: () => _onProductTap(product),
              child: Container(
                width: (MediaQuery.of(context).size.width - 56) / 2,
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
                    Stack(
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
                        // Similarity badge (when NOT closest sort)
                        if (!showDistance)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${(similarity * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        // Store name badge
                        if (product['shop_name'] != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                product['shop_name'].toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                      ],
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
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          if (showDistance) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 10,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${distance.toStringAsFixed(1)} km',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    // List view
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final product = results[i];
        final similarity = product['similarity_score'] as num? ?? 0;
        final distance = _distanceToProduct(product);
        final showDistance =
            _imageSearchSort == 'closest' && distance != double.infinity;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => _onProductTap(product),
            child: Stack(
              children: [
                _ProductListTile(
                  product: product,
                  onTap: _onProductTap,
                  distanceKm: showDistance ? distance : null,
                ),
                // Similarity badge (when NOT closest sort)
                if (!showDistance)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${(similarity * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                // Store name badge
                if (product['shop_name'] != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        product['shop_name'].toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStoreGrid() {
    final stores = _sortStoresByDistance(_filtered);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.start,
        children: stores
            .map(
              (store) => _StoreCard(
                store: store,
                distanceKm: _sortByClosest ? _distanceToStore(store) : null,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildStoreList() {
    final stores = _sortStoresByDistance(_filtered);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: stores.length,
      itemBuilder: (context, i) {
        final store = stores[i];
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
                builder: (_) => StoreProductsScreen(
                  storeId: store['id'],
                  storeName: store['name']?.toString() ?? 'Unknown Store',
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        // Show distance when closest sort is active
                        if (_sortByClosest && _userPosition != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_distanceToStore(store).toStringAsFixed(1)} km',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
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
                            targetName:
                                store['name']?.toString() ?? 'Unknown Store',
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

class _StoreCard extends StatelessWidget {
  final dynamic store;
  final double? distanceKm;

  const _StoreCard({required this.store, this.distanceKm});

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
          builder: (_) => StoreProductsScreen(
            storeId: store['id'],
            storeName: store['name']?.toString() ?? 'Unknown Store',
          ),
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
                  if (distanceKm != null && distanceKm != double.infinity) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 10,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${distanceKm!.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
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
// SEARCH RESULT WIDGETS (reused for inline & image search)
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
  final double? distanceKm;

  const _ProductListTile({
    required this.product,
    required this.onTap,
    this.distanceKm,
  });

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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product['shop_name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        if (distanceKm != null &&
                            distanceKm != double.infinity) ...[
                          Icon(
                            Icons.location_on,
                            size: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${distanceKm!.toStringAsFixed(1)} km',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
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

// ============================================================
// IMAGE SEARCH PREVIEW SHEET
// ============================================================

class _ImageSearchPreviewSheet extends StatefulWidget {
  final Uint8List imageBytes;
  final VoidCallback onSearch;
  final VoidCallback onCancel;

  const _ImageSearchPreviewSheet({
    required this.imageBytes,
    required this.onSearch,
    required this.onCancel,
  });

  @override
  State<_ImageSearchPreviewSheet> createState() =>
      _ImageSearchPreviewSheetState();
}

class _ImageSearchPreviewSheetState extends State<_ImageSearchPreviewSheet> {
  final _searchFocus = FocusNode();
  final _cancelFocus = FocusNode();
  bool _searchFocused = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.select) {
        if (_searchFocused) {
          widget.onSearch();
        } else {
          widget.onCancel();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        setState(() {
          _searchFocused = !_searchFocused;
          if (_searchFocused) {
            _searchFocus.requestFocus();
          } else {
            _cancelFocus.requestFocus();
          }
        });
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onCancel();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        _handleKey(event);
        return KeyEventResult.handled;
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.65,
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
              child: Text(
                t('image_search_preview') ?? 'Search by Image',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('image_search_preview_subtitle') ??
                  'Find visually similar products in the marketplace',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: Focus(
                      focusNode: _cancelFocus,
                      child: OutlinedButton(
                        onPressed: widget.onCancel,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: !_searchFocused
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Text(t('cancel') ?? 'Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Focus(
                      focusNode: _searchFocus,
                      child: FilledButton(
                        onPressed: widget.onSearch,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: _searchFocused
                              ? BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Text(t('search') ?? 'Search'),
                      ),
                    ),
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

// ============================================================
// GUEST AUTH SHEET (copied from home_screen for consistency)
// ============================================================

class _GuestAuthSheet extends StatelessWidget {
  const _GuestAuthSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 24),
          Icon(
            Icons.lock_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            t('login_required') ?? 'Login Required',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              t('guest_login_prompt') ??
                  'Please log in or register to access this feature.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  t('login_or_register') ?? 'Log In / Register',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('continue_browsing') ?? 'Continue Browsing'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
