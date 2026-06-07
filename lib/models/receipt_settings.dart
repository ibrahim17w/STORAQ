import 'package:json_annotation/json_annotation.dart';

part 'receipt_settings.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class ReceiptSettings {
  @JsonKey(name: 'footer_message')
  final String footerMessage;
  @JsonKey(name: 'show_logo')
  final bool showLogo;
  @JsonKey(name: 'show_barcode')
  final bool showBarcode;
  @JsonKey(name: 'currency_symbol')
  final String currencySymbol;

  const ReceiptSettings({
    this.footerMessage = 'Thank you for your purchase!',
    this.showLogo = true,
    this.showBarcode = true,
    this.currencySymbol = 'SYP',
  });

  factory ReceiptSettings.fromJson(Map<String, dynamic> json) =>
      _$ReceiptSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$ReceiptSettingsToJson(this);

  static const ReceiptSettings defaults = ReceiptSettings();

  ReceiptSettings copyWith({
    String? footerMessage,
    bool? showLogo,
    bool? showBarcode,
    String? currencySymbol,
  }) {
    return ReceiptSettings(
      footerMessage: footerMessage ?? this.footerMessage,
      showLogo: showLogo ?? this.showLogo,
      showBarcode: showBarcode ?? this.showBarcode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
    );
  }
}
