import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/prefs_service.dart';

class CartStoreGroup {
  final int? storeId;
  final String storeName;
  final List<CartItem> items;

  const CartStoreGroup({
    required this.storeId,
    required this.storeName,
    required this.items,
  });

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.total);
}

class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  int? get storeId => product.storeId;

  String get storeName =>
      (product.shopName ?? '').trim().isNotEmpty
          ? product.shopName!.trim()
          : 'Store';

  double get total => (product.price ?? 0) * quantity;

  Map<String, dynamic> toOrderItemMap() => {
        'product_id': product.id,
        'product_name': product.name,
        'name': product.name,
        'quantity': quantity,
        'unit_price': product.price,
        'price': product.price,
        'total_price': total,
        'barcode': product.barcode,
      };
}

class CartState {
  final List<CartItem> items;
  final String? customerName;
  final String? customerPhone;
  final String paymentMethod;
  final String? notes;
  final double discount;

  const CartState({
    this.items = const [],
    this.customerName,
    this.customerPhone,
    this.paymentMethod = 'cash',
    this.notes,
    this.discount = 0,
  });

  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.total);

  double get total => subtotal - discount;

  int get itemCount =>
      items.fold(0, (sum, item) => sum + item.quantity);

  List<CartStoreGroup> get groupedByStore {
    final order = <String>[];
    final groups = <String, List<CartItem>>{};

    for (final item in items) {
      final sid = item.storeId;
      final key = sid?.toString() ?? item.storeName;
      order.add(key);
      groups.putIfAbsent(key, () => []).add(item);
    }

    final seen = <String>{};
    final result = <CartStoreGroup>[];
    for (final key in order) {
      if (seen.contains(key)) continue;
      seen.add(key);
      final groupItems = groups[key]!;
      result.add(
        CartStoreGroup(
          storeId: groupItems.first.storeId,
          storeName: groupItems.first.storeName,
          items: List<CartItem>.from(groupItems),
        ),
      );
    }
    return result;
  }

  CartState copyWith({
    List<CartItem>? items,
    String? customerName,
    String? customerPhone,
    String? paymentMethod,
    String? notes,
    double? discount,
  }) {
    return CartState(
      items: items ?? this.items,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      discount: discount ?? this.discount,
    );
  }

  Map<String, dynamic> toJson() => {
        'items': items
            .map(
              (item) => {
                'product': item.product.toJson(),
                'quantity': item.quantity,
              },
            )
            .toList(),
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'payment_method': paymentMethod,
        'notes': notes,
        'discount': discount,
      };

  static CartState fromJson(Map<String, dynamic> json) {
    final items = <CartItem>[];
    for (final entry in json['items'] as List<dynamic>? ?? const []) {
      if (entry is! Map<String, dynamic>) continue;
      final productJson = entry['product'];
      if (productJson is! Map<String, dynamic>) continue;
      try {
        items.add(
          CartItem(
            product: Product.fromJson(productJson),
            quantity: (entry['quantity'] as num?)?.toInt() ?? 1,
          ),
        );
      } catch (_) {}
    }

    return CartState(
      items: items,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      notes: json['notes'] as String?,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  static const _storageKey = 'persisted_cart_v1';

  bool _hasMutations = false;
  bool _restoreComplete = false;

  CartNotifier() : super(const CartState()) {
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final prefs = await PrefsService.instance;
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty && !_hasMutations) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          state = CartState.fromJson(decoded);
        }
      }
    } catch (_) {
      // Ignore corrupt saved cart data.
    } finally {
      _restoreComplete = true;
      if (_hasMutations) {
        unawaited(_persist());
      }
    }
  }

  Future<void> _persist() async {
    if (!_restoreComplete) return;
    try {
      final prefs = await PrefsService.instance;
      if (state.items.isEmpty &&
          state.customerName == null &&
          state.customerPhone == null &&
          state.notes == null &&
          state.discount == 0) {
        await prefs.remove(_storageKey);
        return;
      }
      await prefs.setString(_storageKey, jsonEncode(state.toJson()));
    } catch (_) {
      // Persistence is best-effort; cart still works in memory.
    }
  }

  void _commit(CartState next) {
    _hasMutations = true;
    state = next;
    unawaited(_persist());
  }

  void addProduct(Product product, {int quantity = 1}) {
    final items = [...state.items];
    final idx = items.indexWhere(
      (item) => item.product.id == product.id,
    );
    if (idx >= 0) {
      items[idx].quantity += quantity;
    } else {
      items.add(CartItem(product: product, quantity: quantity));
    }
    _commit(state.copyWith(items: items));
  }

  void removeProduct(dynamic productId) {
    final items =
        state.items.where((item) => item.product.id != productId).toList();
    _commit(state.copyWith(items: items));
  }

  void updateQuantity(dynamic productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    final items = [...state.items];
    final idx = items.indexWhere((item) => item.product.id == productId);
    if (idx >= 0) {
      items[idx].quantity = quantity;
      _commit(state.copyWith(items: items));
    }
  }

  void setDiscount(double discount) {
    _commit(state.copyWith(discount: discount));
  }

  void setPaymentMethod(String method) {
    _commit(state.copyWith(paymentMethod: method));
  }

  void setCustomerInfo({String? name, String? phone}) {
    _commit(state.copyWith(customerName: name, customerPhone: phone));
  }

  void setNotes(String? notes) {
    _commit(state.copyWith(notes: notes));
  }

  List<Map<String, dynamic>> toOrderItems() {
    return state.items.map((item) => item.toOrderItemMap()).toList();
  }

  void clear() {
    _hasMutations = true;
    state = const CartState();
    unawaited(_persist());
  }

  void clearStore({int? storeId, required String storeName}) {
    final items = state.items.where((item) {
      if (storeId != null && item.storeId != null) {
        return item.storeId != storeId;
      }
      return item.storeName != storeName;
    }).toList();
    _commit(state.copyWith(items: items));
  }
}

final cartProvider =
    StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
