// lib/screens/my_store_screen.dart
// COMPLETE REPLACEMENT — adds checkout entry, low-stock badges, improved product cards

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../widgets/gradient_button.dart';
import 'add_product_screen.dart';
import 'checkout_screen.dart';
import 'order_history_screen.dart';
import '../lang/translations.dart';

class MyStoreScreen extends StatefulWidget {
  const MyStoreScreen({super.key});

  @override
  State<MyStoreScreen> createState() => _MyStoreScreenState();
}

class _MyStoreScreenState extends State<MyStoreScreen> {
  Map<String, dynamic>? store;
  List<dynamic> products = [];
  List<dynamic> lowStock = [];
  bool isLoading = true;
  bool isSyncing = false;
  int pendingCount = 0;
  File? _storeImage;
  bool _updatingImage = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final storeData = await ApiService.getMyStore();
      final productData = await ApiService.fetchProducts(storeData['id']);
      final pending = await OfflineService.pendingCount();
      List<dynamic> low = [];
      try {
        low = await ApiService.fetchLowStockProducts();
      } catch (_) {}
      setState(() {
        store = storeData;
        products = productData;
        lowStock = low;
        pendingCount = pending;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickStoreImage() async {
    final picker = ImagePicker();
    final picked = await showDialog<ImageSource>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('select_image_source')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: Text(t('camera')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: Text(t('gallery')),
          ),
        ],
      ),
    );
    if (picked == null) return;
    final file = await picker.pickImage(source: picked, maxWidth: 1024);
    if (file != null) {
      setState(() => _storeImage = File(file.path));
      await _updateStoreImage();
    }
  }

  Future<void> _updateStoreImage() async {
    if (_storeImage == null) return;
    setState(() => _updatingImage = true);
    try {
      final updated = await ApiService.updateMyStore(image: _storeImage);
      setState(() => store = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('shop_image_updated')), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _updatingImage = false);
    }
  }

  Future<void> syncPending() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('no_internet')), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isSyncing = true);
    try {
      final pending = await OfflineService.getPending();
      for (final item in pending) {
        try {
          await ApiService.createProduct(
            name: item['name'],
            price: item['price'],
            quantity: item['quantity'],
            description: item['description'],
            barcode: item['barcode'],
            image: item['image_paths'] != null && (item['image_paths'] as List).isNotEmpty
                ? File((item['image_paths'] as List).first)
                : null,
          );
          await OfflineService.removePending(item['id'] as int);
        } catch (e) {
          debugPrint('Sync failed for ${item['name']}: $e');
        }
      }
      await loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('sync_complete')), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('sync_error')}: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => isSyncing = false);
    }
  }

  Future<void> deleteProduct(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('delete_product')),
        content: Text(t('cannot_undo')),
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
    if (confirm != true) return;

    try {
      await ApiService.deleteProduct(id);
      loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  bool _isLowStock(dynamic product) {
    final qty = (product['quantity'] as num?)?.toInt() ?? 0;
    return qty <= 5 && qty >= 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(store?['name'] ?? t('my_store')),
        actions: [
          if (pendingCount > 0)
            Badge(
              label: Text('$pendingCount'),
              child: IconButton(
                icon: const Icon(Icons.sync),
                onPressed: isSyncing ? null : syncPending,
              ),
            )
          else
            IconButton(
              icon: isSyncing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync),
              onPressed: isSyncing ? null : syncPending,
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Shop image header
                GestureDetector(
                  onTap: _updatingImage ? null : _pickStoreImage,
                  child: Container(
                    width: double.infinity,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      image: (store?['image_url'] != null || _storeImage != null)
                          ? DecorationImage(
                              image: _storeImage != null
                                  ? FileImage(_storeImage!)
                                  : NetworkImage(store!['image_url']) as ImageProvider,
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: (store?['image_url'] == null && _storeImage == null)
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_photo_alternate, size: 48, color: Colors.white),
                              const SizedBox(height: 8),
                              Text(
                                t('tap_to_add_shop_image'),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          )
                        : _updatingImage
                            ? const Center(child: CircularProgressIndicator(color: Colors.white))
                            : const Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircleAvatar(
                                    backgroundColor: Colors.black54,
                                    child: Icon(Icons.edit, color: Colors.white, size: 20),
                                  ),
                                ),
                              ),
                  ),
                ),

                // Quick actions
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.point_of_sale,
                          label: t('checkout'),
                          color: theme.colorScheme.primary,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.receipt_long,
                          label: t('orders'),
                          color: theme.colorScheme.secondary,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.inventory_2,
                          label: t('low_stock'),
                          color: lowStock.isNotEmpty ? Colors.orange : theme.colorScheme.outline,
                          badge: lowStock.isNotEmpty ? '${lowStock.length}' : null,
                          onTap: () {
                            if (lowStock.isNotEmpty) {
                              showModalBottomSheet(
                                context: context,
                                builder: (_) => _LowStockSheet(products: lowStock),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                if (pendingCount > 0)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Text(
                        '$pendingCount ${t('pending_sync')}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                // Products list
                Expanded(
                  child: products.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 48, color: theme.colorScheme.outline),
                              const SizedBox(height: 8),
                              Text(t('no_products'), style: TextStyle(color: theme.colorScheme.outline)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final p = products[index];
                            final isLow = _isLowStock(p);
                            final hasBarcode = p['barcode'] != null && p['barcode'].toString().isNotEmpty;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 56,
                                        height: 56,
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        child: p['image_url'] != null
                                            ? Image.network(
                                                p['image_url'],
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 28),
                                              )
                                            : const Icon(Icons.inventory_2, size: 28),
                                      ),
                                    ),
                                    if (isLow)
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            t('low'),
                                            style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p['name'],
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (hasBarcode)
                                      Icon(Icons.qr_code, size: 14, color: theme.colorScheme.primary),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${p['price']} SYP • ${t('qty')}: ${p['quantity']}'),
                                    if (isLow)
                                      Text(
                                        t('low_stock_warning'),
                                        style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => AddProductScreen(product: p)),
                                        );
                                        loadData();
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => deleteProduct(p['id']),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddProductScreen()),
          );
          loadData();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                Icon(icon, color: color),
                if (badge != null)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(badge!, style: const TextStyle(fontSize: 9, color: Colors.white), textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _LowStockSheet extends StatelessWidget {
  final List<dynamic> products;
  const _LowStockSheet({required this.products});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Text(t('low_stock_items'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: products.length,
              itemBuilder: (_, i) {
                final p = products[i];
                return ListTile(
                  leading: const Icon(Icons.inventory_2, color: Colors.orange),
                  title: Text(p['name']?.toString() ?? ''),
                  trailing: Chip(
                    label: Text('${p['quantity']}'),
                    backgroundColor: Colors.orange.shade50,
                    side: BorderSide(color: Colors.orange.shade200),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
