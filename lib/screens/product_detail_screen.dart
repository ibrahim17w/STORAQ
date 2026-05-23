//product_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../widgets/cached_image.dart';
import 'store_map_screen.dart'; // Already correct
import 'store_products_screen.dart';

/// Product Detail Screen — shows a single product with its shop info and map link.
class ProductDetailScreen extends StatefulWidget {
  final dynamic product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Map<String, dynamic>? _storeData;
  bool _loadingStore = true;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    final shopId = widget.product['shop_id'];
    if (shopId == null) {
      setState(() => _loadingStore = false);
      return;
    }
    try {
      final store = await ApiService.fetchStore(shopId);
      if (mounted) {
        setState(() {
          _storeData = store;
          _loadingStore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStore = false);
    }
  }

  void _openStoreOnMap() {
    final lat = double.tryParse(_storeData?['lat']?.toString() ?? '');
    final lng = double.tryParse(_storeData?['lng']?.toString() ?? '');
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Location not available')));
      return;
    }
    // CHANGED: pass store data properly
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreLocationView(
          target: LatLng(lat, lng),
          targetStoreId: widget.product['shop_id'],
          targetName: _storeData?['name'],
          targetImageUrl: _storeData?['image_url']?.toString(),
          stores: _storeData != null ? [_storeData!] : [],
        ),
      ),
    );
  }

  void _openStorePage() {
    final shopId = widget.product['shop_id'];
    if (shopId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(
          storeId: shopId,
          storeName: _storeData?['name'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final hasLocation =
        _storeData?['lat'] != null && _storeData?['lng'] != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          p['name'] ?? t('product_name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Product Image ──
            CachedAppImage(
              imageUrl: p['image_url'],
              width: double.infinity,
              height: 280,
              fit: BoxFit.cover,
              memCacheWidth: 600,
            ),

            // ── Product Info ──
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['name'] ?? '',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (p['description'] != null &&
                      p['description'].toString().isNotEmpty)
                    Text(
                      p['description'].toString(),
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '\$${p['price'] ?? 0}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: (p['quantity'] ?? 0) > 0
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${p['quantity'] ?? 0} ${t('in_stock')}',
                          style: TextStyle(
                            color: (p['quantity'] ?? 0) > 0
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (p['barcode'] != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.qr_code,
                          size: 18,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${t('barcode')}: ${p['barcode']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Shop Info Section ──
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('store'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingStore)
                    const Center(child: CircularProgressIndicator())
                  else if (_storeData == null)
                    Text(
                      p['shop_name'] ?? t('store'),
                      style: const TextStyle(fontSize: 16),
                    )
                  else
                    InkWell(
                      onTap: _openStorePage,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            CachedAppImage(
                              imageUrl: _storeData!['image_url'],
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              memCacheWidth: 150,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _storeData!['name'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_storeData!['city'] ?? ''}, ${_storeData!['country'] ?? ''}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (hasLocation)
                              IconButton(
                                icon: Icon(
                                  Icons.location_on,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: 'View on map',
                                onPressed: _openStoreOnMap,
                              ),
                          ],
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
