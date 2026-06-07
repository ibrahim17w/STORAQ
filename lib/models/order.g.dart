// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Order _$OrderFromJson(Map<String, dynamic> json) => Order(
  id: json['id'],
  receiptNumber: json['receipt_number'] as String?,
  storeId: parseJsonInt(json['store_id']),
  cashierName: json['cashier_name'] as String?,
  customerName: json['customer_name'] as String?,
  customerPhone: json['customer_phone'] as String?,
  items: json['items'] == null ? const [] : Order._itemsFromJson(json['items']),
  subtotal: parseJsonDouble(json['subtotal']),
  discount: parseJsonDouble(json['discount']),
  tax: parseJsonDouble(json['tax']),
  total: parseJsonDouble(json['total']),
  displaySubtotal: parseJsonDouble(json['display_subtotal']),
  displayDiscount: parseJsonDouble(json['display_discount']),
  displayTax: parseJsonDouble(json['display_tax']),
  displayTotal: parseJsonDouble(json['display_total']),
  displayCurrency: json['display_currency'] as String?,
  paymentMethod: json['payment_method'] as String?,
  notes: json['notes'] as String?,
  currency: json['currency'] as String?,
  createdAt: json['created_at'] as String?,
  status: json['status'] as String?,
  offline: json['offline'] as bool?,
  pendingSync: json['pending_sync'] as bool?,
);

Map<String, dynamic> _$OrderToJson(Order instance) => <String, dynamic>{
  'id': ?instance.id,
  'receipt_number': ?instance.receiptNumber,
  'store_id': ?instance.storeId,
  'cashier_name': ?instance.cashierName,
  'customer_name': ?instance.customerName,
  'customer_phone': ?instance.customerPhone,
  'items': instance.items,
  'subtotal': ?instance.subtotal,
  'discount': ?instance.discount,
  'tax': ?instance.tax,
  'total': ?instance.total,
  'display_subtotal': ?instance.displaySubtotal,
  'display_discount': ?instance.displayDiscount,
  'display_tax': ?instance.displayTax,
  'display_total': ?instance.displayTotal,
  'display_currency': ?instance.displayCurrency,
  'payment_method': ?instance.paymentMethod,
  'notes': ?instance.notes,
  'currency': ?instance.currency,
  'created_at': ?instance.createdAt,
  'status': ?instance.status,
  'offline': ?instance.offline,
  'pending_sync': ?instance.pendingSync,
};
