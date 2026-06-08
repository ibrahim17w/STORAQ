// lib/screens/explore_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../widgets/cached_image.dart';
import 'store_products_screen.dart';
import 'store_map_screen.dart';
import 'store_qr_scanner_screen.dart';
import 'product_detail_screen.dart';
import '../utils/product_store_helper.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import '../utils/location_helper.dart';
import 'package:geolocator/geolocator.dart';
import '../services/marketplace_service.dart';
import '../services/location_service.dart';
import '../services/image_search_service.dart';
import '../services/store_service.dart';
import '../models/models.dart';
import '../services/favorites_service.dart';
import '../providers/viewer_currency_provider.dart';
import '../services/currency_service.dart';
import '../widgets/product/product_card.dart';
import '../widgets/product/product_list_tile.dart';
import '../widgets/store/store_card.dart';
import '../widgets/store/store_list_tile.dart';
import '../widgets/guest_login_sheet.dart' as guest;
import '../utils/tr.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  List<Store> _stores = [];
  List<Product> _products = [];
  List<Store> _filtered = [];
  bool _isLoading = true;
  bool _isGridView = true;

  Position? _userPosition;
  bool _sortByClosest = false;
  bool _locationLoading = false;

  bool _isImageSearchActive = false;
  List<dynamic> _imageSearchResults = [];
  Uint8List? _imageSearchBytes;
  String _imageSearchSort = 'similarity';

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Product> _searchProductResults = [];
  List<Store> _searchStoreResults = [];
  List<String> _searchHistory = [];
  bool _hasSearched = false;
  static const String _historyKey = 'search_history';

  static final List<String> _pendingViews = [];
  static Timer? _viewFlushTimer;

  Set<int> _favoriteIds = {};
  Set<int> _favoriteStoreIds = {};

  /// Extra space so scrollable content clears the floating bottom nav bar.
  double _navBarScrollInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 80;

  EdgeInsets _scrollPadding(BuildContext context, {double inset = 16}) {
    return EdgeInsets.fromLTRB(
      inset,
      inset,
      inset,
      inset + _navBarScrollInset(context),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadGridPreference();
    _loadData();
    _loadHistory();
    _searchController.addListener(_onSearchChanged);
    _loadFavorites();
    _loadFavoriteStores();

    FavoritesService.favoriteIdsNotifier.addListener(_onFavoritesChanged);
    FavoritesService.favoriteStoreIdsNotifier.addListener(
      _onStoreFavoritesChanged,
    );
  }

  @override
  void dispose() {
    FavoritesService.favoriteIdsNotifier.removeListener(_onFavoritesChanged);
    FavoritesService.favoriteStoreIdsNotifier.removeListener(
      _onStoreFavoritesChanged,
    );
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) {
      setState(
        () => _favoriteIds = Set<int>.from(
          FavoritesService.favoriteIdsNotifier.value,
        ),
      );
    }
  }

  void _onStoreFavoritesChanged() {
    if (mounted) {
      setState(
        () => _favoriteStoreIds = Set<int>.from(
          FavoritesService.favoriteStoreIdsNotifier.value,
        ),
      );
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final ids = await FavoritesService.getLocalFavoriteIds();
      if (mounted) setState(() => _favoriteIds = ids.toSet());
    } catch (_) {}
  }

  Future<void> _loadFavoriteStores() async {
    try {
      final ids = await FavoritesService.getLocalFavoriteStoreIds();
      if (mounted) setState(() => _favoriteStoreIds = ids.toSet());
    } catch (_) {}
  }

  Future<void> _toggleFavorite(
    int productId,
    dynamic product,
  ) async {
    final map = product is Product ? product.toJson() : product as Map<String, dynamic>;
    await FavoritesService.toggleFavorite(productId, product: map);
  }

  Future<void> _toggleFavoriteStore(
    int storeId,
    dynamic store,
  ) async {
    final map = store is Store ? store.toJson() : store as Map<String, dynamic>;
    await FavoritesService.toggleFavoriteStore(storeId, store: map);
  }

  int? _productId(dynamic product) {
    if (product is Product) return product.intId;
    final id = product['id'];
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  int? _storeId(dynamic store) {
    if (store is Store) return store.intId;
    final id = store['id'];
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  Future<void> _loadGridPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _isGridView = prefs.getBool('explore_grid_view') ?? true);
  }

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

  double _distanceToStore(Store store) {
    if (_userPosition == null) return double.infinity;
    final lat = store.lat;
    final lng = store.lng;
    if (lat == null || lng == null) return double.infinity;
    return LocationHelper.distanceKm(
      _userPosition!.latitude,
      _userPosition!.longitude,
      lat,
      lng,
    );
  }

  double _distanceToProduct(dynamic product) {
    if (_userPosition == null) return double.infinity;
    final shopId = product is Product ? product.storeId : product['shop_id'];
    if (shopId != null) {
      for (final store in _stores) {
        if (store.id == shopId) {
          return _distanceToStore(store);
        }
      }
    }
    final shopName = product is Product
        ? product.shopName
        : product['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty) {
      for (final store in _stores) {
        if (store.name == shopName) {
          return _distanceToStore(store);
        }
      }
    }
    return double.infinity;
  }

  List<Store> _sortStoresByDistance(List<Store> stores) {
    if (_userPosition == null || !_sortByClosest) return stores;
    final sorted = List<Store>.from(stores);
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
    _initLocation();
    try {
      final storesFuture = StoreService.fetchStores();
      final productsFuture = MarketplaceService.fetchMarketplaceFeed();
      final fetchedStores = await storesFuture;
      final fetchedProducts = await productsFuture;
      if (mounted) {
        setState(() {
          _stores = fetchedStores;
          _products = fetchedProducts;
          _filtered = _stores;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _enrichProductWithStoreInfo(dynamic product) {
    final map = product is Product
        ? product.toJson()
        : Map<String, dynamic>.from(product as Map);
    if (map['shop_id'] != null) return map;
    final shopName = map['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty && _stores.isNotEmpty) {
      for (final store in _stores) {
        if (store.name == shopName) {
          map['shop_id'] = store.id;
          return map;
        }
      }
    }
    if (map['store_id'] != null) {
      map['shop_id'] = map['store_id'];
    }
    return map;
  }

  void _onProductTap(dynamic product) async {
    final canProceed = await guest.requireAuth(context);
    if (!canProceed) return;
    final enriched = productToDetailMap(_enrichProductWithStoreInfo(product));
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
      MarketplaceService.trackProductView(productId).catchError((_) {});
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
      final name = item.name?.toLowerCase() ?? '';
      final desc = item.description?.toLowerCase() ?? '';
      final shop = item.shopName?.toLowerCase() ?? '';
      return queryWords.any(
        (word) =>
            name.contains(word) ||
            desc.contains(word) ||
            shop.contains(word),
      );
    }).toList();

    final stores = _stores.where((item) {
      final name = item.name?.toLowerCase() ?? '';
      final city = item.city?.toLowerCase() ?? '';
      final country = item.country?.toLowerCase() ?? '';
      return queryWords.any(
        (word) =>
            name.contains(word) ||
            city.contains(word) ||
            country.contains(word),
      );
    }).toList();

    setState(() {
      _hasSearched = true;
      _searchProductResults = products;
      _searchStoreResults = stores;
    });

    if (q.length >= 2) {
      _addToHistory(query);
      MarketplaceService.trackSearch(query).catchError((_) {});
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

  Future<void> _openImageSearch() async {
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
      result = await ImageSearchService.searchByImage(
        bytes,
        mimeType: mimeType,
      );
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
            'Image search is temporarily unavailable.';
        isServerError = true;
      } else if (errStr.contains('socket') ||
          errStr.contains('connection') ||
          errStr.contains('network')) {
        errorMsg =
            t('image_search_network_error') ??
            'Network error. Please check your connection.';
        isServerError = true;
      } else if (errStr.contains('429') || errStr.contains('too many')) {
        errorMsg =
            t('image_search_rate_limited') ??
            'Too many searches. Please wait a minute.';
        isServerError = true;
      } else {
        errorMsg = t('image_search_failed') ?? 'Image search failed.';
        isServerError = true;
      }
    }

    if (mounted && dialogOpen) Navigator.of(context).pop();
    if (!mounted) return;

    final results = result?['results'] as List<dynamic>?;
    if (results != null && results.isNotEmpty) {
      if (_userPosition == null) {
        await _initLocation();
      }
      if (mounted) {
        _searchFocusNode.unfocus();
        _searchController.clear();
        setState(() {
          _isImageSearchActive = true;
          _imageSearchResults = results;
          _imageSearchBytes = bytes;
          _imageSearchSort =
              _userPosition != null ? 'closest' : 'similarity';
        });
      }
    } else if (errorMsg != null) {
      if (mounted) setState(() => _isImageSearchActive = false);
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
      if (mounted) setState(() => _isImageSearchActive = false);
      final reason = result?['reason'] as String?;
      String noResultMsg;
      if (reason == 'out_of_stock') {
        noResultMsg =
            t('image_search_out_of_stock') ??
            'Similar products found but out of stock.';
      } else {
        noResultMsg =
            t('image_search_no_similar_products') ??
            'No visually similar products found.';
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
            IconButton(
              icon: const Icon(Icons.qr_code_scanner, size: 22),
              tooltip: t('scan_store_qr') ?? 'Scan Store QR',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StoreQrScannerScreen(),
                  ),
                );
              },
            ),
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
                        readOnly: _isImageSearchActive,
                        canRequestFocus: !_isImageSearchActive,
                        enableInteractiveSelection: !_isImageSearchActive,
                        showCursor: !_isImageSearchActive,
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
                            _searchFocusNode.unfocus();
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
                  child: Text(tr('clear_all', fallback: 'Clear All')),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: _navBarScrollInset(context),
              ),
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
                    '${t('try_broader_search')}: "${_searchController.text.trim().split(' ').take(2).join(' ')}"',
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: _scrollPadding(context),
      children: [
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
                  children: _searchProductResults.map((p) {
                    final pid = _productId(p);
                    return ProductCard(
                      product: p.toJson(),
                      onTap: () => _onProductTap(p),
                      showFavorite: pid != null,
                      isFavorite: pid != null && _favoriteIds.contains(pid),
                      onFavoriteToggle: pid != null
                          ? () => _toggleFavorite(pid, p)
                          : null,
                      currencySettings: ref.watch(viewerCurrencyProvider).currencySettings,
                    );
                  }).toList(),
                )
              : Column(
                  children: _searchProductResults.map((p) {
                    final pid = _productId(p);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ProductListTile(
                        product: p.toJson(),
                        onTap: () => _onProductTap(p),
                        showFavorite: pid != null,
                        isFavorite: pid != null && _favoriteIds.contains(pid),
                        onFavoriteToggle: pid != null
                            ? () => _toggleFavorite(pid, p)
                            : null,
                        currencySettings: ref.watch(viewerCurrencyProvider).currencySettings,
                      ),
                    );
                  }).toList(),
                ),
          const SizedBox(height: 20),
        ],
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
                    itemBuilder: (context, i) {
                      final store = _searchStoreResults[i];
                      final sid = _storeId(store);
                      return StoreCard(
                        store: store.toJson(),
                        onTap: () async {
                          final canProceed = await guest.requireAuth(context);
                          if (!canProceed) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StoreProductsScreen(
                                storeId: store.intId ?? 0,
                                storeName:
                                    store.name ?? t('unknown_store'),
                              ),
                            ),
                          );
                        },
                        isCompact: true,
                        width: 140,
                        showFavorite: sid != null,
                        isFavorite:
                            sid != null && _favoriteStoreIds.contains(sid),
                        onFavoriteToggle: sid != null
                            ? () => _toggleFavoriteStore(sid, store)
                            : null,
                      );
                    },
                  ),
                )
              : Column(
                  children: _searchStoreResults.map((s) {
                    final sid = _storeId(s);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: StoreListTile(
                        store: s.toJson(),
                        onTap: () async {
                          final canProceed = await guest.requireAuth(context);
                          if (!canProceed) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StoreProductsScreen(
                                storeId: s.intId ?? 0,
                                storeName:
                                    s.name ?? t('unknown_store'),
                              ),
                            ),
                          );
                        },
                        showFavorite: sid != null,
                        isFavorite:
                            sid != null && _favoriteStoreIds.contains(sid),
                        onFavoriteToggle: sid != null
                            ? () => _toggleFavoriteStore(sid, s)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
        ],
      ],
    );
  }

  Widget _buildImageSearchHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
      onSelected: (_) async {
        if (value == 'closest' && _userPosition == null) {
          await _initLocation();
        }
        if (mounted) {
          setState(() => _imageSearchSort = value);
        }
      },
    );
  }

  List<dynamic> _getSortedImageResults() {
    final results = List<dynamic>.from(_imageSearchResults);
    switch (_imageSearchSort) {
      case 'price_asc':
        results.sort((a, b) {
          final pa = CurrencyService.comparablePrice(
            a,
            ref.read(viewerCurrencyProvider).currencySettings,
          );
          final pb = CurrencyService.comparablePrice(
            b,
            ref.read(viewerCurrencyProvider).currencySettings,
          );
          return pa.compareTo(pb);
        });
        break;
      case 'price_desc':
        results.sort((a, b) {
          final pa = CurrencyService.comparablePrice(
            a,
            ref.read(viewerCurrencyProvider).currencySettings,
          );
          final pb = CurrencyService.comparablePrice(
            b,
            ref.read(viewerCurrencyProvider).currencySettings,
          );
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
          return sb.compareTo(sa);
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
        padding: _scrollPadding(context),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.start,
          children: results.map((product) {
            final similarity =
                (product['similarity_score'] as num? ?? 0).toDouble();
            final distance = _distanceToProduct(product);
            final pid = _productId(product);
            return ProductCard(
              product: product,
              onTap: () => _onProductTap(product),
              showFavorite: pid != null,
              isFavorite: pid != null && _favoriteIds.contains(pid),
              onFavoriteToggle: pid != null
                  ? () => _toggleFavorite(pid, product)
                  : null,
              currencySettings:
                  ref.watch(viewerCurrencyProvider).currencySettings,
              distanceKm: distance != double.infinity ? distance : null,
              similarityScore:
                  _imageSearchSort != 'closest' ? similarity : null,
            );
          }).toList(),
        ),
      );
    }

    return ListView.builder(
      padding: _scrollPadding(context),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final product = results[i];
        final similarity = product['similarity_score'] as num? ?? 0;
        final distance = _distanceToProduct(product);
        final showDistance = distance != double.infinity;
        final pid = _productId(product);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => _onProductTap(product),
            child: Stack(
              children: [
                ProductListTile(
                  product: product,
                  onTap: () => _onProductTap(product),
                  distanceKm: showDistance ? distance : null,
                  showFavorite: pid != null,
                  isFavorite: pid != null && _favoriteIds.contains(pid),
                  onFavoriteToggle: pid != null
                      ? () => _toggleFavorite(pid, product)
                      : null,
                  currencySettings: ref.watch(viewerCurrencyProvider).currencySettings,
                ),
                if (_imageSearchSort != 'closest')
                  PositionedDirectional(
                    top: 8,
                    end: 8,
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
      padding: _scrollPadding(context, inset: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.start,
        children: stores.map((store) {
          final sid = _storeId(store);
          return StoreCard(
            store: store.toJson(),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoreProductsScreen(
                  storeId: store.intId ?? 0,
                  storeName: store.name ?? t('unknown_store'),
                ),
              ),
            ),
            distanceKm: _sortByClosest ? _distanceToStore(store) : null,
            showFavorite: sid != null,
            isFavorite: sid != null && _favoriteStoreIds.contains(sid),
            onFavoriteToggle: sid != null
                ? () => _toggleFavoriteStore(sid, store)
                : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStoreList() {
    final stores = _sortStoresByDistance(_filtered);
    return ListView.builder(
      padding: _scrollPadding(context, inset: 12),
      itemCount: stores.length,
      itemBuilder: (context, i) {
        final store = stores[i];
        final lat = store.lat;
        final lng = store.lng;
        final hasLocation = lat != null && lng != null;
        final sid = _storeId(store);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoreProductsScreen(
                  storeId: store.intId ?? 0,
                  storeName: store.name ?? t('unknown_store'),
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
                      imageUrl: store.imageUrl,
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
                          store.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${store.city ?? ''}, ${store.country ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
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
                                LocationHelper.formatDistanceKm(
                                  _distanceToStore(store),
                                ),
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
                  if (sid != null)
                    IconButton(
                      icon: Icon(
                        _favoriteStoreIds.contains(sid)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: _favoriteStoreIds.contains(sid)
                            ? Colors.red
                            : Colors.grey,
                      ),
                      onPressed: () => _toggleFavoriteStore(sid, store),
                    )
                  else if (hasLocation)
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
                            targetStoreId: store.intId,
                            targetName:
                                store.name ?? t('unknown_store'),
                            targetImageUrl: store.imageUrl,
                            stores: _stores.map((s) => s.toJson()).toList(),
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

// ============================================================
// IMAGE SEARCH PREVIEW SHEET (explore-unique, stays here)
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
