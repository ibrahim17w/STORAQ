// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipt_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReceiptSettings _$ReceiptSettingsFromJson(Map<String, dynamic> json) =>
    ReceiptSettings(
      footerMessage:
          json['footer_message'] as String? ?? 'Thank you for your purchase!',
      showLogo: json['show_logo'] as bool? ?? true,
      showBarcode: json['show_barcode'] as bool? ?? true,
      currencySymbol: json['currency_symbol'] as String? ?? 'SYP',
    );

Map<String, dynamic> _$ReceiptSettingsToJson(ReceiptSettings instance) =>
    <String, dynamic>{
      'footer_message': instance.footerMessage,
      'show_logo': instance.showLogo,
      'show_barcode': instance.showBarcode,
      'currency_symbol': instance.currencySymbol,
    };
