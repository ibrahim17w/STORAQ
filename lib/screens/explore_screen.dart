import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import 'store_products_screen.dart';
import 'store_map_screen.dart';
import 'package:latlong2/latlong.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<dynamic> _stores = [];
  List<dynamic> _filtered = [];
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      final stores = await ApiService.fetchStores();
      if (mounted) {
        setState(() {
          _stores = stores;
          _filtered = stores;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearch(String query) {
    setState(() {
      _filtered = _stores.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final city = (s['city'] ?? '').toString().toLowerCase();
        return name.contains(query.toLowerCase()) ||
            city.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: TextField(
            controller: _searchCtrl,
            onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: t('search'),
              border: InputBorder.none,
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          actions: [
            if (_searchCtrl.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearch('');
                },
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _filtered.length,
                itemBuilder: (context, i) {
                  final store = _filtered[i];
                  final lat = double.tryParse(store['lat']?.toString() ?? '');
                  final lng = double.tryParse(store['lng']?.toString() ?? '');
                  final hasLocation = lat != null && lng != null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.store)),
                      title: Text(store['name'] ?? ''),
                      subtitle: Text(
                        '${store['city'] ?? ''}, ${store['country'] ?? ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasLocation)
                            IconButton(
                              icon: const Icon(Icons.map, size: 20),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StoreLocationView(
                                    target: LatLng(lat, lng),
                                    targetStoreId: store['id'], // CHANGED
                                    targetName: store['name']
                                        ?.toString(), // CHANGED
                                    targetImageUrl: store['image_url']
                                        ?.toString(), // CHANGED
                                    stores: _stores, // CHANGED
                                  ),
                                ),
                              ),
                            ),
                          const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              StoreProductsScreen(storeId: store['id']),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
