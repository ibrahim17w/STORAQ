import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/marketplace_service.dart';
import '../services/product_service.dart';

class ProductsState {
  final List<Product> feed;
  final List<Product> trending;
  final List<Product> recommendations;
  final bool isLoading;
  final String? error;

  const ProductsState({
    this.feed = const [],
    this.trending = const [],
    this.recommendations = const [],
    this.isLoading = false,
    this.error,
  });

  ProductsState copyWith({
    List<Product>? feed,
    List<Product>? trending,
    List<Product>? recommendations,
    bool? isLoading,
    String? error,
  }) {
    return ProductsState(
      feed: feed ?? this.feed,
      trending: trending ?? this.trending,
      recommendations: recommendations ?? this.recommendations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ProductsNotifier extends StateNotifier<ProductsState> {
  ProductsNotifier() : super(const ProductsState());

  Future<void> loadFeed() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final products = await MarketplaceService.fetchMarketplaceFeed();
      state = state.copyWith(feed: products, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadTrending() async {
    try {
      final trending = await MarketplaceService.fetchTrendingProducts();
      state = state.copyWith(trending: trending);
    } catch (_) {}
  }

  Future<void> loadRecommendations() async {
    try {
      final recs = await MarketplaceService.fetchRecommendations();
      state = state.copyWith(recommendations: recs);
    } catch (_) {}
  }

  Future<List<Product>> search({
    required String query,
    int? storeId,
    int limit = 20,
  }) async {
    return ProductService.searchStoreProducts(
      query: query,
      storeId: storeId,
      limit: limit,
    );
  }

  Future<void> loadAll() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final products = await MarketplaceService.fetchMarketplaceFeed();
      state = state.copyWith(feed: products, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
    unawaited(loadTrending());
    unawaited(loadRecommendations());
  }
}

final productsProvider =
    StateNotifierProvider<ProductsNotifier, ProductsState>((ref) {
  return ProductsNotifier();
});
