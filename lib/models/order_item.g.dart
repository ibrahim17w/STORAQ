// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderItem _$OrderItemFromJson(Map<String, dynamic> json) => OrderItem(
  productId: json['product_id'],
  productName: json['product_name'] as String?,
  name: json['name'] as String?,
  quantity: parseJsonInt(json['quantity']),
  unitPrice: parseJsonDouble(json['unit_price']),
  price: parseJsonDouble(json['price']),
  totalPrice: parseJsonDouble(json['total_price']),
  currency: json['currency'] as String?,
  displayPrice: parseJsonDouble(json['display_price']),
  displayCurrency: json['display_currency'] as String?,
  barcode: json['barcode'] as String?,
  productBarcode: json['product_barcode'] as String?,
);

Map<String, dynamic> _$OrderItemToJson(OrderItem instance) => <String, dynamic>{
  'product_id': ?instance.productId,
  'product_name': ?instance.productName,
  'name': ?instance.name,
  'quantity': ?instance.quantity,
  'unit_price': ?instance.unitPrice,
  'price': ?instance.price,
  'total_price': ?instance.totalPrice,
  'currency': ?instance.currency,
  'display_price': ?instance.displayPrice,
  'display_currency': ?instance.displayCurrency,
  'barcode': ?instance.barcode,
  'product_barcode': ?instance.productBarcode,
};
