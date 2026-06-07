// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'currency_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CurrencySettings _$CurrencySettingsFromJson(Map<String, dynamic> json) =>
    CurrencySettings(
      displayCurrency: json['display_currency'] as String?,
      showBothPrices: json['show_both_prices'] as bool? ?? false,
      exchangeRates: json['exchange_rates'] == null
          ? const []
          : CurrencySettings._ratesFromJson(json['exchange_rates']),
    );

Map<String, dynamic> _$CurrencySettingsToJson(CurrencySettings instance) =>
    <String, dynamic>{
      'display_currency': ?instance.displayCurrency,
      'show_both_prices': instance.showBothPrices,
      'exchange_rates': instance.exchangeRates,
    };

ExchangeRate _$ExchangeRateFromJson(Map<String, dynamic> json) => ExchangeRate(
  from: json['from'] as String,
  to: json['to'] as String,
  rate: (json['rate'] as num).toDouble(),
  isAuto: json['is_auto'] as bool?,
);

Map<String, dynamic> _$ExchangeRateToJson(ExchangeRate instance) =>
    <String, dynamic>{
      'from': instance.from,
      'to': instance.to,
      'rate': instance.rate,
      'is_auto': ?instance.isAuto,
    };
