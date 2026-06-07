import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/prefs_service.dart';

enum LocationFilterMode { none, city, village, nearby }

enum SortBy { newest, priceAsc, priceDesc, rating, popular }

class FilterState {
  final LocationFilterMode locationMode;
  final double? maxDistance;
  final double? minPrice;
  final double? maxPrice;
  final int? categoryId;
  final double? minRating;
  final SortBy sortBy;
  final String? selectedCity;
  final String? selectedVillage;
  final String? selectedCountry;

  const FilterState({
    this.locationMode = LocationFilterMode.city,
    this.maxDistance = 5.0,
    this.minPrice,
    this.maxPrice,
    this.categoryId,
    this.minRating,
    this.sortBy = SortBy.newest,
    this.selectedCity,
    this.selectedVillage,
    this.selectedCountry,
  });

  bool get hasActiveFilters =>
      // Treat the default geo (city + 5km) as the baseline, not an "active filter".
      (locationMode != LocationFilterMode.none &&
              locationMode != LocationFilterMode.city) ||
      (maxDistance != null && maxDistance != 5.0) ||
      minPrice != null ||
      maxPrice != null ||
      categoryId != null ||
      minRating != null ||
      sortBy != SortBy.newest;

  FilterState copyWith({
    LocationFilterMode? locationMode,
    double? maxDistance,
    double? minPrice,
    double? maxPrice,
    int? categoryId,
    double? minRating,
    SortBy? sortBy,
    String? selectedCity,
    String? selectedVillage,
    String? selectedCountry,
  }) {
    return FilterState(
      locationMode: locationMode ?? this.locationMode,
      maxDistance: maxDistance ?? this.maxDistance,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      categoryId: categoryId ?? this.categoryId,
      minRating: minRating ?? this.minRating,
      sortBy: sortBy ?? this.sortBy,
      selectedCity: selectedCity ?? this.selectedCity,
      selectedVillage: selectedVillage ?? this.selectedVillage,
      selectedCountry: selectedCountry ?? this.selectedCountry,
    );
  }
}

class FilterNotifier extends StateNotifier<FilterState> {
  FilterNotifier() : super(const FilterState()) {
    Future.delayed(const Duration(milliseconds: 800), _loadFromPrefs);
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await PrefsService.instance;
      final sortIndex = prefs.getInt('filter_sort') ?? 0;
      // Default to city scope (= LocationFilterMode.city.index) when nothing
      // saved yet; user wanted geo active by default with a 5km fallback.
      final modeIndex =
          prefs.getInt('filter_location_mode') ?? LocationFilterMode.city.index;
      final savedDistance = prefs.getDouble('filter_max_distance');
      state = FilterState(
        sortBy: SortBy.values[sortIndex.clamp(0, SortBy.values.length - 1)],
        locationMode: LocationFilterMode
            .values[modeIndex.clamp(0, LocationFilterMode.values.length - 1)],
        maxDistance: savedDistance ?? 5.0,
        minPrice: prefs.getDouble('filter_min_price'),
        maxPrice: prefs.getDouble('filter_max_price'),
        categoryId: prefs.getInt('filter_category'),
      );
    } catch (_) {}
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await PrefsService.instance;
    await prefs.setInt('filter_sort', state.sortBy.index);
    await prefs.setInt('filter_location_mode', state.locationMode.index);
    if (state.maxDistance != null) {
      await prefs.setDouble('filter_max_distance', state.maxDistance!);
    } else {
      await prefs.remove('filter_max_distance');
    }
    if (state.minPrice != null) {
      await prefs.setDouble('filter_min_price', state.minPrice!);
    } else {
      await prefs.remove('filter_min_price');
    }
    if (state.maxPrice != null) {
      await prefs.setDouble('filter_max_price', state.maxPrice!);
    } else {
      await prefs.remove('filter_max_price');
    }
    if (state.categoryId != null) {
      await prefs.setInt('filter_category', state.categoryId!);
    } else {
      await prefs.remove('filter_category');
    }
    } catch (_) {}
  }

  void setLocationMode(LocationFilterMode mode) {
    state = state.copyWith(locationMode: mode);
    _saveToPrefs();
  }

  void setMaxDistance(double? distance) {
    state = FilterState(
      locationMode: state.locationMode,
      maxDistance: distance,
      minPrice: state.minPrice,
      maxPrice: state.maxPrice,
      categoryId: state.categoryId,
      minRating: state.minRating,
      sortBy: state.sortBy,
      selectedCity: state.selectedCity,
      selectedVillage: state.selectedVillage,
      selectedCountry: state.selectedCountry,
    );
    _saveToPrefs();
  }

  void setPriceRange({double? min, double? max}) {
    state = FilterState(
      locationMode: state.locationMode,
      maxDistance: state.maxDistance,
      minPrice: min,
      maxPrice: max,
      categoryId: state.categoryId,
      minRating: state.minRating,
      sortBy: state.sortBy,
      selectedCity: state.selectedCity,
      selectedVillage: state.selectedVillage,
      selectedCountry: state.selectedCountry,
    );
    _saveToPrefs();
  }

  void setCategory(int? categoryId) {
    state = FilterState(
      locationMode: state.locationMode,
      maxDistance: state.maxDistance,
      minPrice: state.minPrice,
      maxPrice: state.maxPrice,
      categoryId: categoryId,
      minRating: state.minRating,
      sortBy: state.sortBy,
      selectedCity: state.selectedCity,
      selectedVillage: state.selectedVillage,
      selectedCountry: state.selectedCountry,
    );
    _saveToPrefs();
  }

  void setMinRating(double? rating) {
    state = FilterState(
      locationMode: state.locationMode,
      maxDistance: state.maxDistance,
      minPrice: state.minPrice,
      maxPrice: state.maxPrice,
      categoryId: state.categoryId,
      minRating: rating,
      sortBy: state.sortBy,
      selectedCity: state.selectedCity,
      selectedVillage: state.selectedVillage,
      selectedCountry: state.selectedCountry,
    );
  }

  void setSortBy(SortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
    _saveToPrefs();
  }

  void setLocation({String? city, String? village, String? country}) {
    state = state.copyWith(
      selectedCity: city,
      selectedVillage: village,
      selectedCountry: country,
    );
  }

  void clearAll() {
    state = const FilterState();
    _saveToPrefs();
  }
}

final filterProvider =
    StateNotifierProvider<FilterNotifier, FilterState>((ref) {
  return FilterNotifier();
});
