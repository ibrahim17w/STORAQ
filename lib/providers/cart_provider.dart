import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';

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
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

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
    state = state.copyWith(items: items);
  }

  void removeProduct(dynamic productId) {
    final items =
        state.items.where((item) => item.product.id != productId).toList();
    state = state.copyWith(items: items);
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
      state = state.copyWith(items: items);
    }
  }

  void setDiscount(double discount) {
    state = state.copyWith(discount: discount);
  }

  void setPaymentMethod(String method) {
    state = state.copyWith(paymentMethod: method);
  }

  void setCustomerInfo({String? name, String? phone}) {
    state = state.copyWith(customerName: name, customerPhone: phone);
  }

  void setNotes(String? notes) {
    state = state.copyWith(notes: notes);
  }

  List<Map<String, dynamic>> toOrderItems() {
    return state.items.map((item) => item.toOrderItemMap()).toList();
  }

  void clear() {
    state = const CartState();
  }
}

final cartProvider =
    StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
