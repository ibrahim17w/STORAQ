// lib/screens/favorites_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/favorites_service.dart';
import '../lang/translations.dart';
import '../widgets/guest_login_sheet.dart';
import '../widgets/product/product_card.dart';
import '../widgets/product/product_list_tile.dart';
import '../widgets/store/store_list_tile.dart';
import 'product_detail_screen.dart';
import 'store_products_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _favorites = [];
  List<dynamic> _favoriteStores = [];
  bool _isLoadingProducts = true;
  bool _isLoadingStores = true;
  bool _isGridView = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    _tabController.dispose();
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) _loadFavorites();
  }

  void _onStoreFavoritesChanged() {
    if (mounted) _loadFavoriteStores();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoadingProducts = true);
    try {
      final items = await FavoritesService.fetchFavorites();
      if (mounted) {
        setState(() {
          _favorites = items;
          _isLoadingProducts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _loadFavoriteStores() async {
    setState(() => _isLoadingStores = true);
    try {
      final items = await FavoritesService.fetchFavoriteStores();
      if (mounted) {
        setState(() {
          _favoriteStores = items;
          _isLoadingStores = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStores = false);
    }
  }

  void _onProductTap(dynamic product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  void _onStoreTap(dynamic store) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(
          storeId: store['id'],
          storeName: store['name']?.toString() ?? 'Unknown Store',
        ),
      ),
    );
  }

  Future<void> _removeFavorite(int productId) async {
    await FavoritesService.removeFavorite(productId);
  }

  Future<void> _removeFavoriteStore(int storeId) async {
    await FavoritesService.removeFavoriteStore(storeId);
  }

  int? _productId(dynamic product) {
    final id = product['id'];
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  int? _storeId(dynamic store) {
    final id = store['id'];
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ApiService.isLoggedIn(),
      builder: (context, snapshot) {
        final isLoggedIn = snapshot.data ?? false;

        if (!isLoggedIn) {
          return _buildGuestPrompt();
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(t('favorites') ?? 'Favorites'),
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.white, // Selected tab text
              unselectedLabelColor: Colors.white70, // Unselected tab text
              indicatorColor: Colors.white, // Underline indicator
              tabs: [
                Tab(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  text: t('products') ?? 'Products',
                ),
                Tab(
                  icon: const Icon(Icons.store_outlined),
                  text: t('stores') ?? 'Stores',
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [_buildProductsTab(), _buildStoresTab()],
          ),
        );
      },
    );
  }

  Widget _buildGuestPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              t('login_to_continue') ?? 'Login to continue',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              t('guest_restricted') ?? 'Guests cannot access favorites',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => showGuestSheet(context),
              child: Text(t('login') ?? 'Login'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Products Tab ──
  Widget _buildProductsTab() {
    return RefreshIndicator(
      onRefresh: _loadFavorites,
      child: _isLoadingProducts
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
          ? _buildEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: t('no_favorite_products') ?? 'No favorite products yet',
              subtitle:
                  t('tap_heart_products') ??
                  'Tap the heart on products to add them',
            )
          : _isGridView
          ? _buildProductGrid()
          : _buildProductList(),
    );
  }

  Widget _buildProductGrid() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _favorites.map((product) {
          final pid = _productId(product);
          return ProductCard(
            product: product,
            onTap: () => _onProductTap(product),
            showFavorite: pid != null,
            isFavorite: true,
            onFavoriteToggle: () {
              if (pid != null) _removeFavorite(pid);
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _favorites.length,
      itemBuilder: (context, i) {
        final product = _favorites[i];
        final pid = _productId(product);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ProductListTile(
            product: product,
            onTap: () => _onProductTap(product),
            showFavorite: pid != null,
            isFavorite: true,
            onFavoriteToggle: () {
              if (pid != null) _removeFavorite(pid);
            },
          ),
        );
      },
    );
  }

  // ── Stores Tab ──
  Widget _buildStoresTab() {
    return RefreshIndicator(
      onRefresh: _loadFavoriteStores,
      child: _isLoadingStores
          ? const Center(child: CircularProgressIndicator())
          : _favoriteStores.isEmpty
          ? _buildEmptyState(
              icon: Icons.store_outlined,
              title: t('no_favorite_stores') ?? 'No favorite stores yet',
              subtitle:
                  t('tap_heart_stores') ??
                  'Tap the heart on stores to add them',
            )
          : _buildStoreList(),
    );
  }

  Widget _buildStoreList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _favoriteStores.length,
      itemBuilder: (context, i) {
        final store = _favoriteStores[i];
        final sid = _storeId(store);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: StoreListTile(
            store: store,
            onTap: () => _onStoreTap(store),
            showFavorite: sid != null,
            isFavorite: true,
            onFavoriteToggle: () {
              if (sid != null) _removeFavoriteStore(sid);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
