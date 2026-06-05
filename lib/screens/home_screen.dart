// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../providers/locale_provider.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/cached_image.dart';
import '../utils/location_helper.dart';
import 'store_products_screen.dart';
import 'product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import '../services/marketplace_service.dart';
import '../services/location_service.dart';
import '../services/categories_service.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import '../services/favorites_service.dart';
import '../widgets/product/product_card.dart';
import '../widgets/product/product_list_tile.dart';
import '../widgets/store/store_card.dart';
import '../widgets/store/store_list_tile.dart';
import '../widgets/common/section_header.dart';
import '../widgets/common/filter_chip_widget.dart';
import '../widgets/skeletons/product_skeleton.dart';
import '../widgets/search/search_bottom_sheet.dart';
import '../widgets/home_filter_sheet.dart';
import '../widgets/guest_login_sheet.dart' as guest;
import '../screens/see_all_screen.dart';
import '../utils/tr.dart';
import 'dart:convert';

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

  // Location filter state
  Position? _userPosition;
  String _locationFilterMode = 'all';
  String? _userVillage;
  String? _userCity;
  String? _userCountry;
  double? _distanceFilterKm;
  bool _locationLoading = false;

  // Canonical location IDs
  String? _userCityId;
  String? _userVillageId;
  String? _userCountryCode;

  // Guest mode
  bool _isGuest = false;

  // Price filter state
  double _selectedMinPrice = 0;
  double _selectedMaxPrice = double.infinity;

  // Category filter state
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

  // Rating filter
  double _minRating = 0;

  // Sort option
  String _sortBy = 'newest';

  // Favorites
  Set<int> _favoriteIds = {};

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
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final ids = await FavoritesService.getLocalFavoriteIds();
      if (mounted) setState(() => _favoriteIds = ids.toSet());
    } catch (_) {}
  }

  Future<void> _toggleFavorite(int productId) async {
    await FavoritesService.toggleFavorite(productId);
    final ids = await FavoritesService.getLocalFavoriteIds();
    if (mounted) setState(() => _favoriteIds = ids.toSet());
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

  Future<void> _loadFilterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _locationFilterMode =
            prefs.getString('home_location_filter_mode') ?? 'all';
        if (_locationFilterMode == 'radius') {
          _locationFilterMode = 'all';
          _distanceFilterKm = prefs.getDouble('home_filter_radius') ?? 5.0;
        }
        _distanceFilterKm = prefs.containsKey('home_distance_filter_km')
            ? prefs.getDouble('home_distance_filter_km')
            : _distanceFilterKm;
        _selectedMinPrice = prefs.getDouble('home_min_price') ?? 0;
        final savedMax = prefs.getDouble('home_max_price');
        _selectedMaxPrice = savedMax == null || savedMax >= 999999999
            ? double.infinity
            : savedMax;
        _selectedCategory = prefs.getString('home_category');
        _minRating = prefs.getDouble('home_min_rating') ?? 0;
        _sortBy = prefs.getString('home_sort_by') ?? 'newest';
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
    await prefs.remove('home_filter_radius');
    await prefs.setDouble('home_min_price', _selectedMinPrice);
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
    Position? pos;
    try {
      pos = await LocationHelper.getCurrentPosition().timeout(
        const Duration(seconds: 6),
      );
    } catch (_) {
      pos = null;
    }
    if (!mounted) return;
    setState(() {
      _userPosition = pos;
      _locationLoading = false;
    });
    if (pos != null && _stores.isNotEmpty) {
      _inferUserLocationFromStores();
    }
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

    _reverseGeocodeUserLocation(uLat, uLng);

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
      // Silent fail
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
    final cityId = item['city_id']?.toString();
    if (cityId != null && cityId.isNotEmpty) {
      return cityId;
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

  List<dynamic> _filterByLocation(List<dynamic> items) {
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
        if (villageId != null && villageId.isNotEmpty) {
          final villageItems = items.where((item) {
            final itemVillageId = item['village_id']?.toString();
            return itemVillageId != null &&
                itemVillageId.isNotEmpty &&
                itemVillageId.toLowerCase() == villageId.toLowerCase();
          }).toList();
          if (villageItems.isNotEmpty) return villageItems;
        }
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
        if (cityId != null && cityId.isNotEmpty) {
          return items.where((item) {
            final itemCityId = item['city_id']?.toString();
            if (itemCityId != null && itemCityId.isNotEmpty) {
              return itemCityId.toLowerCase() == cityId.toLowerCase();
            }
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
      final user = await AuthService.getCurrentUser();
      if (mounted && user != null)
        setState(() => _userName = user['full_name'] ?? '');
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_marketplace_feed');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        if (mounted) {
          setState(() {
            _products = decoded;
            _productsLoading = false;
            _updateRecommendedProducts();
          });
        }
      }
    } catch (_) {}

    try {
      final products = await MarketplaceService.fetchMarketplaceFeed();
      if (mounted) {
        setState(() {
          _products = products;
          _productsLoading = false;
          _updateRecommendedProducts();
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_marketplace_feed', jsonEncode(products));
    } catch (_) {
      if (mounted && _products.isEmpty) {
        setState(() => _productsLoading = false);
      }
    }
  }

  Future<void> _loadStores() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_stores');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        if (mounted) {
          setState(() {
            _stores = decoded;
            _storesLoading = false;
          });
          if (_userPosition != null) _inferUserLocationFromStores();
        }
      }
    } catch (_) {}

    try {
      final stores = await StoreService.fetchStores();
      if (mounted) {
        setState(() {
          _stores = stores;
          _storesLoading = false;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_stores', jsonEncode(stores));
        if (_userPosition != null && _stores.isNotEmpty) {
          _inferUserLocationFromStores();
        }
      }
    } catch (_) {
      if (mounted && _stores.isEmpty) {
        setState(() => _storesLoading = false);
      }
    }
  }

  Future<void> _loadTrending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_trending');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        if (mounted) {
          setState(() {
            _trendingProducts = decoded;
            _trendingLoading = false;
          });
        }
      }
    } catch (_) {}

    try {
      final trending = await MarketplaceService.fetchTrendingProducts();
      if (mounted) {
        setState(() {
          _trendingProducts = trending.isNotEmpty ? trending : [];
          _trendingLoading = false;
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_trending', jsonEncode(trending));
    } catch (_) {
      if (mounted && _trendingProducts.isEmpty) {
        setState(() => _trendingLoading = false);
      }
    }
  }

  Future<void> _loadSponsored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_sponsored');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        if (mounted) {
          setState(() {
            _sponsoredStores = decoded;
            _sponsoredLoading = false;
          });
        }
      }
    } catch (_) {}

    try {
      final sponsored = await MarketplaceService.fetchSponsoredStores();
      if (mounted) {
        setState(() {
          _sponsoredStores = sponsored.isNotEmpty ? sponsored : [];
          _sponsoredLoading = false;
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_sponsored', jsonEncode(sponsored));
    } catch (_) {
      if (mounted && _sponsoredStores.isEmpty) {
        setState(() => _sponsoredLoading = false);
      }
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_recommendations');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached) as List<dynamic>;
        if (mounted) {
          setState(() {
            _apiRecommendations = decoded;
            _recommendationsLoading = false;
            _updateRecommendedProducts();
          });
        }
      }
    } catch (_) {}

    try {
      final recs = await MarketplaceService.fetchRecommendations();
      if (mounted) {
        setState(() {
          _apiRecommendations = recs;
          _recommendationsLoading = false;
          _updateRecommendedProducts();
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_recommendations', jsonEncode(recs));
    } catch (_) {
      if (mounted && _apiRecommendations.isEmpty) {
        setState(() => _recommendationsLoading = false);
      }
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
    final canProceed = await guest.requireAuth(context);
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
    if (productId != null) {
      MarketplaceService.trackProductView(productId).catchError((_) {});
    }
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
          final canProceed = await guest.requireAuth(context);
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
      builder: (_) => HomeFilterSheet(
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
        builder: (_) => SeeAllScreen(
          title: title,
          items: items,
          isStore: isStore,
          onProductTap: _onProductTap,
          onStoreTap: (store) async {
            final canProceed = await guest.requireAuth(context);
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

  int? _productId(dynamic product) {
    final id = product['id'];
    if (id == null) return null;
    if (id is int) return id;
    return int.tryParse(id.toString());
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _sortItems(_applyAllFilters(_products));
    final filteredTrending = _sortItems(_applyAllFilters(_trendingProducts));
    final filteredSponsored = _filterByLocation(_sponsoredStores);
    final filteredStores = _filterByLocation(_stores);
    final filteredRecommended = _getRecommendedProducts();

    final dist = _distanceFilterKm;
    final village = _userVillage;
    final villageId = _userVillageId;
    final city = _userCity;
    final cityId = _userCityId;
    final country = _userCountry;
    final countryCode = _userCountryCode;

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
              if (hasActiveFilters)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_locationFilterMode != 'all')
                            FilterChipWidget(
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
                            FilterChipWidget(
                              label: '${dist.round()} km',
                              icon: Icons.straighten,
                              onRemove: () {
                                setState(() => _distanceFilterKm = null);
                                _saveFilterPreferences();
                                _updateRecommendedProducts();
                              },
                            ),
                          if (_selectedMinPrice > 0 ||
                              _selectedMaxPrice != double.infinity)
                            FilterChipWidget(
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
                            FilterChipWidget(
                              label: _selectedCategory!,
                              icon: Icons.category,
                              onRemove: () {
                                setState(() => _selectedCategory = null);
                                _saveFilterPreferences();
                                _updateRecommendedProducts();
                              },
                            ),
                          if (_minRating > 0)
                            FilterChipWidget(
                              label: '${_minRating.round()}+ ★',
                              icon: Icons.star,
                              onRemove: () {
                                setState(() => _minRating = 0);
                                _saveFilterPreferences();
                                _updateRecommendedProducts();
                              },
                            ),
                          if (_sortBy != 'newest')
                            FilterChipWidget(
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
              if (!_recommendationsLoading &&
                  !_productsLoading &&
                  filteredRecommended.isNotEmpty) ...[
                SectionHeader(
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
                      itemBuilder: (context, i) {
                        final product = filteredRecommended[i];
                        final pid = _productId(product);
                        return ProductCard(
                          product: product,
                          onTap: () => _onProductTap(product),
                          showFavorite: pid != null,
                          isFavorite: pid != null && _favoriteIds.contains(pid),
                          onFavoriteToggle: pid != null
                              ? () => _toggleFavorite(pid)
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (!_sponsoredLoading && filteredSponsored.isNotEmpty) ...[
                SectionHeader(
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
                      itemBuilder: (context, i) => StoreCard(
                        store: filteredSponsored[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoreProductsScreen(
                              storeId: filteredSponsored[i]['id'],
                            ),
                          ),
                        ),
                        isSponsored: true,
                        sponsoredLabel: t('top') ?? 'TOP',
                      ),
                    ),
                  ),
                ),
              ],
              if (!_trendingLoading && filteredTrending.isNotEmpty) ...[
                SectionHeader(
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
                      itemBuilder: (context, i) {
                        final product = filteredTrending[i];
                        final pid = _productId(product);
                        return ProductCard(
                          product: product,
                          onTap: () => _onProductTap(product),
                          isTrending: true,
                          trendingLabel: t('hot') ?? 'HOT',
                          showFavorite: pid != null,
                          isFavorite: pid != null && _favoriteIds.contains(pid),
                          onFavoriteToggle: pid != null
                              ? () => _toggleFavorite(pid)
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (!_storesLoading && filteredStores.isNotEmpty) ...[
                SectionHeader(
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
                      itemBuilder: (context, i) => StoreCard(
                        store: filteredStores[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoreProductsScreen(
                              storeId: filteredStores[i]['id'],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
              if (_productsLoading)
                const ProductGridSkeleton()
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
            final pid = _productId(product);
            return ProductCard(
              product: product,
              onTap: () => _onProductTap(product),
              showFavorite: pid != null,
              isFavorite: pid != null && _favoriteIds.contains(pid),
              onFavoriteToggle: pid != null ? () => _toggleFavorite(pid) : null,
            );
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
        delegate: SliverChildBuilderDelegate((context, i) {
          final product = products[i];
          final pid = _productId(product);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ProductListTile(
              product: product,
              onTap: () => _onProductTap(product),
              showFavorite: pid != null,
              isFavorite: pid != null && _favoriteIds.contains(pid),
              onFavoriteToggle: pid != null ? () => _toggleFavorite(pid) : null,
            ),
          );
        }, childCount: displayCount),
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
