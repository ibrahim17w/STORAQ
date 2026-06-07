import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/store_service.dart';
import '../services/product_service.dart';

class StoreState {
  final Store? myStore;
  final List<Product> catalog;
  final List<dynamic> staff;
  final bool isLoading;
  final String? error;

  const StoreState({
    this.myStore,
    this.catalog = const [],
    this.staff = const [],
    this.isLoading = false,
    this.error,
  });

  StoreState copyWith({
    Store? myStore,
    List<Product>? catalog,
    List<dynamic>? staff,
    bool? isLoading,
    String? error,
  }) {
    return StoreState(
      myStore: myStore ?? this.myStore,
      catalog: catalog ?? this.catalog,
      staff: staff ?? this.staff,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class StoreNotifier extends StateNotifier<StoreState> {
  StoreNotifier() : super(const StoreState());

  Future<void> loadMyStore() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final store = await StoreService.getMyStore();
      state = state.copyWith(myStore: store, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadCatalog() async {
    try {
      final products = await ProductService.fetchMyStoreProducts();
      state = state.copyWith(catalog: products);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> loadStaff() async {
    try {
      final staff = await StoreService.fetchMyStoreStaff();
      state = state.copyWith(staff: staff);
    } catch (_) {}
  }

  Future<void> refresh() async {
    await Future.wait([loadMyStore(), loadCatalog(), loadStaff()]);
  }

  void clearStore() {
    state = const StoreState();
  }
}

final storeProvider =
    StateNotifierProvider<StoreNotifier, StoreState>((ref) {
  return StoreNotifier();
});
