import 'package:json_annotation/json_annotation.dart';
import '../utils/json_parsers.dart';
import 'order_item.dart';

part 'order.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class Order {
  final dynamic id;
  @JsonKey(name: 'receipt_number')
  final String? receiptNumber;
  @JsonKey(name: 'store_id', fromJson: parseJsonInt)
  final int? storeId;
  @JsonKey(name: 'cashier_name')
  final String? cashierName;
  @JsonKey(name: 'customer_name')
  final String? customerName;
  @JsonKey(name: 'customer_phone')
  final String? customerPhone;
  @JsonKey(fromJson: _itemsFromJson)
  final List<OrderItem> items;
  @JsonKey(fromJson: parseJsonDouble)
  final double? subtotal;
  @JsonKey(fromJson: parseJsonDouble)
  final double? discount;
  @JsonKey(fromJson: parseJsonDouble)
  final double? tax;
  @JsonKey(fromJson: parseJsonDouble)
  final double? total;
  @JsonKey(name: 'display_subtotal', fromJson: parseJsonDouble)
  final double? displaySubtotal;
  @JsonKey(name: 'display_discount', fromJson: parseJsonDouble)
  final double? displayDiscount;
  @JsonKey(name: 'display_tax', fromJson: parseJsonDouble)
  final double? displayTax;
  @JsonKey(name: 'display_total', fromJson: parseJsonDouble)
  final double? displayTotal;
  @JsonKey(name: 'display_currency')
  final String? displayCurrency;
  @JsonKey(name: 'payment_method')
  final String? paymentMethod;
  final String? notes;
  final String? currency;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  final String? status;
  final bool? offline;
  @JsonKey(name: 'pending_sync')
  final bool? pendingSync;

  const Order({
    this.id,
    this.receiptNumber,
    this.storeId,
    this.cashierName,
    this.customerName,
    this.customerPhone,
    this.items = const [],
    this.subtotal,
    this.discount,
    this.tax,
    this.total,
    this.displaySubtotal,
    this.displayDiscount,
    this.displayTax,
    this.displayTotal,
    this.displayCurrency,
    this.paymentMethod,
    this.notes,
    this.currency,
    this.createdAt,
    this.status,
    this.offline,
    this.pendingSync,
  });

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

  Map<String, dynamic> toJson() {
    final map = _$OrderToJson(this);
    map['items'] = items.map((item) => item.toJson()).toList();
    return map;
  }

  static List<OrderItem> _itemsFromJson(dynamic items) {
    if (items == null) return [];
    if (items is List) {
      return items
          .whereType<Map<String, dynamic>>()
          .map((e) => OrderItem.fromJson(e))
          .toList();
    }
    return [];
  }
}
