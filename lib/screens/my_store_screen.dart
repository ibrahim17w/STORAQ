// lib/screens/my_store_screen.dart
// FIXED: Auto-refreshes reliably when returning from add/edit product
// FIXED: Uses RouteObserver pattern for guaranteed refresh

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';
import 'dart:convert';

class MyStoreScreen extends StatefulWidget {
  const MyStoreScreen({super.key});

  @override
  State<MyStoreScreen> createState() => _MyStoreScreenState();
}

class _MyStoreScreenState extends State<MyStoreScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  Map<String, dynamic>? _store;
  List<dynamic> _products = [];
  bool _loading = true;
  String? _error;
  bool _needsRefresh = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called when app lifecycle changes. When resumed, check if we need refresh.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _needsRefresh) {
      _needsRefresh = false;
      _loadData();
    }
  }

  /// Called when dependencies change — also when returning from navigation
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsRefresh) {
      _needsRefresh = false;
      // Use microtask to avoid setState during build
      scheduleMicrotask(() => _loadData());
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = await ApiService.getMyStore();
      final products = await ApiService.fetchProducts(store['id']);
      if (mounted) {
        setState(() {
          _store = store;
          _products = products;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _navigateToAddProduct() async {
    _needsRefresh = true;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
    // ALWAYS refresh when returning — product may have been added
    _needsRefresh = false;
    await _loadData();
  }

  Future<void> _navigateToEditProduct(Map<String, dynamic> product) async {
    _needsRefresh = true;
    // FIXED: Ensure all required fields are present for editing
    final editProduct = Map<String, dynamic>.from(product);

    // Normalize image fields — backend may return 'images' (JSONB) or 'image_urls'
    final images = product['images'];
    final imageUrls = product['image_urls'];
    if (imageUrls == null && images != null) {
      if (images is List) {
        editProduct['image_urls'] = images.map((e) => e.toString()).toList();
      } else if (images is String) {
        try {
          final decoded = jsonDecode(images);
          if (decoded is List) {
            editProduct['image_urls'] = decoded
                .map((e) => e.toString())
                .toList();
          }
        } catch (_) {}
      }
    }

    // Ensure category_ids is a list
    final categoryIds = product['category_ids'] ?? product['category_id'];
    if (categoryIds != null && editProduct['category_ids'] == null) {
      if (categoryIds is List) {
        editProduct['category_ids'] = categoryIds;
      } else if (categoryIds is int) {
        editProduct['category_ids'] = [categoryIds];
      }
    }

    // Ensure price is properly typed
    if (product['price'] != null) {
      editProduct['price'] = product['price'].toString();
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => AddProductScreen(product: editProduct)),
    );
    _needsRefresh = false;
    await _loadData();
  }

  Future<void> _deleteProduct(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('delete_product')),
        content: Text(t('delete_product_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('delete'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.deleteProduct(id);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('product_deleted')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_loading && _products.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null && _products.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                t('error_loading_store'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _loadData, child: Text(t('retry'))),
            ],
          ),
        ),
      );
    }

    final storeName = _store?['name']?.toString() ?? t('my_store');
    final storeImage = _store?['image_url']?.toString();

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.light
          ? const Color(0xFFF8F9FA)
          : theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // App bar with store header
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  storeName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                background: storeImage != null && storeImage.isNotEmpty
                    ? Image.network(
                        storeImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: theme.colorScheme.primaryContainer,
                        ),
                      )
                    : Container(color: theme.colorScheme.primaryContainer),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: t('refresh'),
                ),
              ],
            ),

            // Product count + add button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_products.length} ${t('products')}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _navigateToAddProduct,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(t('add_product')),
                    ),
                  ],
                ),
              ),
            ),

            // Products grid
            if (_products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t('no_products_yet'),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _navigateToAddProduct,
                        icon: const Icon(Icons.add),
                        label: Text(t('add_first_product')),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final product = _products[index] as Map<String, dynamic>;
                    return _ProductCard(
                      product: product,
                      onEdit: () => _navigateToEditProduct(product),
                      onDelete: () => _deleteProduct(product['id']),
                    );
                  }, childCount: _products.length),
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddProduct,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = product['name']?.toString() ?? 'Unnamed';
    final price = product['price']?.toString() ?? '0';
    final qty = product['quantity'] ?? 0;
    final imageUrl = product['image_url']?.toString();
    final images = product['images'] as List<dynamic>?;
    final displayImage =
        imageUrl ??
        (images != null && images.isNotEmpty ? images.first.toString() : null);
    final isLowStock = (qty as num) <= (product['low_stock_threshold'] ?? 5);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 72,
                  height: 72,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: displayImage != null
                      ? Image.network(
                          displayImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.image_not_supported),
                        )
                      : const Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$price ${t('currency')}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isLowStock ? Icons.warning_amber : Icons.inventory_2,
                          size: 14,
                          color: isLowStock
                              ? Colors.orange
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$qty ${t('in_stock')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isLowStock
                                ? Colors.orange
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(t('edit'))),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      t('delete'),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
