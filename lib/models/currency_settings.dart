import 'package:json_annotation/json_annotation.dart';

part 'currency_settings.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class CurrencySettings {
  @JsonKey(name: 'display_currency')
  final String? displayCurrency;
  @JsonKey(name: 'show_both_prices')
  final bool showBothPrices;
  @JsonKey(name: 'exchange_rates', fromJson: _ratesFromJson)
  final List<ExchangeRate> exchangeRates;

  const CurrencySettings({
    this.displayCurrency,
    this.showBothPrices = false,
    this.exchangeRates = const [],
  });

  factory CurrencySettings.fromJson(Map<String, dynamic> json) =>
      _$CurrencySettingsFromJson(json);

  Map<String, dynamic> toJson() => _$CurrencySettingsToJson(this);

  Map<String, dynamic> toLegacyMap() => {
        'display_currency': displayCurrency,
        'show_both_prices': showBothPrices,
        'exchange_rates':
            exchangeRates.map((r) => r.toJson()).toList(),
      };

  static CurrencySettings fromLegacyMap(Map<String, dynamic> map) {
    return CurrencySettings(
      displayCurrency: map['display_currency']?.toString(),
      showBothPrices: map['show_both_prices'] == true,
      exchangeRates: _ratesFromJson(map['exchange_rates']),
    );
  }

  static List<ExchangeRate> _ratesFromJson(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((e) => ExchangeRate.fromJson(e))
          .toList();
    }
    return [];
  }
}

@JsonSerializable(includeIfNull: false)
class ExchangeRate {
  final String from;
  final String to;
  final double rate;
  @JsonKey(name: 'is_auto')
  final bool? isAuto;

  const ExchangeRate({
    required this.from,
    required this.to,
    required this.rate,
    this.isAuto,
  });

  factory ExchangeRate.fromJson(Map<String, dynamic> json) =>
      _$ExchangeRateFromJson(json);

  Map<String, dynamic> toJson() => _$ExchangeRateToJson(this);
}
