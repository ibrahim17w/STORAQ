// lib/screens/main_nav_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../lang/translations.dart';
import '../services/product_service.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'explore_screen.dart';
import 'map_screen.dart';
import 'favorites_screen.dart';
import 'profile_screen.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _currentIndex = 0;
  bool _wasOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  final _screens = const [
    HomeScreen(),
    ExploreScreen(),
    MapScreen(),
    FavoritesScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _wasOffline = result.contains(ConnectivityResult.none);

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOffline = results.contains(ConnectivityResult.none);
      if (_wasOffline && !isOffline) {
        // Came back online — auto-sync pending changes
        _autoSync();
      }
      _wasOffline = isOffline;
    });
  }

  Future<void> _autoSync() async {
    try {
      final storeId = await ApiService.getMyStoreId();
      if (storeId != null) {
        await ProductService.syncPendingChanges(storeId);
      }
    } catch (e) {
      // Silent fail — user can manually sync if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: t('home') ?? 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.search_outlined),
            selectedIcon: const Icon(Icons.search),
            label: t('explore') ?? 'Explore',
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: t('map') ?? 'Map',
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_outline),
            selectedIcon: const Icon(Icons.favorite),
            label: t('favorites') ?? 'Favorites',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: t('profile') ?? 'Profile',
          ),
        ],
      ),
    );
  }
}
