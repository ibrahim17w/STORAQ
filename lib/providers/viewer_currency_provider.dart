import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'viewer_location_provider.dart';
import '../services/platform_rates_service.dart';

class ViewerCurrencyState {
  final Map<String, dynamic> currencySettings;
  final bool loading;

  const ViewerCurrencyState({
    required this.currencySettings,
    this.loading = false,
  });

  static const empty = ViewerCurrencyState(
    currencySettings: {
      'display_currency': null,
      'show_both_prices': false,
      'exchange_rates': <dynamic>[],
    },
  );
}

class ViewerCurrencyNotifier extends StateNotifier<ViewerCurrencyState> {
  ViewerCurrencyNotifier(this.ref) : super(ViewerCurrencyState.empty) {
    _rebuild();
    ref.listen(viewerLocationProvider, (_, __) => _rebuild());
  }

  final Ref ref;

  Future<void> _rebuild() async {
    final location = ref.read(viewerLocationProvider);
    final currency = location.paymentCurrency;

    state = ViewerCurrencyState(
      currencySettings: {
        'display_currency': currency,
        'show_both_prices': false,
        'exchange_rates': <dynamic>[],
      },
      loading: true,
    );

    try {
      final paymentRates = await PlatformRatesService.getPaymentRates();
      final ratesMap = paymentRates['rates'] as Map<String, dynamic>? ?? {};
      final exchangeRates = <Map<String, dynamic>>[];

      for (final entry in ratesMap.entries) {
        final to = entry.key.toString().toUpperCase();
        if (to == 'USD') continue;
        final rate = entry.value;
        if (rate is num && rate > 0) {
          exchangeRates.add({'from': 'USD', 'to': to, 'rate': rate});
        }
      }

      state = ViewerCurrencyState(
        currencySettings: {
          'display_currency': currency,
          'show_both_prices': false,
          'exchange_rates': exchangeRates,
        },
      );
    } catch (_) {
      state = ViewerCurrencyState(
        currencySettings: {
          'display_currency': currency,
          'show_both_prices': false,
          'exchange_rates': <dynamic>[],
        },
      );
    }
  }
}

final viewerCurrencyProvider =
    StateNotifierProvider<ViewerCurrencyNotifier, ViewerCurrencyState>(
  ViewerCurrencyNotifier.new,
);
