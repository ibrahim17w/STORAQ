// lib/screens/store_products_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/analytics_service.dart';
import '../lang/translations.dart';
import '../widgets/cached_image.dart';
import '../widgets/product/product_list_tile.dart';
import '../utils/product_store_helper.dart';
import 'store_map_screen.dart';
import 'product_detail_screen.dart';
import '../services/store_service.dart';
import '../services/product_service.dart';
import '../providers/viewer_currency_provider.dart';
import '../models/models.dart';
import '../widgets/reviews_section.dart';
import '../services/review_service.dart';

class StoreProductsScreen extends ConsumerStatefulWidget {
  final int storeId;
  final String? storeName;
  const StoreProductsScreen({super.key, required this.storeId, this.storeName});

  @override
  ConsumerState<StoreProductsScreen> createState() =>
      _StoreProductsScreenState();
}

class _StoreProductsScreenState extends ConsumerState<StoreProductsScreen> {
  List<Product> products = [];
  bool isLoading = true;
  String error = '';
  String _displayName = '';
  Store? _storeData;

  Map<String, dynamic> _productMap(Product product) {
    final map = product.toJson();
    if (_storeData != null) {
      map['shop_name'] ??= _storeData!.name;
      map['store_id'] ??= widget.storeId;
      map['shop_id'] ??= widget.storeId;
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    _displayName = widget.storeName ?? '';
    loadData();
    _trackVisit();
  }

  Future<void> _trackVisit() async {
    try {
      await AnalyticsService.trackStoreVisit(widget.storeId);
    } catch (_) {}
  }

  Future<void> loadData() async {
    try {
      final storeData = await StoreService.fetchStore(widget.storeId);
      _storeData = storeData;
      if (_displayName.isEmpty) {
        _displayName = storeData.name ?? t('store');
      }

      final data = await ProductService.fetchProducts(widget.storeId);
      setState(() {
        products = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  void _openProduct(Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: productToDetailMap(_productMap(product)),
        ),
      ),
    );
  }

  void _openOnMap() {
    final lat = _storeData?.lat;
    final lng = _storeData?.lng;
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('location_not_available'))),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreLocationView(
          target: LatLng(lat, lng),
          targetStoreId: widget.storeId,
          targetName:
              _displayName.isNotEmpty ? _displayName : _storeData?.name,
          targetImageUrl: _storeData?.imageUrl,
          stores: _storeData != null ? [_storeData!.toJson()] : [],
        ),
      ),
    );
  }

  Widget _buildStoreHeader(ThemeData theme) {
    final store = _storeData;
    if (store == null) return const SizedBox.shrink();

    final city = store.city ?? '';
    final country = store.country ?? '';
    final location = [city, country]
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
    final hasLocation = store.lat != null && store.lng != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedAppImage(
              imageUrl: store.imageUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              memCacheWidth: 120,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (location.isNotEmpty)
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  '${products.length} ${t('products') ?? 'products'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (store.rating != null || (store.reviewCount ?? 0) > 0)
                  Row(
                    children: [
                      Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '${(store.rating ?? 5.0).toStringAsFixed(1)} (${store.reviewCount ?? 0})',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (hasLocation)
            OutlinedButton.icon(
              onPressed: _openOnMap,
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: Text(t('map') ?? 'Map'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _displayName.isNotEmpty ? _displayName : t('store'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(child: Text('${t('error')}: $error'))
              : products.isEmpty
                  ? RefreshIndicator(
                      onRefresh: loadData,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        children: [
                          _buildStoreHeader(Theme.of(context)),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(t('no_products_yet')),
                            ),
                          ),
                          ReviewsSection(
                            type: ReviewTargetType.store,
                            targetId: widget.storeId,
                            targetName: _displayName,
                            initialRating: _storeData?.rating,
                            initialReviewCount: _storeData?.reviewCount,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: loadData,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: products.length + 2,
                        separatorBuilder: (_, i) =>
                            SizedBox(height: i == 0 ? 8 : 10),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildStoreHeader(Theme.of(context));
                          }
                          if (index == products.length + 1) {
                            return ReviewsSection(
                              type: ReviewTargetType.store,
                              targetId: widget.storeId,
                              targetName: _displayName,
                              initialRating: _storeData?.rating,
                              initialReviewCount: _storeData?.reviewCount,
                            );
                          }
                          final product = products[index - 1];
                          final map = _productMap(product);
                          return ProductListTile(
                            product: map,
                            compact: true,
                            currencySettings:
                                ref.watch(viewerCurrencyProvider).currencySettings,
                            onTap: () => _openProduct(product),
                          );
                        },
                      ),
                    ),
    );
  }
}
