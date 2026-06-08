//stores_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../widgets/theme_toggle.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'store_products_screen.dart';
import 'my_store_screen.dart';
import 'store_map_screen.dart';
import '../lang/translations.dart';
import '../services/store_service.dart';
import '../models/models.dart';

class StoresScreen extends ConsumerStatefulWidget {
  const StoresScreen({super.key});

  @override
  ConsumerState<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends ConsumerState<StoresScreen> {
  List<Store> stores = [];
  bool isLoading = true;
  String error = '';
  bool _hasStoreAccess = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final data = await StoreService.fetchStores();
      // FIXED: Check store context (owner or accepted worker) instead of just role
      final hasAccess =
          await ApiService.isStoreOwner() || await ApiService.isStoreWorker();
      if (!mounted) return;
      setState(() {
        stores = data;
        _hasStoreAccess = hasAccess;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> openMap(double lat, double lng) async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('app_name')),
        actions: [
          // FIXED: Show My Store for both owner and accepted worker
          if (_hasStoreAccess)
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyStoreScreen()),
                );
              },
              icon: const Icon(Icons.inventory_2, color: Colors.white),
              label: Text(
                t('my_store'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          const ThemeToggle(),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
          ? Center(child: Text('${t('error')}: $error'))
          : ListView.builder(
              itemCount: stores.length,
              itemBuilder: (context, index) {
                final store = stores[index];

                final int storeId = store.intId ?? 0;

                final String storeName =
                    store.name ?? t('unknown_store');

                final String? storeImageUrl = store.imageUrl;

                final double? lat = store.lat;

                final double? lng = store.lng;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.store,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      storeName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${store.city ?? ''} - ${store.village ?? ''}\n${store.phone ?? ''}',
                    ),
                    isThreeLine: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StoreProductsScreen(
                            storeId: storeId,
                            storeName: storeName,
                          ),
                        ),
                      );
                    },
                    trailing: IconButton(
                      icon: Icon(
                        Icons.location_on,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: () {
                        if (lat != null && lng != null) {
                          final target = LatLng(lat, lng);

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StoreLocationView(
                                target: target,
                                targetStoreId: storeId,
                                targetName: storeName,
                                targetImageUrl: storeImageUrl,
                                stores: stores.map((s) => s.toJson()).toList(),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
