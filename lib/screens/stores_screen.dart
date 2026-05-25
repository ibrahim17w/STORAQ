//stores_screen.dart
import 'package:flutter/material.dart';
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

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  List<dynamic> stores = [];
  bool isLoading = true;
  String error = '';
  String? userRole;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final data = await ApiService.fetchStores();
      final role = await ApiService.getUserRole();
      setState(() {
        stores = data;
        userRole = role;
        isLoading = false;
      });
    } catch (e) {
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
        title: const Text('Market Bridge'),
        actions: [
          if (userRole == 'store_owner')
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyStoreScreen()),
                );
              },
              icon: const Icon(Icons.inventory_2, color: Colors.white),
              label: const Text(
                'My Store',
                style: TextStyle(color: Colors.white),
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
          ? Center(child: Text('Error: $error'))
          : ListView.builder(
              itemCount: stores.length,
              itemBuilder: (context, index) {
                final store = stores[index];

                // FIX: always parse ID safely
                final int storeId = int.tryParse(store['id'].toString()) ?? 0;

                final String storeName =
                    store['name']?.toString() ?? 'Unknown Store';

                final String? storeImageUrl = store['image_url']?.toString();

                final double? lat = store['lat'] != null
                    ? double.tryParse(store['lat'].toString())
                    : null;

                final double? lng = store['lng'] != null
                    ? double.tryParse(store['lng'].toString())
                    : null;

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
                      '${store['city']} - ${store['village']}\n${store['phone'] ?? ''}',
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
                                stores: stores, // CHANGED: pass the full list
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
