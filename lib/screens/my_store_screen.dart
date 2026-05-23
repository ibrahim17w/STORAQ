//my_store_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../widgets/gradient_button.dart';
import 'add_product_screen.dart';
import '../lang/translations.dart';

class MyStoreScreen extends StatefulWidget {
  const MyStoreScreen({super.key});

  @override
  State<MyStoreScreen> createState() => _MyStoreScreenState();
}

class _MyStoreScreenState extends State<MyStoreScreen> {
  Map<String, dynamic>? store;
  List<dynamic> products = [];
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
      setState(() {
        store = storeData;
        products = productData;
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
        title: const Text('Select Image'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Camera'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Gallery'),
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
        const SnackBar(
          content: Text('Shop image updated'),
          backgroundColor: Colors.green,
        ),
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
        const SnackBar(
          content: Text('No internet connection'),
          backgroundColor: Colors.orange,
        ),
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
            image: item['image_path'] != null ? File(item['image_path']) : null,
          );
          await OfflineService.removePending(item['id'] as int);
        } catch (e) {
          print('Sync failed for ${item['name']}: $e');
        }
      }
      await loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync complete!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red,
          ),
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
        title: const Text('Delete Product?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(store?['name'] ?? 'My Store'),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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
                      image:
                          (store?['image_url'] != null || _storeImage != null)
                          ? DecorationImage(
                              image: _storeImage != null
                                  ? FileImage(_storeImage!)
                                  : NetworkImage(store!['image_url'])
                                        as ImageProvider,
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: (store?['image_url'] == null && _storeImage == null)
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate,
                                size: 48,
                                color: Colors.white,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Tap to add shop image',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        : _updatingImage
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        : const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                child: Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                if (pendingCount > 0)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Text(
                        '$pendingCount items pending sync',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: products.isEmpty
                      ? const Center(
                          child: Text('No products yet. Tap + to add.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final p = products[index];
                            return Card(
                              child: ListTile(
                                leading: p['image_url'] != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          p['image_url'],
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.image, size: 40),
                                        ),
                                      )
                                    : const Icon(Icons.inventory_2, size: 40),
                                title: Text(
                                  p['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${p['price']} SYP • Qty: ${p['quantity']}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AddProductScreen(product: p),
                                          ),
                                        );
                                        loadData();
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
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
