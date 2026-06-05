// lib/screens/favorites_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/favorites_service.dart';
import '../lang/translations.dart';
import '../widgets/guest_login_sheet.dart';
import '../widgets/product/product_card.dart';
import '../widgets/product/product_list_tile.dart';
import 'product_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<dynamic> _favorites = [];
  bool _isLoading = true;
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    try {
      final items = await FavoritesService.fetchFavorites();
      if (mounted) {
        setState(() {
          _favorites = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onProductTap(dynamic product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  Future<void> _removeFavorite(int productId) async {
    await FavoritesService.removeFavorite(productId);
    await _loadFavorites();
  }

  int? _productId(dynamic product) {
    final id = product['id'];
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
            actions: [
              IconButton(
                icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                onPressed: () => setState(() => _isGridView = !_isGridView),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadFavorites,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _favorites.isEmpty
                ? _buildEmptyState()
                : _isGridView
                ? _buildGrid()
                : _buildList(),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            t('no_favorites') ?? 'No favorites yet',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('tap_heart_to_add') ?? 'Tap the heart on products to add them',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
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

  Widget _buildList() {
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
}
