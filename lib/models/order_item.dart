import 'package:json_annotation/json_annotation.dart';
import '../utils/json_parsers.dart';

part 'order_item.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class OrderItem {
  @JsonKey(name: 'product_id')
  final dynamic productId;
  @JsonKey(name: 'product_name')
  final String? productName;
  final String? name;
  @JsonKey(fromJson: parseJsonInt)
  final int? quantity;
  @JsonKey(name: 'unit_price', fromJson: parseJsonDouble)
  final double? unitPrice;
  @JsonKey(fromJson: parseJsonDouble)
  final double? price;
  @JsonKey(name: 'total_price', fromJson: parseJsonDouble)
  final double? totalPrice;
  final String? currency;
  @JsonKey(name: 'display_price', fromJson: parseJsonDouble)
  final double? displayPrice;
  @JsonKey(name: 'display_currency')
  final String? displayCurrency;
  final String? barcode;
  @JsonKey(name: 'product_barcode')
  final String? productBarcode;

  const OrderItem({
    this.productId,
    this.productName,
    this.name,
    this.quantity,
    this.unitPrice,
    this.price,
    this.totalPrice,
    this.currency,
    this.displayPrice,
    this.displayCurrency,
    this.barcode,
    this.productBarcode,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) =>
      _$OrderItemFromJson(json);

  Map<String, dynamic> toJson() => _$OrderItemToJson(this);

  String get displayName => productName ?? name ?? 'Unknown';

  double get effectiveUnitPrice =>
      unitPrice ?? price ?? 0;

  double get effectiveTotalPrice =>
      totalPrice ?? (effectiveUnitPrice * (quantity ?? 0));

  String? get effectiveBarcode => barcode ?? productBarcode;
}
