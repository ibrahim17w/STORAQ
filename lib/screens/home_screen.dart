// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../lang/translations.dart';
import '../providers/locale_provider.dart';
import '../widgets/theme_toggle.dart';
import '../utils/location_helper.dart';
import 'store_products_screen.dart';
import 'product_detail_screen.dart';
import '../utils/product_store_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/marketplace_service.dart';
import '../services/store_service.dart';
import '../services/favorites_service.dart';
import '../services/currency_service.dart';
import '../services/categories_service.dart';
import '../utils/category_helper.dart';
import '../widgets/product/product_card.dart';
import '../widgets/product/product_list_tile.dart';
import '../widgets/store/store_card.dart';
import '../widgets/home/home_search_bar.dart';
import '../widgets/common/cart_icon_button.dart';
import '../widgets/common/section_header.dart';
import '../widgets/common/filter_chip_widget.dart';
import '../widgets/skeletons/product_skeleton.dart';
import '../widgets/search/search_bottom_sheet.dart';
import '../widgets/home_filter_sheet.dart';
import '../widgets/guest_login_sheet.dart' as guest;
import '../screens/see_all_screen.dart';
import '../utils/tr.dart';
import '../utils/location_display_helper.dart';
import 'dart:convert';
import '../models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/products_provider.dart';
import '../providers/filter_provider.dart';
import '../providers/viewer_location_provider.dart';
import '../services/viewer_location_service.dart';

/// Bumped when the user returns to the Home tab so sponsored content refreshes.
final homeSponsoredRefreshTick = ValueNotifier<int>(0);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  List<Store> _stores = [];
  List<Store> _sponsoredStores = [];
  List<Product> _sponsoredProducts = [];
  bool _storesLoading = true;
  bool _sponsoredLoading = true;
  bool _sponsoredProductsLoading = true;
  bool _isGridView = true;

  // Location state (geo-derived)
  Position? _userPosition;
  String? _userVillage;
  String? _userCity;
  String? _userCountry;
  bool _locationLoading = false;

  // Canonical location IDs
  String? _userCityId;
  String? _userVillageId;
  String? _userCountryCode;

  List<Category> _categories = [];

  String? _categoryLabel(int? id) {
    if (id == null) return null;
    for (final cat in _categories) {
      if (cat.id == id) return CategoryHelper.displayName(cat);
    }
    return null;
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await CategoriesService.fetchCategories();
      if (mounted) setState(() => _categories = cats);
    } catch (_) {}
  }

  List<FilterCategoryOption> get _filterCategoryOptions => _categories
      .where((c) => c.id != null)
      .map(
        (c) => FilterCategoryOption(
          id: c.id!,
          label: CategoryHelper.displayName(c),
        ),
      )
      .toList();

  String _locationModeString(LocationFilterMode mode) {
    switch (mode) {
      case LocationFilterMode.none:
        return 'all';
      case LocationFilterMode.city:
        return 'city';
      case LocationFilterMode.village:
        return 'village';
      case LocationFilterMode.nearby:
        return 'country';
    }
  }

  LocationFilterMode _parseLocationMode(String mode) {
    switch (mode) {
      case 'village':
        return LocationFilterMode.village;
      case 'city':
        return LocationFilterMode.city;
      case 'country':
        return LocationFilterMode.nearby;
      default:
        return LocationFilterMode.none;
    }
  }

  String _sortByString(SortBy sort) {
    switch (sort) {
      case SortBy.newest:
        return 'newest';
      case SortBy.priceAsc:
        return 'price_low';
      case SortBy.priceDesc:
        return 'price_high';
      case SortBy.rating:
        return 'newest';
      case SortBy.popular:
        return 'popular';
    }
  }

  SortBy _parseSortBy(String sort) {
    switch (sort) {
      case 'price_low':
        return SortBy.priceAsc;
      case 'price_high':
        return SortBy.priceDesc;
      case 'popular':
        return SortBy.popular;
      default:
        return SortBy.newest;
    }
  }

  // Provider type conversion helpers
  Set<int> _favoriteIds = {};
  Set<int> _favoriteStoreIds = {};

  // Currency display settings (defaults: no conversion until loaded)
  Map<String, dynamic> _currencySettings = {
    'display_currency': null,
    'show_both_prices': false,
    'exchange_rates': <dynamic>[],
  };

  static final List<String> _pendingViews = [];
  static Timer? _viewFlushTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    homeSponsoredRefreshTick.addListener(_onSponsoredRefreshRequested);
    FavoritesService.favoriteIdsNotifier.addListener(_onFavoritesChanged);
    FavoritesService.favoriteStoreIdsNotifier.addListener(
      _onStoreFavoritesChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrapHomeData();
    });
  }

  void _onSponsoredRefreshRequested() {
    if (!mounted) return;
    unawaited(_loadSponsoredProducts(skipCache: true));
    unawaited(_loadSponsored());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onSponsoredRefreshRequested();
    }
  }

  void _bootstrapHomeData() {
    unawaited(_loadGridPreference());
    unawaited(_loadFavorites());
    unawaited(_loadFavoriteStores());
    unawaited(_loadCategories());
    unawaited(_loadCachedViewerLocation());

    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_loadStores());
      unawaited(_loadSponsored());
      unawaited(_loadSponsoredProducts());
    });

    // GPS is slow/unreliable on desktop — skip on launch.
    if (Platform.isAndroid || Platform.isIOS) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) unawaited(_initLocation());
      });
    }

    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      ref.read(productsProvider.notifier).loadAll();
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) unawaited(_loadCurrencySettings());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    homeSponsoredRefreshTick.removeListener(_onSponsoredRefreshRequested);
    FavoritesService.favoriteIdsNotifier.removeListener(_onFavoritesChanged);
    FavoritesService.favoriteStoreIdsNotifier.removeListener(
      _onStoreFavoritesChanged,
    );
    _viewFlushTimer?.cancel();
    _flushViews();
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) {
      setState(
        () => _favoriteIds = Set<int>.from(
          FavoritesService.favoriteIdsNotifier.value,
        ),
      );
    }
  }

  void _onStoreFavoritesChanged() {
    if (mounted) {
      setState(
        () => _favoriteStoreIds = Set<int>.from(
          FavoritesService.favoriteStoreIdsNotifier.value,
        ),
      );
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final ids = await FavoritesService.getLocalFavoriteIds();
      if (mounted) setState(() => _favoriteIds = ids.toSet());
    } catch (_) {}
  }

  Future<void> _loadCurrencySettings() async {
    try {
      final settings = await CurrencyService.getCurrencySettings();
      if (mounted) setState(() => _currencySettings = settings.toLegacyMap());
    } catch (_) {}
  }

  Future<void> _loadFavoriteStores() async {
    try {
      final ids = await FavoritesService.getLocalFavoriteStoreIds();
      if (mounted) setState(() => _favoriteStoreIds = ids.toSet());
    } catch (_) {}
  }

  Map<String, dynamic> _asMap(dynamic item) {
    if (item is Product) return item.toJson();
    if (item is Store) return item.toJson();
    if (item is Map<String, dynamic>) return item;
    return {};
  }

  Future<void> _toggleFavorite(int productId, Product product) async {
    await FavoritesService.toggleFavorite(productId, product: product.toJson());
  }

  Future<void> _toggleFavoriteStore(int storeId, Store store) async {
    await FavoritesService.toggleFavoriteStore(storeId, store: store.toJson());
  }

  int? _storeId(Store store) => store.intId;

  Future<void> _loadGridPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _isGridView = prefs.getBool('home_grid_view') ?? true);
  }


  Future<void> _toggleViewMode() async {
    final newMode = !_isGridView;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('home_grid_view', newMode);
    if (mounted) setState(() => _isGridView = newMode);
  }

  // ── Location ──
  Future<void> _initLocation() async {
    if (!mounted) return;
    setState(() => _locationLoading = true);
    Position? pos;
    try {
      pos = await LocationHelper.getCurrentPosition().timeout(
        const Duration(seconds: 4),
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
    unawaited(_loadSponsoredProducts());
    if (pos != null &&
        _userVillage == null &&
        _userCity == null &&
        _userCountry == null) {
      if (mounted && ref.read(filterProvider).maxDistance == null) {
        ref.read(filterProvider.notifier).setMaxDistance(5.0);
      }
    }
  }

  void _inferUserLocationFromStores() {
    if (_userPosition == null || _stores.isEmpty) return;
    final uLat = _userPosition!.latitude;
    final uLng = _userPosition!.longitude;

    _reverseGeocodeUserLocation(uLat, uLng);

    final List<Store> villageStores = [];
    final List<Store> closeStores = [];
    final List<Store> regionStores = [];
    Store? nearest;
    double minDist = double.infinity;

    for (final store in _stores) {
      final sLat = store.lat;
      final sLng = store.lng;
      if (sLat == null || sLng == null) continue;
      final d = LocationHelper.distanceKm(uLat, uLng, sLat, sLng);
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
        final fallback = nearest.city;
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
        bestCountry = nearest.country;
      }
      if (bestCountry != null) {
        setState(() => _userCountry = bestCountry);
      }
    }
    unawaited(_loadSponsoredProducts(skipCache: true));
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
            final countryName = addr['country']?.toString();
            if (countryName != null) _userCountry = countryName;
          }
        });
        unawaited(ViewerLocationService.saveLocation(
          countryCode: _userCountryCode,
          countryName: _userCountry,
          city: _userCity,
          cityId: _userCityId,
          village: _userVillage,
          villageId: _userVillageId,
          lat: lat,
          lng: lng,
        ));
        if (mounted) {
          ref.read(viewerLocationProvider.notifier).setCountry(
                countryCode: _userCountryCode,
                countryName: _userCountry,
              );
        }
        unawaited(_loadSponsoredProducts());
      }
    } catch (e) {
      // Silent fail
    }
  }

  String? _mostCommonField(List<dynamic> stores, String field) {
    final Map<String, int> counts = {};
    for (final s in stores) {
      final m = _asMap(s);
      final val = m[field]?.toString().trim();
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
    final m = _asMap(item);
    final village = m['village']?.toString();
    if (village != null && village.isNotEmpty) return village;
    final storeVillage = m['store_village']?.toString();
    if (storeVillage != null && storeVillage.isNotEmpty) return storeVillage;
    final shopName = m['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty && _stores.isNotEmpty) {
      for (final store in _stores) {
        if (store.name == shopName) {
          return store.village;
        }
      }
    }
    return null;
  }

  String? _getItemCity(dynamic item) {
    final m = _asMap(item);
    final cityId = m['city_id']?.toString();
    if (cityId != null && cityId.isNotEmpty) {
      return cityId;
    }
    final city = m['city']?.toString();
    if (city != null && city.isNotEmpty && city.toLowerCase() != 'null')
      return city;
    final storeCity = m['store_city']?.toString();
    if (storeCity != null &&
        storeCity.isNotEmpty &&
        storeCity.toLowerCase() != 'null')
      return storeCity;
    final shopName = m['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty && _stores.isNotEmpty) {
      for (final store in _stores) {
        if (store.name == shopName) {
          return store.cityId ?? store.city;
        }
      }
    }
    return null;
  }

  String? _getItemCountry(dynamic item) {
    final m = _asMap(item);
    final country = m['country']?.toString();
    if (country != null && country.isNotEmpty) return country;
    final storeCountry = m['store_country']?.toString();
    if (storeCountry != null && storeCountry.isNotEmpty) return storeCountry;
    final shopName = m['shop_name']?.toString();
    if (shopName != null && shopName.isNotEmpty && _stores.isNotEmpty) {
      for (final store in _stores) {
        if (store.name == shopName) {
          return store.country;
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

    switch (_locationModeString(ref.read(filterProvider).locationMode)) {
      case 'all':
        return items;
      case 'village':
        if (villageId != null && villageId.isNotEmpty) {
          final villageItems = items.where((item) {
            final m = _asMap(item);
            final itemVillageId = m['village_id']?.toString();
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
            final m = _asMap(item);
            final itemCityId = m['city_id']?.toString();
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
            final m = _asMap(item);
            final itemCc = m['country_code']?.toString();
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
            final m = _asMap(item);
            final itemCityId = m['city_id']?.toString();
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
            final m = _asMap(item);
            final itemCc = m['country_code']?.toString();
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
    final distanceFilterKm = ref.read(filterProvider).maxDistance;
    if (distanceFilterKm == null || _userPosition == null) return items;
    final uLat = _userPosition!.latitude;
    final uLng = _userPosition!.longitude;
    return items.where((item) {
      final m = _asMap(item);
      final sLat = m['lat'];
      final sLng = m['lng'];
      if (sLat == null || sLng == null) return false;
      final lat = sLat is num
          ? sLat.toDouble()
          : double.tryParse(sLat.toString());
      final lng = sLng is num
          ? sLng.toDouble()
          : double.tryParse(sLng.toString());
      if (lat == null || lng == null) return false;
      final d = LocationHelper.distanceKm(uLat, uLng, lat, lng);
      return d <= distanceFilterKm;
    }).toList();
  }

  List<dynamic> _filterByPrice(List<dynamic> items) {
    final fs = ref.read(filterProvider);
    final selectedMinPrice = fs.minPrice ?? 0;
    final selectedMaxPrice = fs.maxPrice ?? double.infinity;
    return items.where((item) {
      final m = _asMap(item);
      final price = CurrencyService.comparablePrice(m, _currencySettings);
      final passesMin = price >= selectedMinPrice;
      final passesMax =
          selectedMaxPrice == double.infinity || price <= selectedMaxPrice;
      return passesMin && passesMax;
    }).toList();
  }

  List<dynamic> _filterByCategory(List<dynamic> items) {
    final categoryId = ref.read(filterProvider).categoryId;
    if (categoryId == null) return items;
    return items.where((item) {
      final m = _asMap(item);
      final rawId = m['category_id'] ?? m['categoryId'];
      final parsedId = rawId is int
          ? rawId
          : int.tryParse(rawId?.toString() ?? '');
      if (parsedId == categoryId) return true;

      Category? selectedCategory;
      for (final c in _categories) {
        if (c.id == categoryId) {
          selectedCategory = c;
          break;
        }
      }
      if (selectedCategory == null) return false;
      final itemCategory = m['category']?.toString().toLowerCase() ?? '';
      return itemCategory.isNotEmpty &&
          itemCategory == selectedCategory.name.toLowerCase();
    }).toList();
  }

  List<dynamic> _filterByRating(List<dynamic> items) {
    final minRating = ref.read(filterProvider).minRating ?? 0;
    if (minRating <= 0) return items;
    return items.where((item) {
      final m = _asMap(item);
      final raw = m['rating'];
      final rating = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '0') ?? 0;
      return rating >= minRating;
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
    switch (_sortByString(ref.read(filterProvider).sortBy)) {
      case 'price_low':
        sorted.sort((a, b) {
          final aPrice = CurrencyService.comparablePrice(_asMap(a), _currencySettings);
          final bPrice = CurrencyService.comparablePrice(_asMap(b), _currencySettings);
          return aPrice.compareTo(bPrice);
        });
        break;
      case 'price_high':
        sorted.sort((a, b) {
          final aPrice = CurrencyService.comparablePrice(_asMap(a), _currencySettings);
          final bPrice = CurrencyService.comparablePrice(_asMap(b), _currencySettings);
          return bPrice.compareTo(aPrice);
        });
        break;
      case 'popular':
        sorted.sort((a, b) {
          final am = _asMap(a);
          final bm = _asMap(b);
          final aViews = (am['view_count'] is num)
              ? (am['view_count'] as num).toInt()
              : int.tryParse(am['view_count']?.toString() ?? '0') ?? 0;
          final bViews = (bm['view_count'] is num)
              ? (bm['view_count'] as num).toInt()
              : int.tryParse(bm['view_count']?.toString() ?? '0') ?? 0;
          return bViews.compareTo(aViews);
        });
        break;
      case 'newest':
      default:
        break;
    }
    return sorted;
  }


  Future<void> _loadStores() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_stores');
      if (cached != null && cached.isNotEmpty) {
        final decoded = (jsonDecode(cached) as List<dynamic>)
            .map((e) => Store.fromJson(e as Map<String, dynamic>))
            .toList();
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
        await prefs.setString('cached_stores', jsonEncode(stores.map((s) => s.toJson()).toList()));
        if (_userPosition != null && _stores.isNotEmpty) {
          _inferUserLocationFromStores();
        }
        unawaited(_loadSponsoredProducts(skipCache: true));
      }
    } catch (_) {
      if (mounted && _stores.isEmpty) {
        setState(() => _storesLoading = false);
      }
    }
  }


  Future<void> _loadCachedViewerLocation() async {
    try {
      final cached = await ViewerLocationService.getLocation();
      if (!mounted) return;
      final city = cached['city']?.toString();
      final cityId = cached['city_id']?.toString();
      final village = cached['village']?.toString();
      final villageId = cached['village_id']?.toString();
      final country = cached['country']?.toString();
      final countryCode = cached['country_code']?.toString();
      final lat = cached['lat'] as double?;
      final lng = cached['lng'] as double?;
      setState(() {
        _userCity ??= city;
        _userCityId ??= cityId;
        _userVillage ??= village;
        _userVillageId ??= villageId;
        _userCountry ??= country;
        _userCountryCode ??= countryCode;
        if (_userPosition == null && lat != null && lng != null) {
          _userPosition = Position(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        }
      });
      final hasGeo = (city != null && city.isNotEmpty) ||
          (cityId != null && cityId.isNotEmpty) ||
          (village != null && village.isNotEmpty) ||
          (country != null && country.isNotEmpty) ||
          (countryCode != null && countryCode.isNotEmpty) ||
          (lat != null && lng != null);
      if (hasGeo) {
        unawaited(_loadSponsoredProducts(skipCache: true));
      }
    } catch (_) {}
  }

  Map<String, String?> _sponsoredViewerParams() {
    final viewerLocation = ref.read(viewerLocationProvider);
    return {
      'lat': _userPosition?.latitude.toString(),
      'lng': _userPosition?.longitude.toString(),
      'village': _userVillage,
      'city': _userCity,
      'country': _userCountry ?? viewerLocation.countryName,
      'countryCode': _userCountryCode ?? viewerLocation.countryCode,
      'cityId': _userCityId,
    };
  }

  String _sponsoredCacheKey() {
    final p = _sponsoredViewerParams();
    return [
      p['lat'],
      p['lng'],
      p['cityId'] ?? p['city'],
      p['countryCode'] ?? p['country'],
      p['village'],
    ].where((e) => e != null && e!.isNotEmpty).join('|');
  }

  Future<void> _loadSponsoredProducts({bool skipCache = false}) async {
    final cacheKey = 'cached_sponsored_products_${_sponsoredCacheKey()}';

    if (!skipCache) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(cacheKey);
        if (cached != null && cached.isNotEmpty) {
          final decoded = (jsonDecode(cached) as List<dynamic>)
              .map((e) => Product.fromJson(e as Map<String, dynamic>))
              .toList();
          if (mounted) {
            setState(() {
              _sponsoredProducts = decoded;
              _sponsoredProductsLoading = false;
            });
          }
        }
      } catch (_) {}
    }

    try {
      final params = _sponsoredViewerParams();
      final products = await MarketplaceService.fetchSponsoredProducts(
        lat: params['lat'] != null ? double.tryParse(params['lat']!) : null,
        lng: params['lng'] != null ? double.tryParse(params['lng']!) : null,
        village: params['village'],
        city: params['city'],
        country: params['country'],
        countryCode: params['countryCode'],
        cityId: params['cityId'],
      );
      if (mounted) {
        setState(() {
          _sponsoredProducts = products;
          _sponsoredProductsLoading = false;
        });
      }
      final prefs = await SharedPreferences.getInstance();
      if (products.isNotEmpty) {
        await prefs.setString(
          cacheKey,
          jsonEncode(products.map((p) => p.toJson()).toList()),
        );
      } else {
        await prefs.remove(cacheKey);
      }
    } catch (_) {
      if (mounted && _sponsoredProducts.isEmpty) {
        setState(() => _sponsoredProductsLoading = false);
      }
    }
  }

  Future<void> _loadSponsored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_sponsored');
      if (cached != null && cached.isNotEmpty) {
        final decoded = (jsonDecode(cached) as List<dynamic>)
            .map((e) => Store.fromJson(e as Map<String, dynamic>))
            .toList();
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
      await prefs.setString('cached_sponsored', jsonEncode(sponsored.map((s) => s.toJson()).toList()));
    } catch (_) {
      if (mounted && _sponsoredStores.isEmpty) {
        setState(() => _sponsoredLoading = false);
      }
    }
  }

  Future<void> _refreshAll() async {
    setState(() {
      _storesLoading = true;
      _sponsoredLoading = true;
      _sponsoredProductsLoading = true;
    });
    await Future.wait([
      ref.read(productsProvider.notifier).loadAll(),
      _loadStores(),
      _loadSponsored(),
      _loadSponsoredProducts(skipCache: true),
    ]);
  }

  void _onProductTap(dynamic product) async {
    final canProceed = await guest.requireAuth(context);
    if (!canProceed) return;
    final p = product is Product ? product : Product.fromJson(_asMap(product));
    _trackProductView(p);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: productToDetailMap(p),
        ),
      ),
    );
  }

  void _trackProductView(Product product) {
    final productName = product.name ?? '';
    if (productName.isEmpty) return;
    _pendingViews.remove(productName);
    _pendingViews.insert(0, productName);
    if (_pendingViews.length > 20) _pendingViews.removeLast();
    _viewFlushTimer?.cancel();
    _viewFlushTimer = Timer(const Duration(seconds: 2), _flushViews);
    final productId = product.id;
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
        products: ref.read(productsProvider).feed.map((p) => p.toJson()).toList(),
        stores: _stores.map((s) => s.toJson()).toList(),
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
    final fs = ref.read(filterProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HomeFilterSheet(
        locationFilterMode: _locationModeString(fs.locationMode),
        userVillage: _userVillage,
        userCity: _userCity,
        userCountry: _userCountry,
        userCityId: _userCityId,
        userVillageId: _userVillageId,
        userCountryCode: _userCountryCode,
        hasPosition: _userPosition != null,
        distanceFilterKm: fs.maxDistance,
        selectedMinPrice: fs.minPrice ?? 0,
        selectedMaxPrice: fs.maxPrice ?? double.infinity,
        selectedCategoryId: fs.categoryId,
        categories: _filterCategoryOptions,
        minRating: fs.minRating ?? 0,
        sortBy: _sortByString(fs.sortBy),
        onApply: (filters) {
          final notifier = ref.read(filterProvider.notifier);
          notifier.setLocationMode(
            _parseLocationMode(filters['locationFilterMode'] as String? ?? 'all'),
          );
          notifier.setMaxDistance(filters['distanceFilterKm'] as double?);
          final minP = filters['minPrice'] as double?;
          final maxP = filters['maxPrice'] as double?;
          notifier.setPriceRange(
            min: (minP == null || minP <= 0) ? null : minP,
            max: (maxP == null || maxP == double.infinity) ? null : maxP,
          );
          notifier.setCategory(filters['categoryId'] as int?);
          final mr = filters['minRating'] as double?;
          notifier.setMinRating((mr == null || mr <= 0) ? null : mr);
          notifier.setSortBy(
            _parseSortBy(filters['sortBy'] as String? ?? 'newest'),
          );
          Navigator.pop(context);
        },
        onReset: () {
          ref.read(filterProvider.notifier).clearAll();
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
    final mapped = items.map((i) => _asMap(i)).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeeAllScreen(
          title: title,
          items: mapped,
          isStore: isStore,
          currencySettings: _currencySettings,
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

  int? _productId(Product product) => product.intId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productsState = ref.watch(productsProvider);
    final filterState = ref.watch(filterProvider);

    final productsLoading = productsState.isLoading;

    final filteredProducts = _sortItems(_applyAllFilters(productsState.feed));
    final filteredTrending = _sortItems(_applyAllFilters(productsState.trending));
    // Paid placements should stay visible regardless of the user's location filter.
    final filteredSponsored = _sponsoredStores;
    final filteredStores = _filterByLocation(_stores);

    // Compute recommendations from provider data
    List<Product> filteredRecommended;
    final apiRecs = productsState.recommendations;
    if (apiRecs.isNotEmpty) {
      final filtered = _applyAllFilters(apiRecs);
      filteredRecommended = (filtered.length > 6
              ? filtered.sublist(0, 6)
              : List<dynamic>.from(filtered))
          .cast<Product>()
          .toList();
    } else {
      final pool = _applyAllFilters(productsState.feed);
      filteredRecommended = (pool.length > 6
              ? pool.sublist(0, 6)
              : List<dynamic>.from(pool))
          .cast<Product>()
          .toList();
    }

    // Derive filter display values from provider state
    final _locationFilterMode = _locationModeString(filterState.locationMode);
    final dist = filterState.maxDistance;
    final _selectedMinPrice = filterState.minPrice ?? 0.0;
    final _selectedMaxPrice = filterState.maxPrice ?? double.infinity;
    final _selectedCategory = _categoryLabel(filterState.categoryId);
    final _minRating = filterState.minRating ?? 0.0;
    final _sortBy = _sortByString(filterState.sortBy);

    final village = _userVillage;
    final villageId = _userVillageId;
    final city = _userCity;
    final cityId = _userCityId;
    final country = _userCountry;
    final countryCode = _userCountryCode;

    // hasActiveFilters mirrors the filterProvider exactly so the chip bar
    // visibly confirms that geo is active on first launch.
    final bool hasActiveFilters = filterState.hasActiveFilters;

    ref.listen<ViewerLocationState>(viewerLocationProvider, (prev, next) {
      if (prev?.countryCode != next.countryCode ||
          prev?.countryName != next.countryName) {
        unawaited(_loadSponsoredProducts(skipCache: true));
      }
    });

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? theme.scaffoldBackgroundColor
          : const Color(0xFFF8F9FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const CartIconButton(),
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
                    height: 148,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsetsDirectional.only(start: 20),
                      itemCount: filteredSponsored.length,
                      itemBuilder: (context, i) {
                        final store = filteredSponsored[i] as Store;
                        final sid = _storeId(store);
                        final storeMap = store.toJson();
                        return StoreCard(
                          store: storeMap,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StoreProductsScreen(storeId: store.id),
                            ),
                          ),
                          isSponsored: true,
                          sponsoredLabel: t('top') ?? 'TOP',
                          showFavorite: sid != null,
                          isFavorite:
                              sid != null && _favoriteStoreIds.contains(sid),
                          onFavoriteToggle: sid != null
                              ? () => _toggleFavoriteStore(sid, store)
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: HomeSearchBar(
                    onSearchTap: _openSearch,
                    onFilterTap: _openFilterSheet,
                    hasActiveFilters: hasActiveFilters,
                  ),
                ),
              ),
              // ─── Sponsored Products ────────────────────────────────────
              // Always rendered so the surface is discoverable. Shows
              // skeletons while loading, real cards once campaigns arrive,
              // and an inline empty-state card otherwise.
              SectionHeader(
                title: t('sponsored_products'),
                onSeeAll: _sponsoredProducts.isEmpty
                    ? null
                    : () => _openSeeAll(
                          title: t('sponsored_products'),
                          items: _sponsoredProducts,
                          isStore: false,
                        ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      _sponsoredProducts.isEmpty && !_sponsoredProductsLoading
                          ? 96
                          : 252,
                  child: _sponsoredProductsLoading
                      ? ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsetsDirectional.only(start: 20),
                          itemCount: 3,
                          itemBuilder: (context, _) => Container(
                            width: 160,
                            margin:
                                const EdgeInsetsDirectional.only(end: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        )
                      : _sponsoredProducts.isEmpty
                          ? Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  20, 0, 20, 12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.amber
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.campaign_outlined,
                                        color: Colors.amber,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            t('no_sponsored_products_yet'),
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            t('sponsored_empty_hint'),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsetsDirectional.only(start: 20),
                              itemCount: _sponsoredProducts.length,
                              itemBuilder: (context, i) {
                                final product = _sponsoredProducts[i];
                                final pid = _productId(product);
                                return ProductCard(
                                  product: product.toJson(),
                                  compact: true,
                                  onTap: () => _onProductTap(product),
                                  showFavorite: pid != null,
                                  isFavorite: pid != null &&
                                      _favoriteIds.contains(pid),
                                  onFavoriteToggle: pid != null
                                      ? () => _toggleFavorite(pid, product)
                                      : null,
                                  currencySettings: _currencySettings,
                                  isSponsored: true,
                                  sponsoredLabel: t('sponsored'),
                                );
                              },
                            ),
                ),
              ),
              if (hasActiveFilters)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        if (_locationFilterMode != 'all')
                          FilterChipWidget(
                            label: () {
                              switch (_locationFilterMode) {
                                case 'village':
                                  final localizedVillage =
                                      LocationDisplayHelper.localizedVillageLabel(
                                    village,
                                    villageId: villageId,
                                  );
                                  if (localizedVillage.isNotEmpty) {
                                    return localizedVillage;
                                  }
                                  return t('nearby') ?? 'Nearby';
                                case 'city':
                                  final localizedCity =
                                      LocationDisplayHelper.localizedCityLabel(
                                    city: city,
                                    cityId: cityId,
                                  );
                                  if (localizedCity.isNotEmpty) {
                                    return localizedCity;
                                  }
                                  return t('nearby') ?? 'Nearby';
                                case 'country':
                                  final localizedCountry =
                                      LocationDisplayHelper.localizedCountryLabel(
                                    country: country,
                                    countryCode: countryCode,
                                  );
                                  if (localizedCountry.isNotEmpty) {
                                    return localizedCountry;
                                  }
                                  return t('unknown_country') ??
                                      'Unknown Country';
                                default:
                                  return t('nearby') ?? 'Nearby';
                              }
                            }(),
                            icon: Icons.location_on_outlined,
                            onRemove: () {
                              ref
                                  .read(filterProvider.notifier)
                                  .setLocationMode(LocationFilterMode.none);
                            },
                          ),
                        if (dist != null)
                          FilterChipWidget(
                            label: '${dist.round()} km',
                            icon: Icons.straighten,
                            onRemove: () {
                              ref
                                  .read(filterProvider.notifier)
                                  .setMaxDistance(null);
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
                              ref.read(filterProvider.notifier).setPriceRange(
                                    min: null,
                                    max: null,
                                  );
                            },
                          ),
                        if (_selectedCategory != null)
                          FilterChipWidget(
                            label: _selectedCategory!,
                            icon: Icons.category_outlined,
                            onRemove: () {
                              ref
                                  .read(filterProvider.notifier)
                                  .setCategory(null);
                            },
                          ),
                        if (_minRating > 0)
                          FilterChipWidget(
                            label: '${_minRating.round()}+ ★',
                            icon: Icons.star_outline,
                            onRemove: () {
                              ref
                                  .read(filterProvider.notifier)
                                  .setMinRating(null);
                            },
                          ),
                        if (_sortBy != 'newest')
                          FilterChipWidget(
                            label: _sortLabels[_sortBy] ?? _sortBy,
                            icon: Icons.sort,
                            onRemove: () {
                              ref
                                  .read(filterProvider.notifier)
                                  .setSortBy(SortBy.newest);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              if (!productsLoading &&
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
                    height: 252,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsetsDirectional.only(start: 20),
                      itemCount: filteredRecommended.length,
                      itemBuilder: (context, i) {
                        final product = filteredRecommended[i];
                        final pid = _productId(product);
                        return ProductCard(
                          product: product.toJson(),
                          compact: true,
                          onTap: () => _onProductTap(product),
                          showFavorite: pid != null,
                          isFavorite: pid != null && _favoriteIds.contains(pid),
                          onFavoriteToggle: pid != null
                              ? () => _toggleFavorite(pid, product)
                              : null,
                          currencySettings: _currencySettings,
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (!productsLoading && filteredTrending.isNotEmpty) ...[
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
                    height: 252,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsetsDirectional.only(start: 20),
                      itemCount: filteredTrending.length,
                      itemBuilder: (context, i) {
                        final product = filteredTrending[i] as Product;
                        final pid = _productId(product);
                        return ProductCard(
                          product: product.toJson(),
                          compact: true,
                          onTap: () => _onProductTap(product),
                          isTrending: true,
                          trendingLabel: t('hot') ?? 'HOT',
                          showFavorite: pid != null,
                          isFavorite: pid != null && _favoriteIds.contains(pid),
                          onFavoriteToggle: pid != null
                              ? () => _toggleFavorite(pid, product)
                              : null,
                          currencySettings: _currencySettings,
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
                    height: 148,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsetsDirectional.only(start: 20),
                      itemCount: filteredStores.length,
                      itemBuilder: (context, i) {
                        final store = filteredStores[i] as Store;
                        final sid = _storeId(store);
                        final storeMap = store.toJson();
                        return StoreCard(
                          store: storeMap,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StoreProductsScreen(storeId: store.id),
                            ),
                          ),
                          showFavorite: sid != null,
                          isFavorite:
                              sid != null && _favoriteStoreIds.contains(sid),
                          onFavoriteToggle: sid != null
                              ? () => _toggleFavoriteStore(sid, store)
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              ],
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          t('latest_products') ?? 'Latest Products',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          t('see_all') ?? 'See All',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (productsLoading)
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
                              ref.read(filterProvider.notifier).clearAll();
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.start,
          children: displayProducts.map((item) {
            final product = item as Product;
            final pid = _productId(product);
            return ProductCard(
              product: product.toJson(),
              onTap: () => _onProductTap(product),
              showFavorite: pid != null,
              isFavorite: pid != null && _favoriteIds.contains(pid),
              onFavoriteToggle: pid != null
                  ? () => _toggleFavorite(pid, product)
                  : null,
              currencySettings: _currencySettings,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProductList(List<dynamic> products) {
    final displayCount = products.length > 30 ? 30 : products.length;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
          final product = products[i] as Product;
          final pid = _productId(product);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ProductListTile(
              product: product.toJson(),
              onTap: () => _onProductTap(product),
              showFavorite: pid != null,
              isFavorite: pid != null && _favoriteIds.contains(pid),
              onFavoriteToggle: pid != null
                  ? () => _toggleFavorite(pid, product)
                  : null,
              currencySettings: _currencySettings,
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
