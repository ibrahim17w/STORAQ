// lib/screens/store_products_screen.dart
// FIXED: Image resolution now uses centralized CachedAppImage widget
// to properly display cached local images when offline.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../widgets/cached_image.dart';
import 'store_map_screen.dart';
import '../services/store_service.dart';
import '../services/location_service.dart';
import '../services/product_service.dart';
import '../services/offline_service.dart';

class StoreProductsScreen extends StatefulWidget {
  final int storeId;
  final String? storeName;
  const StoreProductsScreen({super.key, required this.storeId, this.storeName});

  @override
  State<StoreProductsScreen> createState() => _StoreProductsScreenState();
}

class _StoreProductsScreenState extends State<StoreProductsScreen> {
  List<dynamic> products = [];
  bool isLoading = true;
  String error = '';
  String _displayName = '';
  Map<String, dynamic>? _storeData;

  @override
  void initState() {
    super.initState();
    _displayName = widget.storeName ?? '';
    loadData();
  }

  Future<void> loadData() async {
    try {
      final storeData = await StoreService.fetchStore(widget.storeId);
      _storeData = storeData;
      if (_displayName.isEmpty) {
        _displayName = storeData['name'] ?? t('store');
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

  void _openOnMap() {
    final lat = double.tryParse(_storeData?['lat']?.toString() ?? '');
    final lng = double.tryParse(_storeData?['lng']?.toString() ?? '');
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Location not available')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreLocationView(
          target: LatLng(lat, lng),
          targetStoreId: widget.storeId,
          targetName: _displayName.isNotEmpty
              ? _displayName
              : _storeData?['name'],
          targetImageUrl: _storeData?['image_url']?.toString(),
          stores: _storeData != null ? [_storeData!] : [],
        ),
      ),
    );
  }

  // CRITICAL FIX: Use CachedAppImage which properly handles all image types
  Widget _buildProductImage(Map<String, dynamic> product) {
    final imagePaths = OfflineService.getProductImagePaths(product);
    final firstPath = imagePaths.isNotEmpty ? imagePaths.first : null;

    return CachedAppImage(
      imageUrl: firstPath,
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      placeholder: Container(
        height: 180,
        color: Colors.grey.shade800,
        child: const Icon(Icons.image_not_supported, size: 50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation =
        _storeData?['lat'] != null && _storeData?['lng'] != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName.isNotEmpty ? _displayName : t('store')),
        actions: [
          if (hasLocation)
            IconButton(
              icon: const Icon(Icons.location_on),
              tooltip: 'View on map',
              onPressed: _openOnMap,
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
          ? Center(child: Text('Error: $error'))
          : products.isEmpty
          ? const Center(child: Text('No products yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final p = products[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: _buildProductImage(p),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p['name'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (p['description'] != null)
                              Text(
                                p['description'],
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${p['price']} SYP',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (p['quantity'] ?? 0) > 0
                                        ? Colors.green.shade100
                                        : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${p['quantity'] ?? 0} in stock',
                                    style: TextStyle(
                                      color: (p['quantity'] ?? 0) > 0
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (p['barcode'] != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.qr_code, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Barcode: ${p['barcode']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
