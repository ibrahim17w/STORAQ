// lib/screens/main_nav_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lang/translations.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'explore_screen.dart';
import 'map_screen.dart';
import 'favorites_screen.dart';
import 'profile_screen.dart';
import 'analytics_screen.dart';
import 'store_products_screen.dart';
import '../services/deep_link_service.dart';

class MainNavScreen extends ConsumerStatefulWidget {
  const MainNavScreen({super.key});

  @override
  ConsumerState<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends ConsumerState<MainNavScreen> {
  int _currentIndex = 0;
  bool _isStoreOwner = false;

  /// Only tabs the user has opened are built — avoids launching 5–6 screens at once.
  final Map<int, Widget> _tabCache = {
    0: const HomeScreen(key: ValueKey('nav_home')),
  };

  @override
  void initState() {
    super.initState();
    DeepLinkService.pendingStoreIdNotifier.addListener(_onDeepLinkEvent);
    Future.microtask(_checkStoreOwner);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingDeepLink());
  }

  @override
  void dispose() {
    DeepLinkService.pendingStoreIdNotifier.removeListener(_onDeepLinkEvent);
    super.dispose();
  }

  void _onDeepLinkEvent() {
    _handlePendingDeepLink();
  }

  void _handlePendingDeepLink() {
    final storeId = DeepLinkService.consumePendingStoreId();
    if (storeId == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(storeId: storeId),
      ),
    );
  }

  Future<void> _checkStoreOwner() async {
    final isOwner = await ApiService.isStoreOwner();
    if (!mounted || isOwner == _isStoreOwner) return;
    setState(() {
      _isStoreOwner = isOwner;
      final current = _currentIndex;
      _tabCache
        ..clear()
        ..[current] = _buildScreen(current);
    });
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) {
      if (index == 0) homeSponsoredRefreshTick.value++;
      return;
    }
    setState(() {
      _currentIndex = index;
      _tabCache.putIfAbsent(index, () => _buildScreen(index));
    });
    if (index == 0) homeSponsoredRefreshTick.value++;
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const HomeScreen(key: ValueKey('nav_home'));
      case 1:
        return const ExploreScreen(key: ValueKey('nav_explore'));
      case 2:
        return const MapScreen(key: ValueKey('nav_map'));
      case 3:
        if (_isStoreOwner) {
          return const AnalyticsScreen(key: ValueKey('nav_analytics'));
        }
        return const FavoritesScreen(key: ValueKey('nav_favorites'));
      case 4:
        if (_isStoreOwner) {
          return const FavoritesScreen(key: ValueKey('nav_favorites'));
        }
        return const ProfileScreen(key: ValueKey('nav_profile'));
      case 5:
        return const ProfileScreen(key: ValueKey('nav_profile'));
      default:
        return const SizedBox.shrink();
    }
  }

  static const _ownerTabs = [
    _NavTab(Icons.home_outlined, Icons.home_rounded, 'home', 'Home'),
    _NavTab(Icons.search_outlined, Icons.search_rounded, 'explore', 'Explore'),
    _NavTab(Icons.map_outlined, Icons.map_rounded, 'map', 'Map'),
    _NavTab(
      Icons.analytics_outlined,
      Icons.analytics_rounded,
      'analytics',
      'Analytics',
    ),
    _NavTab(
      Icons.favorite_outline,
      Icons.favorite_rounded,
      'favorites',
      'Favorites',
    ),
    _NavTab(Icons.person_outline, Icons.person_rounded, 'profile', 'Profile'),
  ];

  static const _guestTabs = [
    _NavTab(Icons.home_outlined, Icons.home_rounded, 'home', 'Home'),
    _NavTab(Icons.search_outlined, Icons.search_rounded, 'explore', 'Explore'),
    _NavTab(Icons.map_outlined, Icons.map_rounded, 'map', 'Map'),
    _NavTab(
      Icons.favorite_outline,
      Icons.favorite_rounded,
      'favorites',
      'Favorites',
    ),
    _NavTab(Icons.person_outline, Icons.person_rounded, 'profile', 'Profile'),
  ];

  List<_NavTab> get _tabs => _isStoreOwner ? _ownerTabs : _guestTabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          for (final entry in _tabCache.entries)
            Offstage(
              offstage: entry.key != _currentIndex,
              child: TickerMode(
                enabled: entry.key == _currentIndex,
                child: entry.value,
              ),
            ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: List.generate(_tabs.length, (index) {
                final tab = _tabs[index];
                final selected = _currentIndex == index;
                return Expanded(
                  child: InkWell(
                    onTap: () => _onTabSelected(index),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selected ? tab.selectedIcon : tab.icon,
                            size: 22,
                            color: selected ? primary : muted,
                          ),
                          const SizedBox(height: 4),
                          if (selected)
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: primary,
                                shape: BoxShape.circle,
                              ),
                            )
                          else
                            const SizedBox(height: 4),
                          const SizedBox(height: 2),
                          Text(
                            t(tab.labelKey) ?? tab.fallback,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.1,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                              color: selected ? primary : muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab {
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final String fallback;

  const _NavTab(
    this.icon,
    this.selectedIcon,
    this.labelKey,
    this.fallback,
  );
}
