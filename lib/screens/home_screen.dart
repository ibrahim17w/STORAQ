//home_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../providers/locale_provider.dart';
import '../widgets/app_notification.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/cached_image.dart';
import '../utils/location_helper.dart';
import 'store_products_screen.dart';
import 'product_detail_screen.dart';
import 'login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';

String _tr(String key, {required String fallback}) {
  final result = t(key);
  // If t() returns null or the raw key itself, use the fallback
  if (result == null || result == key) return fallback;
  return result;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _products = [];
  List<dynamic> _stores = [];
  List<dynamic> _trendingProducts = [];
  List<dynamic> _sponsoredStores = [];
  List<dynamic> _apiRecommendations = [];
  List<dynamic> _recommendedProducts = [];
  bool _productsLoading = true;
  bool _storesLoading = true;
  bool _trendingLoading = true;
  bool _sponsoredLoading = true;
  bool _recommendationsLoading = true;
  String _userName = '';
  bool _isGridView = true;

  // ── Location filter state ──
  Position? _userPosition;
  String _locationFilterMode = 'all'; // 'all', 'village', 'city', 'country'
  String? _userVillage;
  String? _userCity;
  String? _userCountry;
  double? _distanceFilterKm; // separate distance filter: 5, 10, 20, 50
  bool _locationLoading = false;

  // ── Canonical location IDs (NEW) ──
  String? _userCityId;
  String? _userVillageId;
  String? _userCountryCode;

  // ── Guest mode ──
  bool _isGuest = false;

  // ── Price filter state ──
  // FIXED: Start from 0, use double.infinity for unlimited max
  double _selectedMinPrice = 0;
  double _selectedMaxPrice = double.infinity;

  // ── Category filter state ──
  String? _selectedCategory;
  final List<String> _categories = [
    'Electronics',
    'Clothing',
    'Food',
    'Books',
    'Home',
    'Sports',
    'Other',
  ];

  // ── Rating filter ──
  double _minRating = 0;

  // ── Sort option ──
  String _sortBy = 'newest'; // newest, price_low, price_high, popular

  static final List<String> _pendingViews = [];
  static Timer? _viewFlushTimer;

  @override
  void initState() {
    super.initState();
    _loadGuestStatus();
    _loadGridPreference();
    _loadFilterPreferences();
    _loadUserName();
    _initLocation();
    _loadProducts();
    _loadStores();
    _loadTrending();
    _loadSponsored();
    _loadRecommendations();
  }

  Future<void> _loadGridPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _isGridView = prefs.getBool('home_grid_view') ?? true);
  }

  Future<void> _loadGuestStatus() async {
    final isGuest = await ApiService.isGuest();
    final isLoggedIn = await ApiService.isLoggedIn();
    if (mounted) setState(() => _isGuest = isGuest && !isLoggedIn);
  }

  Future<bool> _requireAuth() async {
    final isGuest = await ApiService.isGuest();
    final isLoggedIn = await ApiService.isLoggedIn();
    if (!isGuest || isLoggedIn) return true;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GuestAuthSheet(),
    );
    return result == true;
  }

  Future<void> _loadFilterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _locationFilterMode =
            prefs.getString('home_location_filter_mode') ?? 'all';

        // Migrate old 'radius' mode to the new separate distance filter
        if (_locationFilterMode == 'radius') {
          _locationFilterMode = 'all';
          _distanceFilterKm = prefs.getDouble('home_filter_radius') ?? 5.0;
        }

        _distanceFilterKm = prefs.containsKey('home_distance_filter_km')
            ? prefs.getDouble('home_distance_filter_km')
            : _distanceFilterKm;

        _selectedMinPrice = prefs.getDouble('home_min_price') ?? 0;
        // FIXED: Load infinity if saved as special value
        final savedMax = prefs.getDouble('home_max_price');
        _selectedMaxPrice = savedMax == null || savedMax >= 999999999
            ? double.infinity
            : savedMax;
        _selectedCategory = prefs.getString('home_category');
        _minRating = prefs.getDouble('home_min_rating') ?? 0;
        _sortBy = prefs.getString('home_sort_by') ?? 'newest';

        // NEW: Load canonical location IDs
        _userCityId = prefs.getString('home_city_id');
        _userVillageId = prefs.getString('home_village_id');
        _userCountryCode = prefs.getString('home_country_code');
      });
    }
  }

  Future<void> _saveFilterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_location_filter_mode', _locationFilterMode);

    if (_distanceFilterKm != null) {
      await prefs.setDouble('home_distance_filter_km', _distanceFilterKm!);
    } else {
      await prefs.remove('home_distance_filter_km');
    }
    // Clean up legacy radius preference
    await prefs.remove('home_filter_radius');

    await prefs.setDouble('home_min_price', _selectedMinPrice);
    // FIXED: Save infinity as sentinel value
    await prefs.setDouble(
      'home_max_price',
      _selectedMaxPrice == double.infinity ? 999999999 : _selectedMaxPrice,
    );
    if (_selectedCategory != null) {
      await prefs.setString('home_category', _selectedCategory!);
    } else {
      await prefs.remove('home_category');
    }
    await prefs.setDouble('home_min_rating', _minRating);
    await prefs.setString('home_sort_by', _sortBy);

    // NEW: Save canonical location IDs
    if (_userCityId != null) {
      await prefs.setString('home_city_id', _userCityId!);
    } else {
      await prefs.remove('home_city_id');
    }
    if (_userVillageId != null) {
      await prefs.setString('home_village_id', _userVillageId!);
    } else {
      await prefs.remove('home_village_id');
    }
    if (_userCountryCode != null) {
      await prefs.setString('home_country_code', _userCountryCode!);
    } else {
      await prefs.remove('home_country_code');
    }
  }

  Future<void> _toggleViewMode() async {
    final newMode = !_isGridView;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('home_grid_view', newMode);
    setState(() => _isGridView = newMode);
  }

  // ── Location ──
  Future<void> _initLocation() async {
    setState(() => _locationLoading = true);
    final pos = await LocationHelper.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _userPosition = pos;
      _locationLoading = false;
    });
    // Infer village / city / country from nearby stores
    if (pos != null && _stores.isNotEmpty) {
      _inferUserLocationFromStores();
    }

    // If we couldn't resolve any place name, default to the smallest distance
    if (pos != null &&
        _userVillage == null &&
        _userCity == null &&
        _userCountry == null) {
      if (mounted && _distanceFilterKm == null) {
        setState(() => _distanceFilterKm = 5.0);
        _saveFilterPreferences();
      }
    }
  }

  void _inferUserLocationFromStores() {
    if (_userPosition == null || _stores.isEmpty) return;
    final uLat = _userPosition!.latitude;
    final uLng = _userPosition!.longitude;

    // ── NEW: Try canonical reverse geocoding first ──
    _reverseGeocodeUserLocation(uLat, uLng);

    // Fallback: infer from nearby stores if geocoding fails
    final List<dynamic> villageStores = [];
    final List<dynamic> closeStores = [];
    final List<dynamic> regionStores = [];
    dynamic nearest;
    double minDist = double.infinity;

    for (final store in _stores) {
      final sLat = store['lat'];
      final sLng = store['lng'];
      if (sLat == null || sLng == null) continue;
      final lat = sLat is num
          ? sLat.toDouble()
          : double.tryParse(sLat.toString());
      final lng = sLng is num
          ? sLng.toDouble()
          : double.tryParse(sLng.toString());
      if (lat == null || lng == null) continue;
      final d = LocationHelper.distanceKm(uLat, uLng, lat, lng);
      if (d < minDist) {
        minDist = d;
        nearest = store;
      }
      if (d <= 3.0)
        villageStores.add(store);
      else if (d <= 8.0)
        closeStores.add(store);
      else if (d <= 25.0)
        regionStores.add(store);
    }

    // Only use store-based inference if canonical geocoding didn't set values
    if (_userCityId == null) {
      String? bestCity = _mostCommonField(villageStores, 'city');
      if (bestCity == null) bestCity = _mostCommonField(closeStores, 'city');
      if (bestCity == null) bestCity = _mostCommonField(regionStores, 'city');
      if (bestCity == null && nearest != null && minDist <= 50.0) {
        final fallback = nearest['city']?.toString();
        if (fallback != null &&
            fallback.isNotEmpty &&
            fallback.toLowerCase() != 'null') {
          bestCity = fallback;
        }
      }
      if (bestCity != null) {
        setState(() => _userCity = bestCity);
      }
    }

    if (_userVillageId == null) {
      String? bestVillage = _mostCommonField(villageStores, 'village');
      if (bestVillage == null)
        bestVillage = _mostCommonField(closeStores, 'village');
      if (bestVillage != null) {
        setState(() => _userVillage = bestVillage);
      }
    }

    if (_userCountryCode == null) {
      String? bestCountry;
      if (nearest != null && minDist <= 50.0) {
        bestCountry = nearest['country']?.toString();
      }
      if (bestCountry != null) {
        setState(() => _userCountry = bestCountry);
      }
    }
  }

  Future<void> _reverseGeocodeUserLocation(double lat, double lng) async {
    try {
      final lang = localeNotifier.value.languageCode;
      final geo = await LocationHelper.reverseGeocodeCanonical(
        lat,
        lng,
        lang: lang,
      );
      if (geo != null && mounted) {
        setState(() {
          _userCityId = geo['canonical_id']?.toString();
          _userCity = geo['display_name']?.toString();
          _userCountryCode = geo['country_code']?.toString();
          // Try to extract village from display_name or address
          final addr = geo['address'] as Map<String, dynamic>?;
          if (addr != null) {
            final villageName =
                addr['village']?.toString() ??
                addr['hamlet']?.toString() ??
                addr['suburb']?.toString();
            _userVillage = villageName;
            if (villageName != null) {
              _userVillageId = '${_userCityId}_village_$villageName';
            }
          }
        });
      }
    } catch (e) {
      // Silent fail — fallback to store inference
    }
  }

  String? _mostCommonField(List<dynamic> stores, String field) {
    final Map<String, int> counts = {};
    for (final s in stores) {
      final val = s[field]?.toString().trim();
      if (val != null &&
          val.isNotEmpty &&
          val.toLowerCase() != 'null' &&
          val.toLowerCase() != 'unknown') {
        counts[val] = (counts[val] ?? 0) + 1;
      }
    }
    String? winner;
    int bestCount = 0;
    counts.forEach((val, count) {
      if (count > bestCount) {
        bestCount = count;
        winner = val;
      }
    });
    return winner;
  }

  String? _getItemVillage(dynamic item) {
    final village = item['village']?.toString();
    if (village != null && village.isNotEmpty) return village;
    final storeVillage = item['store_village']?.toString();
    if (storeVillage != null && storeVillage.isNotEmpty) return storeVillage;
    final shopName = item['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty && _stores.isNotEmpty) {
      for (final store in _stores) {
        if (store['name']?.toString() == shopName) {
          return store['village']?.toString();
        }
      }
    }
    return null;
  }

  String? _getItemCity(dynamic item) {
    // NEW: Prefer canonical city_id for multilingual matching
    final cityId = item['city_id']?.toString();
    if (cityId != null && cityId.isNotEmpty) {
      return cityId; // Return canonical ID for comparison
    }
    final city = item['city']?.toString();
    if (city != null && city.isNotEmpty && city.toLowerCase() != 'null')
      return city;
    final storeCity = item['store_city']?.toString();
    if (storeCity != null &&
        storeCity.isNotEmpty &&
        storeCity.toLowerCase() != 'null')
      return storeCity;
    final shopName = item['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty && _stores.isNotEmpty) {
      for (final store in _stores) {
        if (store['name']?.toString() == shopName) {
          return store['city_id']?.toString() ?? store['city']?.toString();
        }
      }
    }
    return null;
  }

  String? _getItemCountry(dynamic item) {
    final country = item['country']?.toString();
    if (country != null && country.isNotEmpty) return country;
    final storeCountry = item['store_country']?.toString();
    if (storeCountry != null && storeCountry.isNotEmpty) return storeCountry;
    final shopName = item['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty && _stores.isNotEmpty) {
      for (final store in _stores) {
        if (store['name']?.toString() == shopName) {
          return store['country']?.toString();
        }
      }
    }
    return null;
  }

  /// Area filter: village → city → country → all.
  /// NEW: Uses canonical city_id for language-agnostic matching.
  List<dynamic> _filterByLocation(List<dynamic> items) {
    // Local copies for null-safety promotion
    final village = _userVillage;
    final villageId = _userVillageId;
    final city = _userCity;
    final cityId = _userCityId;
    final country = _userCountry;
    final countryCode = _userCountryCode;

    switch (_locationFilterMode) {
      case 'all':
        return items;
      case 'village':
        // Cascade: village → city → country → world
        if (villageId != null && villageId.isNotEmpty) {
          final villageItems = items.where((item) {
            final itemVillageId = item['village_id']?.toString();
            return itemVillageId != null &&
                itemVillageId.isNotEmpty &&
                itemVillageId.toLowerCase() == villageId.toLowerCase();
          }).toList();
          if (villageItems.isNotEmpty) return villageItems;
        }
        // Fallback to text comparison for legacy data
        if (village != null && village.isNotEmpty) {
          final villageItems = items.where((item) {
            final itemVillage = _getItemVillage(item);
            return itemVillage != null &&
                itemVillage.isNotEmpty &&
                itemVillage.toLowerCase() == village.toLowerCase();
          }).toList();
          if (villageItems.isNotEmpty) return villageItems;
        }
        if (cityId != null && cityId.isNotEmpty) {
          final cityItems = items.where((item) {
            final itemCityId = item['city_id']?.toString();
            return itemCityId != null &&
                itemCityId.isNotEmpty &&
                itemCityId.toLowerCase() == cityId.toLowerCase();
          }).toList();
          if (cityItems.isNotEmpty) return cityItems;
        }
        // Fallback to text city
        if (city != null && city.isNotEmpty) {
          final cityItems = items.where((item) {
            final itemCity = _getItemCity(item);
            return itemCity != null &&
                itemCity.isNotEmpty &&
                itemCity.toLowerCase() == city.toLowerCase();
          }).toList();
          if (cityItems.isNotEmpty) return cityItems;
        }
        if (countryCode != null && countryCode.isNotEmpty) {
          final countryItems = items.where((item) {
            final itemCc = item['country_code']?.toString();
            return itemCc != null &&
                itemCc.isNotEmpty &&
                itemCc.toLowerCase() == countryCode.toLowerCase();
          }).toList();
          if (countryItems.isNotEmpty) return countryItems;
        }
        if (country != null && country.isNotEmpty) {
          final countryItems = items.where((item) {
            final itemCountry = _getItemCountry(item);
            return itemCountry != null &&
                itemCountry.isNotEmpty &&
                itemCountry.toLowerCase() == country.toLowerCase();
          }).toList();
          if (countryItems.isNotEmpty) return countryItems;
        }
        return items;
      case 'city':
        // NEW: Prefer canonical ID matching
        if (cityId != null && cityId.isNotEmpty) {
          return items.where((item) {
            final itemCityId = item['city_id']?.toString();
            if (itemCityId != null && itemCityId.isNotEmpty) {
              return itemCityId.toLowerCase() == cityId.toLowerCase();
            }
            // Fallback for legacy stores without city_id
            final itemCity = _getItemCity(item);
            return itemCity != null &&
                itemCity.isNotEmpty &&
                city != null &&
                city.isNotEmpty &&
                itemCity.toLowerCase() == city.toLowerCase();
          }).toList();
        }
        if (city == null || city.isEmpty) return items;
        return items.where((item) {
          final itemCity = _getItemCity(item);
          return itemCity != null &&
              itemCity.isNotEmpty &&
              itemCity.toLowerCase() == city.toLowerCase();
        }).toList();
      case 'country':
        if (countryCode != null && countryCode.isNotEmpty) {
          return items.where((item) {
            final itemCc = item['country_code']?.toString();
            if (itemCc != null && itemCc.isNotEmpty) {
              return itemCc.toLowerCase() == countryCode.toLowerCase();
            }
            final itemCountry = _getItemCountry(item);
            return itemCountry != null &&
                itemCountry.isNotEmpty &&
                country != null &&
                country.isNotEmpty &&
                itemCountry.toLowerCase() == country.toLowerCase();
          }).toList();
        }
        if (country == null || country.isEmpty) return items;
        return items.where((item) {
          final itemCountry = _getItemCountry(item);
          return itemCountry != null &&
              itemCountry.isNotEmpty &&
              itemCountry.toLowerCase() == country.toLowerCase();
        }).toList();
      default:
        return items;
    }
  }

  /// Separate radius filter (5 / 10 / 20 / 50 km).
  List<dynamic> _filterByDistance(List<dynamic> items) {
    if (_distanceFilterKm == null || _userPosition == null) return items;
    final uLat = _userPosition!.latitude;
    final uLng = _userPosition!.longitude;
    return items.where((item) {
      final sLat = item['lat'];
      final sLng = item['lng'];
      if (sLat == null || sLng == null) return false;
      final lat = sLat is num
          ? sLat.toDouble()
          : double.tryParse(sLat.toString());
      final lng = sLng is num
          ? sLng.toDouble()
          : double.tryParse(sLng.toString());
      if (lat == null || lng == null) return false;
      final d = LocationHelper.distanceKm(uLat, uLng, lat, lng);
      return d <= _distanceFilterKm!;
    }).toList();
  }

  List<dynamic> _filterByPrice(List<dynamic> items) {
    return items.where((item) {
      final rawPrice = item['price'];
      final price = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice.toString()) ?? 0;
      final passesMin = price >= _selectedMinPrice;
      // FIXED: Unlimited max means no upper bound
      final passesMax =
          _selectedMaxPrice == double.infinity || price <= _selectedMaxPrice;
      return passesMin && passesMax;
    }).toList();
  }

  List<dynamic> _filterByCategory(List<dynamic> items) {
    final selectedCategory = _selectedCategory;
    if (selectedCategory == null) return items;
    return items.where((item) {
      final category = item['category']?.toString() ?? '';
      return category.isNotEmpty &&
          category.toLowerCase() == selectedCategory.toLowerCase();
    }).toList();
  }

  List<dynamic> _filterByRating(List<dynamic> items) {
    if (_minRating <= 0) return items;
    return items.where((item) {
      final raw = item['rating'];
      final rating = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '0') ?? 0;
      return rating >= _minRating;
    }).toList();
  }

  List<dynamic> _applyAllFilters(List<dynamic> items) {
    var filtered = _filterByLocation(items);
    filtered = _filterByDistance(filtered);
    filtered = _filterByPrice(filtered);
    filtered = _filterByCategory(filtered);
    filtered = _filterByRating(filtered);
    return filtered;
  }

  List<dynamic> _sortItems(List<dynamic> items) {
    final sorted = List<dynamic>.from(items);
    switch (_sortBy) {
      case 'price_low':
        sorted.sort((a, b) {
          final aPrice = (a['price'] is num)
              ? (a['price'] as num).toDouble()
              : double.tryParse(a['price']?.toString() ?? '0') ?? 0;
          final bPrice = (b['price'] is num)
              ? (b['price'] as num).toDouble()
              : double.tryParse(b['price']?.toString() ?? '0') ?? 0;
          return aPrice.compareTo(bPrice);
        });
        break;
      case 'price_high':
        sorted.sort((a, b) {
          final aPrice = (a['price'] is num)
              ? (a['price'] as num).toDouble()
              : double.tryParse(a['price']?.toString() ?? '0') ?? 0;
          final bPrice = (b['price'] is num)
              ? (b['price'] as num).toDouble()
              : double.tryParse(b['price']?.toString() ?? '0') ?? 0;
          return bPrice.compareTo(aPrice);
        });
        break;
      case 'popular':
        sorted.sort((a, b) {
          final aViews = (a['view_count'] is num)
              ? (a['view_count'] as num).toInt()
              : int.tryParse(a['view_count']?.toString() ?? '0') ?? 0;
          final bViews = (b['view_count'] is num)
              ? (b['view_count'] as num).toInt()
              : int.tryParse(b['view_count']?.toString() ?? '0') ?? 0;
          return bViews.compareTo(aViews);
        });
        break;
      case 'newest':
      default:
        break;
    }
    return sorted;
  }

  @override
  void dispose() {
    _viewFlushTimer?.cancel();
    _flushViews();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    try {
      final user = await ApiService.getCurrentUser();
      if (mounted && user != null)
        setState(() => _userName = user['full_name'] ?? '');
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final products = await ApiService.fetchMarketplaceFeed();
      if (mounted) {
        setState(() {
          _products = products;
          _productsLoading = false;
          _updateRecommendedProducts();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _productsLoading = false);
    }
  }

  Future<void> _loadStores() async {
    try {
      final stores = await ApiService.fetchStores();
      if (mounted)
        setState(() {
          _stores = stores;
          _storesLoading = false;
        });
      // Re-infer location now that stores are available
      if (mounted && _userPosition != null && _stores.isNotEmpty) {
        _inferUserLocationFromStores();
      }
    } catch (_) {
      if (mounted) setState(() => _storesLoading = false);
    }
  }

  Future<void> _loadTrending() async {
    try {
      final trending = await ApiService.fetchTrendingProducts();
      if (mounted)
        setState(() {
          _trendingProducts = trending.isNotEmpty ? trending : [];
          _trendingLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _trendingLoading = false);
    }
  }

  Future<void> _loadSponsored() async {
    try {
      final sponsored = await ApiService.fetchSponsoredStores();
      if (mounted)
        setState(() {
          _sponsoredStores = sponsored.isNotEmpty ? sponsored : [];
          _sponsoredLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _sponsoredLoading = false);
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final recs = await ApiService.fetchRecommendations();
      if (mounted) {
        setState(() {
          _apiRecommendations = recs;
          _recommendationsLoading = false;
          _updateRecommendedProducts();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _recommendationsLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    setState(() {
      _productsLoading = true;
      _storesLoading = true;
      _trendingLoading = true;
      _sponsoredLoading = true;
      _recommendationsLoading = true;
    });
    await Future.wait([
      _loadProducts(),
      _loadStores(),
      _loadTrending(),
      _loadSponsored(),
      _loadRecommendations(),
    ]);
  }

  void _updateRecommendedProducts() {
    if (_apiRecommendations.isNotEmpty) {
      final filtered = _applyAllFilters(_apiRecommendations);
      _recommendedProducts = filtered.length > 6
          ? filtered.sublist(0, 6)
          : List<dynamic>.from(filtered);
      return;
    }

    final pool = _applyAllFilters(_products);
    if (pool.length <= 6) {
      _recommendedProducts = List<dynamic>.from(pool);
      return;
    }
    final random = Random();
    final indices = <int>{};
    while (indices.length < 6 && indices.length < pool.length) {
      indices.add(random.nextInt(pool.length));
    }
    _recommendedProducts = indices.map((i) => pool[i]).toList();
  }

  List<dynamic> _getRecommendedProducts() {
    return _recommendedProducts;
  }

  void _onProductTap(dynamic product) async {
    final canProceed = await _requireAuth();
    if (!canProceed) return;
    _trackProductView(product);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  void _trackProductView(dynamic product) {
    final productName = product['name']?.toString() ?? '';
    if (productName.isEmpty) return;
    _pendingViews.remove(productName);
    _pendingViews.insert(0, productName);
    if (_pendingViews.length > 20) _pendingViews.removeLast();
    _viewFlushTimer?.cancel();
    _viewFlushTimer = Timer(const Duration(seconds: 2), _flushViews);
    final productId = product['id'];
    if (productId != null)
      ApiService.trackProductView(productId).catchError((_) {});
  }

  static Future<void> _flushViews() async {
    if (_pendingViews.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'recent_product_views',
      List<String>.from(_pendingViews),
    );
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SearchBottomSheet(
        products: _products,
        stores: _stores,
        onProductTap: (product) {
          Navigator.pop(context);
          _onProductTap(product);
        },
        onStoreTap: (store) async {
          Navigator.pop(context);
          final canProceed = await _requireAuth();
          if (!canProceed) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoreProductsScreen(storeId: store['id']),
            ),
          );
        },
      ),
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        locationFilterMode: _locationFilterMode,
        userVillage: _userVillage,
        userCity: _userCity,
        userCountry: _userCountry,
        userCityId: _userCityId,
        userVillageId: _userVillageId,
        userCountryCode: _userCountryCode,
        hasPosition: _userPosition != null,
        distanceFilterKm: _distanceFilterKm,
        selectedMinPrice: _selectedMinPrice,
        selectedMaxPrice: _selectedMaxPrice,
        selectedCategory: _selectedCategory,
        categories: _categories,
        minRating: _minRating,
        sortBy: _sortBy,
        onApply: (filters) {
          setState(() {
            _locationFilterMode = filters['locationFilterMode'];
            _distanceFilterKm = filters['distanceFilterKm'];
            _selectedMinPrice = filters['minPrice'];
            _selectedMaxPrice = filters['maxPrice'];
            _selectedCategory = filters['category'];
            _minRating = filters['minRating'];
            _sortBy = filters['sortBy'];
          });
          _saveFilterPreferences();
          _updateRecommendedProducts();
          Navigator.pop(context);
        },
        onReset: () {
          setState(() {
            _locationFilterMode = 'all';
            _distanceFilterKm = null;
            _selectedMinPrice = 0;
            _selectedMaxPrice = double.infinity;
            _selectedCategory = null;
            _minRating = 0;
            _sortBy = 'newest';
          });
          _saveFilterPreferences();
          _updateRecommendedProducts();
          Navigator.pop(context);
        },
        onRequestLocation: _initLocation,
      ),
    );
  }

  void _openSeeAll({
    required String title,
    required List<dynamic> items,
    required bool isStore,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SeeAllScreen(
          title: title,
          items: items,
          isStore: isStore,
          onProductTap: _onProductTap,
          onStoreTap: (store) async {
            final canProceed = await _requireAuth();
            if (!canProceed) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoreProductsScreen(storeId: store['id']),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _sortItems(_applyAllFilters(_products));
    final filteredTrending = _sortItems(_applyAllFilters(_trendingProducts));
    // FIXED: Only apply location filter to sponsored stores (not price/category/rating/sort)
    final filteredSponsored = _filterByLocation(_sponsoredStores);
    // NEW: Filter ALL stores by location for the Nearby Shops section
    final filteredStores = _filterByLocation(_stores);
    final filteredRecommended = _getRecommendedProducts();

    // Local copies for null-safety promotion
    final dist = _distanceFilterKm;
    final village = _userVillage;
    final villageId = _userVillageId;
    final city = _userCity;
    final cityId = _userCityId;
    final country = _userCountry;
    final countryCode = _userCountryCode;

    // FIXED: Check if any filter is active (including unlimited max)
    final bool hasActiveFilters =
        _locationFilterMode != 'all' ||
        _distanceFilterKm != null ||
        _selectedMinPrice > 0 ||
        _selectedMaxPrice != double.infinity ||
        _selectedCategory != null ||
        _minRating > 0 ||
        _sortBy != 'newest';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: CustomScrollView(
            slivers: [
              // ── Header (theme + language switches only) ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const ThemeToggle(),
                      const SizedBox(width: 2),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: IconButton(
                          icon: ValueListenableBuilder(
                            valueListenable: localeNotifier,
                            builder: (_, locale, __) => Text(
                              locale.languageCode.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          onPressed: () => showLanguagePicker(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Search bar ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: GestureDetector(
                    onTap: _openSearch,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Icon(
                            Icons.search,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.4),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              t('search') ?? 'Search',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.4),
                                fontSize: 15,
                              ),
                            ),
                          ),
                          // Filter button with badge
                          Stack(
                            children: [
                              Container(
                                margin: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: hasActiveFilters
                                      ? Theme.of(context).colorScheme.secondary
                                      : Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: _openFilterSheet,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.tune,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            t('filter') ?? 'Filter',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (hasActiveFilters)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).scaffoldBackgroundColor,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Active filters chips row ──
              if (hasActiveFilters)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_locationFilterMode != 'all')
                            _FilterChip(
                              label: () {
                                switch (_locationFilterMode) {
                                  case 'village':
                                    if (village != null && village.isNotEmpty)
                                      return village;
                                    if (villageId != null &&
                                        villageId.isNotEmpty)
                                      return villageId;
                                    return t('nearby') ?? 'Nearby';
                                  case 'city':
                                    if (city != null &&
                                        city.isNotEmpty &&
                                        city.toLowerCase() != 'null')
                                      return city;
                                    if (cityId != null && cityId.isNotEmpty)
                                      return cityId;
                                    return t('nearby') ?? 'Nearby';
                                  case 'country':
                                    if (country != null && country.isNotEmpty)
                                      return country;
                                    if (countryCode != null &&
                                        countryCode.isNotEmpty)
                                      return countryCode.toUpperCase();
                                    return t('unknown_country') ??
                                        'Unknown Country';
                                  default:
                                    return t('nearby') ?? 'Nearby';
                                }
                              }(),
                              icon: Icons.location_on,
                              onRemove: () {
                                setState(() => _locationFilterMode = 'all');
                                _saveFilterPreferences();
                                _updateRecommendedProducts();
                              },
                            ),
                          if (dist != null)
                            _FilterChip(
                              label: '${dist.round()} km',
                              icon: Icons.straighten,
                              onRemove: () {
                                setState(() => _distanceFilterKm = null);
                                _saveFilterPreferences();
                                _updateRecommendedProducts();
                              },
                            ),
                          // FIXED: Price chip shows unlimited properly
                          if (_selectedMinPrice > 0 ||
                              _selectedMaxPrice != double.infinity)
                            _FilterChip(
                              label: _selectedMaxPrice == double.infinity
                                  ? '${_selectedMinPrice.toStringAsFixed(0)}+'
                                  : '${_selectedMinPrice.toStringAsFixed(0)} - ${_selectedMaxPrice.toStringAsFixed(0)}',
                              icon: Icons.attach_money,
                              onRemove: () {
                                setState(() {
                                  _selectedMinPrice = 0;
                                  _selectedMaxPrice = double.infinity;
                                });
                                _saveFilterPreferences();
                                _updateRecommendedProducts();
                              },
                            ),
                          if (_selectedCategory != null)
                            _FilterChip(
                              label: _selectedCategory!,
                              icon: Icons.category,
                              onRemove: () {
                                setState(() => _selectedCategory = null);
                                _saveFilterPreferences();
                                _updateRecommendedProducts();
                              },
                            ),
                          if (_minRating > 0)
                            _FilterChip(
                              label: '${_minRating.round()}+ ★',
                              icon: Icons.star,
                              onRemove: () {
                                setState(() => _minRating = 0);
                                _saveFilterPreferences();
                                _updateRecommendedProducts();
                              },
                            ),
                          if (_sortBy != 'newest')
                            _FilterChip(
                              label: _sortLabels[_sortBy] ?? _sortBy,
                              icon: Icons.sort,
                              onRemove: () {
                                setState(() => _sortBy = 'newest');
                                _saveFilterPreferences();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Recommended ──
              if (!_recommendationsLoading &&
                  !_productsLoading &&
                  filteredRecommended.isNotEmpty) ...[
                _SectionHeaderSliver(
                  title: t('recommended_for_you') ?? 'Recommended for You',
                  onSeeAll: () => _openSeeAll(
                    title: t('recommended_for_you') ?? 'Recommended for You',
                    items: filteredRecommended,
                    isStore: false,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filteredRecommended.length,
                      itemBuilder: (context, i) => _SmallProductCard(
                        product: filteredRecommended[i],
                        onTap: _onProductTap,
                      ),
                    ),
                  ),
                ),
              ],

              // ── Top Shops ──
              if (!_sponsoredLoading && filteredSponsored.isNotEmpty) ...[
                _SectionHeaderSliver(
                  title: t('top_shops') ?? 'Top Shops',
                  onSeeAll: () => _openSeeAll(
                    title: t('top_shops') ?? 'Top Shops',
                    items: filteredSponsored,
                    isStore: true,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 140,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filteredSponsored.length,
                      itemBuilder: (context, i) => _SponsoredStoreCard(
                        store: filteredSponsored[i],
                        onTap: (store) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                StoreProductsScreen(storeId: store['id']),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // ── Hot & Trending ──
              if (!_trendingLoading && filteredTrending.isNotEmpty) ...[
                _SectionHeaderSliver(
                  title: t('hot_trending') ?? 'Hot & Trending',
                  onSeeAll: () => _openSeeAll(
                    title: t('hot_trending') ?? 'Hot & Trending',
                    items: filteredTrending,
                    isStore: false,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filteredTrending.length,
                      itemBuilder: (context, i) => _SmallProductCard(
                        product: filteredTrending[i],
                        onTap: _onProductTap,
                        isTrending: true,
                      ),
                    ),
                  ),
                ),
              ],

              // ── Nearby Shops ──
              if (!_storesLoading && filteredStores.isNotEmpty) ...[
                _SectionHeaderSliver(
                  title: t('nearby_shops') ?? 'Nearby Shops',
                  onSeeAll: () => _openSeeAll(
                    title: t('nearby_shops') ?? 'Nearby Shops',
                    items: filteredStores,
                    isStore: true,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 140,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filteredStores.length,
                      itemBuilder: (context, i) => _SponsoredStoreCard(
                        store: filteredStores[i],
                        onTap: (store) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                StoreProductsScreen(storeId: store['id']),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // ── Latest Products header ──
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text(
                        t('latest_products') ?? 'Latest Products',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _isGridView ? Icons.view_list : Icons.grid_view,
                          size: 20,
                        ),
                        onPressed: _toggleViewMode,
                        tooltip: _isGridView
                            ? (t('list_view') ?? 'List view')
                            : (t('grid_view') ?? 'Grid view'),
                      ),
                      TextButton(
                        onPressed: () => _openSeeAll(
                          title: t('latest_products') ?? 'Latest Products',
                          items: filteredProducts,
                          isStore: false,
                        ),
                        child: Text(t('see_all') ?? 'See All'),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Latest Products ──
              if (_productsLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (filteredProducts.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.filter_list_off,
                            size: 48,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t('no_products_match_filters') ??
                                'No products match your filters',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _locationFilterMode = 'all';
                                _distanceFilterKm = null;
                                _selectedMinPrice = 0;
                                _selectedMaxPrice = double.infinity;
                                _selectedCategory = null;
                                _minRating = 0;
                                _sortBy = 'newest';
                              });
                              _saveFilterPreferences();
                              _updateRecommendedProducts();
                            },
                            child: Text(
                              t('clear_all_filters') ?? 'Clear all filters',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                _isGridView
                    ? _buildProductGrid(filteredProducts)
                    : _buildProductList(filteredProducts),

              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductGrid(List<dynamic> products) {
    final displayCount = products.length > 30 ? 30 : products.length;
    final displayProducts = products.take(displayCount).toList();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.start,
          children: displayProducts.map((product) {
            return _SmallProductCard(product: product, onTap: _onProductTap);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProductList(List<dynamic> products) {
    final displayCount = products.length > 30 ? 30 : products.length;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ProductListTile(product: products[i], onTap: _onProductTap),
          ),
          childCount: displayCount,
        ),
      ),
    );
  }
}

// ============================================================
// FILTER SHEET
// ============================================================

class _FilterSheet extends StatefulWidget {
  final String locationFilterMode;
  final String? userVillage;
  final String? userCity;
  final String? userCountry;
  final String? userCityId;
  final String? userVillageId;
  final String? userCountryCode;
  final bool hasPosition;
  final double? distanceFilterKm;
  final double selectedMinPrice;
  final double selectedMaxPrice;
  final String? selectedCategory;
  final List<String> categories;
  final double minRating;
  final String sortBy;
  final void Function(Map<String, dynamic>) onApply;
  final VoidCallback onReset;
  final VoidCallback onRequestLocation;

  const _FilterSheet({
    required this.locationFilterMode,
    this.userVillage,
    this.userCity,
    this.userCountry,
    this.userCityId,
    this.userVillageId,
    this.userCountryCode,
    required this.hasPosition,
    this.distanceFilterKm,
    required this.selectedMinPrice,
    required this.selectedMaxPrice,
    required this.selectedCategory,
    required this.categories,
    required this.minRating,
    required this.sortBy,
    required this.onApply,
    required this.onReset,
    required this.onRequestLocation,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _locationFilterMode;
  late double? _distanceFilterKm;
  late double _selMinPrice;
  late double _selMaxPrice;
  late String? _category;
  late double _rating;
  late String _sort;

  // FIXED: Slider max cap - reasonable amount, dragging to end = unlimited
  static const double _sliderMax = 100000.0;

  final List<double> _distanceOptions = [5.0, 10.0, 20.0, 50.0];
  final List<String> _sortOptions = [
    'newest',
    'price_low',
    'price_high',
    'popular',
  ];

  @override
  void initState() {
    super.initState();
    _locationFilterMode = widget.locationFilterMode;
    _distanceFilterKm = widget.distanceFilterKm;
    _selMinPrice = widget.selectedMinPrice;
    _selMaxPrice = widget.selectedMaxPrice;
    _category = widget.selectedCategory;
    _rating = widget.minRating;
    _sort = widget.sortBy;
  }

  // Safe setters that enforce start <= end constraint
  void _setMinPrice(double value) {
    setState(() {
      _selMinPrice = value.clamp(0.0, _sliderMax);
      if (_selMaxPrice != double.infinity && _selMinPrice > _selMaxPrice) {
        _selMaxPrice = _selMinPrice;
      }
    });
  }

  void _setMaxPrice(double value) {
    setState(() {
      if (value == double.infinity) {
        _selMaxPrice = double.infinity;
        return;
      }
      _selMaxPrice = value.clamp(0.0, _sliderMax);
      if (_selMaxPrice < _selMinPrice) {
        _selMinPrice = _selMaxPrice;
      }
    });
  }

  // FIXED: Convert slider value to actual price (infinity at max)
  double _sliderToPrice(double sliderValue) {
    if (sliderValue >= _sliderMax) return double.infinity;
    return sliderValue;
  }

  // FIXED: Convert actual price to slider value
  double _priceToSlider(double price) {
    if (price == double.infinity) return _sliderMax;
    return price.clamp(0.0, _sliderMax);
  }

  // FIXED: Format price label with compact notation
  String _formatPriceLabel(double price) {
    if (price == double.infinity) return t('unlimited') ?? 'Unlimited';
    if (price >= 1000000) return '\$${(price / 1000000).toStringAsFixed(1)}M';
    if (price >= 1000) return '\$${(price / 1000).toStringAsFixed(1)}K';
    return '\$${price.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    // Local copies for null-safety promotion
    final village = widget.userVillage;
    final villageId = widget.userVillageId;
    final city = widget.userCity;
    final cityId = widget.userCityId;
    final country = widget.userCountry;
    final countryCode = widget.userCountryCode;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text(
                  t('filters') ?? 'Filters',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onReset,
                  child: Text(t('reset_all') ?? 'Reset all'),
                ),
              ],
            ),
          ),
          const Divider(),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Location Filter ──
                  _buildSectionTitle(
                    t('location') ?? 'Location',
                    Icons.location_on,
                  ),
                  const SizedBox(height: 8),
                  if (!widget.hasPosition)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          widget.onRequestLocation();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.my_location, size: 18),
                        label: Text(
                          t('enable_gps_location') ?? 'Enable GPS location',
                        ),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Location mode chips
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(
                                _tr('all_regions', fallback: 'All Regions'),
                              ),
                              selected: _locationFilterMode == 'all',
                              onSelected: (_) =>
                                  setState(() => _locationFilterMode = 'all'),
                            ),
                            // Show village chip if we have village ID or text name
                            if (villageId != null || village != null)
                              ChoiceChip(
                                label: Text(
                                  village ??
                                      villageId ??
                                      t('nearby') ??
                                      'Nearby',
                                ),
                                selected: _locationFilterMode == 'village',
                                onSelected: (_) => setState(
                                  () => _locationFilterMode = 'village',
                                ),
                              ),
                            // Show city chip if we have city ID or text name
                            if (cityId != null || city != null)
                              ChoiceChip(
                                label: Text(
                                  city != null &&
                                          city.isNotEmpty &&
                                          city.toLowerCase() != 'null'
                                      ? city
                                      : (cityId != null
                                            ? cityId
                                            : (t('nearby') ?? 'Nearby')),
                                ),
                                selected: _locationFilterMode == 'city',
                                onSelected: (_) => setState(
                                  () => _locationFilterMode = 'city',
                                ),
                              ),
                            // Show country chip if we have country code or text name
                            if (countryCode != null || country != null)
                              ChoiceChip(
                                label: Text(
                                  country != null && country.isNotEmpty
                                      ? country
                                      : (countryCode != null
                                            ? countryCode.toUpperCase()
                                            : (t('unknown_country') ??
                                                  'Unknown Country')),
                                ),
                                selected: _locationFilterMode == 'country',
                                onSelected: (_) => setState(
                                  () => _locationFilterMode = 'country',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Show current detected location
                        if (village != null ||
                            villageId != null ||
                            city != null ||
                            cityId != null ||
                            country != null ||
                            countryCode != null)
                          Text(
                            '${t('location') ?? 'Location'}: ${[village ?? villageId, city ?? cityId, country ?? countryCode?.toUpperCase()].where((e) => e != null).join(', ')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // ── Distance Filter (separate from city/village) ──
                  _buildSectionTitle(t('radius') ?? 'Radius', Icons.straighten),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(t('all') ?? 'All'),
                        selected: _distanceFilterKm == null,
                        onSelected: (_) =>
                            setState(() => _distanceFilterKm = null),
                      ),
                      ..._distanceOptions.map((km) {
                        return ChoiceChip(
                          label: Text('${km.round()} km'),
                          selected: _distanceFilterKm == km,
                          onSelected: (_) =>
                              setState(() => _distanceFilterKm = km),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Price Range ──
                  _buildSectionTitle(
                    t('price_range') ?? 'Price Range',
                    Icons.attach_money,
                  ),
                  const SizedBox(height: 8),
                  // Manual input row for precise control
                  Row(
                    children: [
                      Expanded(
                        child: _PriceInputField(
                          label: t('min') ?? 'Min',
                          value: _selMinPrice == double.infinity
                              ? ''
                              : _selMinPrice.toStringAsFixed(0),
                          onChanged: (val) {
                            final parsed = double.tryParse(val) ?? 0;
                            _setMinPrice(parsed);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '—',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: _PriceInputField(
                          label: t('max') ?? 'Max',
                          value: _selMaxPrice == double.infinity
                              ? ''
                              : _selMaxPrice.toStringAsFixed(0),
                          hint: t('unlimited') ?? 'Unlimited',
                          onChanged: (val) {
                            if (val.isEmpty) {
                              _setMaxPrice(double.infinity);
                              return;
                            }
                            final parsed = double.tryParse(val);
                            if (parsed == null) return;
                            if (parsed <= 0 || parsed >= _sliderMax) {
                              _setMaxPrice(double.infinity);
                            } else {
                              _setMaxPrice(parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatPriceLabel(_selMinPrice),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        _formatPriceLabel(_selMaxPrice),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  // FIXED: 100 increments (1000 divisions across 100K range)
                  RangeSlider(
                    values: RangeValues(
                      _priceToSlider(
                        _selMinPrice,
                      ).clamp(0.0, _priceToSlider(_selMaxPrice)),
                      _priceToSlider(
                        _selMaxPrice,
                      ).clamp(_priceToSlider(_selMinPrice), _sliderMax),
                    ),
                    min: 0,
                    max: _sliderMax,
                    divisions: 1000, // 100 per step
                    labels: RangeLabels(
                      _formatPriceLabel(_selMinPrice),
                      _formatPriceLabel(_selMaxPrice),
                    ),
                    onChanged: (values) {
                      setState(() {
                        _selMinPrice = values.start;
                        _selMaxPrice = _sliderToPrice(values.end);
                        // Enforce constraint after both values update
                        if (_selMaxPrice != double.infinity &&
                            _selMinPrice > _selMaxPrice) {
                          _selMaxPrice = _selMinPrice;
                        }
                      });
                    },
                  ),
                  // Quick preset chips for common ranges
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PricePresetChip(
                        label: '< \$100',
                        onTap: () {
                          _setMinPrice(0);
                          _setMaxPrice(100);
                        },
                        isActive: _selMinPrice == 0 && _selMaxPrice == 100,
                      ),
                      _PricePresetChip(
                        label: '\$100 - \$500',
                        onTap: () {
                          _setMinPrice(100);
                          _setMaxPrice(500);
                        },
                        isActive: _selMinPrice == 100 && _selMaxPrice == 500,
                      ),
                      _PricePresetChip(
                        label: '\$500 - \$2K',
                        onTap: () {
                          _setMinPrice(500);
                          _setMaxPrice(2000);
                        },
                        isActive: _selMinPrice == 500 && _selMaxPrice == 2000,
                      ),
                      _PricePresetChip(
                        label: '\$2K - \$10K',
                        onTap: () {
                          _setMinPrice(2000);
                          _setMaxPrice(10000);
                        },
                        isActive: _selMinPrice == 2000 && _selMaxPrice == 10000,
                      ),
                      _PricePresetChip(
                        label: '> \$10K',
                        onTap: () {
                          _setMinPrice(10000);
                          _setMaxPrice(double.infinity);
                        },
                        isActive:
                            _selMinPrice == 10000 &&
                            _selMaxPrice == double.infinity,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Category ──
                  _buildSectionTitle(
                    t('category') ?? 'Category',
                    Icons.category,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(t('all') ?? 'All'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                      ...widget.categories.map((cat) {
                        return ChoiceChip(
                          label: Text(cat),
                          selected: _category == cat,
                          onSelected: (_) => setState(() => _category = cat),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Sort By ──
                  _buildSectionTitle(t('sort_by') ?? 'Sort By', Icons.sort),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sortOptions.map((opt) {
                      final labels = {
                        'newest': _tr('newest', fallback: 'Newest'),
                        'price_low': _tr(
                          'price_low_high',
                          fallback: 'Price: Low to High',
                        ),
                        'price_high': _tr(
                          'price_high_low',
                          fallback: 'Price: High to Low',
                        ),
                        'popular': _tr(
                          'most_popular',
                          fallback: 'Most Popular',
                        ),
                      };
                      return ChoiceChip(
                        label: Text(labels[opt] ?? opt),
                        selected: _sort == opt,
                        onSelected: (_) => setState(() => _sort = opt),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ── Minimum Rating ──
                  _buildSectionTitle(
                    t('minimum_rating') ?? 'Minimum Rating',
                    Icons.star,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      return IconButton(
                        icon: Icon(
                          starValue <= _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () =>
                            setState(() => _rating = starValue.toDouble()),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      );
                    }),
                  ),
                  if (_rating > 0)
                    TextButton(
                      onPressed: () => setState(() => _rating = 0),
                      child: Text(
                        t('clear_rating_filter') ?? 'Clear rating filter',
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Apply button
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply({
                    'locationFilterMode': _locationFilterMode,
                    'distanceFilterKm': _distanceFilterKm,
                    'minPrice': _selMinPrice,
                    'maxPrice': _selMaxPrice,
                    'category': _category,
                    'minRating': _rating,
                    'sortBy': _sort,
                  });
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  t('apply_filters') ?? 'Apply Filters',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// ============================================================
// FILTER CHIP (active filter indicator)
// ============================================================

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onRemove;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SEE ALL SCREEN
// ============================================================

class _SeeAllScreen extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final bool isStore;
  final void Function(dynamic) onProductTap;
  final void Function(dynamic) onStoreTap;

  const _SeeAllScreen({
    required this.title,
    required this.items,
    required this.isStore,
    required this.onProductTap,
    required this.onStoreTap,
  });

  @override
  State<_SeeAllScreen> createState() => _SeeAllScreenState();
}

class _SeeAllScreenState extends State<_SeeAllScreen> {
  bool _isGrid = true;

  void _toggleView() => setState(() => _isGrid = !_isGrid);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
            onPressed: _toggleView,
          ),
        ],
      ),
      body: _isGrid ? _buildGrid() : _buildList(),
    );
  }

  Widget _buildGrid() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.start,
        children: widget.items.map((item) {
          if (widget.isStore) {
            return _SponsoredStoreCard(store: item, onTap: widget.onStoreTap);
          }
          return _SmallProductCard(product: item, onTap: widget.onProductTap);
        }).toList(),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: widget.items.length,
      itemBuilder: (context, i) {
        if (widget.isStore) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _StoreListTile(
              store: widget.items[i],
              onTap: widget.onStoreTap,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ProductListTile(
            product: widget.items[i],
            onTap: widget.onProductTap,
          ),
        );
      },
    );
  }
}

// ============================================================
// WIDGETS
// ============================================================

class _SectionHeaderSliver extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHeaderSliver({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              child: Text(t('see_all') ?? 'See All'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallProductCard extends StatelessWidget {
  final dynamic product;
  final void Function(dynamic) onTap;
  final bool isTrending;

  const _SmallProductCard({
    required this.product,
    required this.onTap,
    this.isTrending = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(product),
      child: Container(
        width: 160,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                CachedAppImage(
                  imageUrl: product['image_url'],
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
                if (isTrending)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        t('hot') ?? 'HOT',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '\$${product['price']}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product['shop_name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
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

class _ProductListTile extends StatelessWidget {
  final dynamic product;
  final void Function(dynamic) onTap;

  const _ProductListTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(product),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CachedAppImage(
              imageUrl: product['image_url'],
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${product['price']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product['shop_name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreListTile extends StatelessWidget {
  final dynamic store;
  final void Function(dynamic) onTap;

  const _StoreListTile({required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(store),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CachedAppImage(
              imageUrl: store['image_url'],
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              memCacheWidth: 200,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${store['city'] ?? ''}, ${store['country'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _SponsoredStoreCard extends StatelessWidget {
  final dynamic store;
  final void Function(dynamic) onTap;

  const _SponsoredStoreCard({required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(store),
      child: Container(
        width: 120,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            CachedAppImage(
              imageUrl: store['image_url'],
              width: 120,
              height: 80,
              fit: BoxFit.cover,
              memCacheWidth: 240,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                store['name'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t('top') ?? 'TOP',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade800,
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SEARCH BOTTOM SHEET (real-time + history cache)
// ============================================================

class SearchBottomSheet extends StatefulWidget {
  final List<dynamic> products;
  final List<dynamic> stores;
  final void Function(dynamic) onProductTap;
  final void Function(dynamic) onStoreTap;

  const SearchBottomSheet({
    super.key,
    required this.products,
    required this.stores,
    required this.onProductTap,
    required this.onStoreTap,
  });

  @override
  State<SearchBottomSheet> createState() => _SearchBottomSheetState();
}

class _SearchBottomSheetState extends State<SearchBottomSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<dynamic> _productResults = [];
  List<dynamic> _storeResults = [];
  List<String> _searchHistory = [];
  bool _hasSearched = false;
  static const String _historyKey = 'search_history';

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    if (mounted) {
      setState(() => _searchHistory = history);
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _searchHistory);
  }

  Future<void> _addToHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;
    _searchHistory.remove(trimmed);
    _searchHistory.insert(0, trimmed);
    if (_searchHistory.length > 20) {
      _searchHistory = _searchHistory.sublist(0, 20);
    }
    await _saveHistory();
  }

  Future<void> _removeFromHistory(String query) async {
    setState(() => _searchHistory.remove(query));
    await _saveHistory();
  }

  Future<void> _clearHistory() async {
    setState(() => _searchHistory.clear());
    await _saveHistory();
  }

  void _performSearch(String query) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      setState(() {
        _hasSearched = false;
        _productResults = [];
        _storeResults = [];
      });
      return;
    }

    // Live search: show results even for 1 char
    final products = widget.products.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final desc = item['description']?.toString().toLowerCase() ?? '';
      final shop = item['shop_name']?.toString().toLowerCase() ?? '';
      final cat = item['category']?.toString().toLowerCase() ?? '';
      return name.contains(q) ||
          desc.contains(q) ||
          shop.contains(q) ||
          cat.contains(q);
    }).toList();

    final stores = widget.stores.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final city = item['city']?.toString().toLowerCase() ?? '';
      final country = item['country']?.toString().toLowerCase() ?? '';
      return name.contains(q) || city.contains(q) || country.contains(q);
    }).toList();

    setState(() {
      _hasSearched = true;
      _productResults = products;
      _storeResults = stores;
    });

    // Track and save to history only for meaningful searches (2+ chars)
    if (q.length >= 2) {
      _addToHistory(query);
      ApiService.trackSearch(query).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => _performSearch(q),
              onChanged: (v) {
                _performSearch(v);
              },
              decoration: InputDecoration(
                hintText: t('search') ?? 'Search',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasQuery
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: !hasQuery && _searchHistory.isNotEmpty
                // Show search history when empty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(
                          children: [
                            Text(
                              t('recent_searches') ?? 'Recent Searches',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _clearHistory,
                              child: Text(
                                _tr('clear_all', fallback: 'Clear All'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _searchHistory.length,
                          itemBuilder: (context, i) {
                            final query = _searchHistory[i];
                            return Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.history, size: 20),
                                title: Text(query),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => _removeFromHistory(query),
                                ),
                                onTap: () {
                                  _controller.text = query;
                                  _controller.selection =
                                      TextSelection.collapsed(
                                        offset: query.length,
                                      );
                                  _performSearch(query);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : !hasQuery
                // Empty state - no history
                ? Center(
                    child: Text(
                      t('type_to_search') ?? 'Type to search products & stores',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : (_productResults.isEmpty && _storeResults.isEmpty)
                // No results
                ? Center(
                    child: Text(
                      t('no_results_found') ?? 'No results found',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                // Results
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_storeResults.isNotEmpty) ...[
                        Text(
                          t('stores_results') ?? 'Stores',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ..._storeResults.map(
                          (s) => _StoreListTile(
                            store: s,
                            onTap: widget.onStoreTap,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_productResults.isNotEmpty) ...[
                        Text(
                          t('products_results') ?? 'Products',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ..._productResults.map(
                          (p) => _ProductListTile(
                            product: p,
                            onTap: widget.onProductTap,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PRICE INPUT FIELD (manual entry)
// ============================================================

class _PriceInputField extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final void Function(String) onChanged;

  const _PriceInputField({
    required this.label,
    required this.value,
    this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]*')),
          ],
          decoration: InputDecoration(
            hintText: hint,
            prefixText: '\$',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ============================================================
// PRICE PRESET CHIP (quick range buttons)
// ============================================================

class _PricePresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _PricePresetChip({
    required this.label,
    required this.onTap,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      backgroundColor: isActive
          ? Theme.of(context).colorScheme.primary
          : Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      side: BorderSide(
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline.withOpacity(0.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: onTap,
    );
  }
}

// ============================================================
// LOCATION MODE CHIP
// ============================================================

class _LocationModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _LocationModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      side: BorderSide(
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline.withOpacity(0.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: onTap,
    );
  }
}

// ============================================================
// GUEST AUTH SHEET (reusable across all screens)
// ============================================================

class _GuestAuthSheet extends StatelessWidget {
  const _GuestAuthSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Icon(
            Icons.lock_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            t('login_required') ?? 'Login Required',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              t('guest_login_prompt') ??
                  'Please log in or register to access this feature.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                  // Navigate to login screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  t('login_or_register') ?? 'Log In / Register',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('continue_browsing') ?? 'Continue Browsing'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

const Map<String, String> _sortLabels = {
  'newest': 'Newest',
  'price_low': 'Price: Low to High',
  'price_high': 'Price: High to Low',
  'popular': 'Most Popular',
};
