//lib/providers/viewer_location_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/viewer_location_service.dart';
import '../utils/geo_currency_helper.dart';

class ViewerLocationState {
  final String? countryCode;
  final String? countryName;
  final bool loading;

  const ViewerLocationState({
    this.countryCode,
    this.countryName,
    this.loading = false,
  });

  String get paymentCurrency =>
      GeoCurrencyHelper.currencyForCountryCode(countryCode);

  ViewerLocationState copyWith({
    String? countryCode,
    String? countryName,
    bool? loading,
  }) {
    return ViewerLocationState(
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      loading: loading ?? this.loading,
    );
  }
}

class ViewerLocationNotifier extends StateNotifier<ViewerLocationState> {
  ViewerLocationNotifier() : super(const ViewerLocationState()) {
    _loadCached();
  }

  Future<void> _loadCached() async {
    final code = await ViewerLocationService.getCountryCode();
    final name = await ViewerLocationService.getCountryName();
    if (code != null || name != null) {
      state = state.copyWith(countryCode: code, countryName: name);
    }
  }

  Future<void> setCountry({
    required String? countryCode,
    String? countryName,
  }) async {
    await ViewerLocationService.saveCountry(
      countryCode: countryCode,
      countryName: countryName,
    );
    state = state.copyWith(countryCode: countryCode, countryName: countryName);
  }
}

final viewerLocationProvider =
    StateNotifierProvider<ViewerLocationNotifier, ViewerLocationState>(
      (ref) => ViewerLocationNotifier(),
    );
