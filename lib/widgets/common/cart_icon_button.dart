import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../lang/translations.dart';
import '../../providers/cart_provider.dart';
import '../../screens/shopping_cart_screen.dart';

class CartIconButton extends ConsumerWidget {
  const CartIconButton({super.key});

  void _openCart(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ShoppingCartScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartProvider).itemCount;

    return IconButton(
      tooltip: t('cart') ?? 'Cart',
      onPressed: () => _openCart(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.shopping_cart_outlined),
      ),
    );
  }
}
