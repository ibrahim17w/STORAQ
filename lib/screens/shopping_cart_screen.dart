import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lang/translations.dart';
import '../providers/cart_provider.dart';
import '../utils/product_store_helper.dart';
import '../widgets/cached_image.dart';
import '../services/currency_service.dart';
import 'product_detail_screen.dart';
import 'store_products_screen.dart';

class ShoppingCartScreen extends ConsumerWidget {
  const ShoppingCartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);
    final groups = cart.groupedByStore;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('cart') ?? 'Cart'),
        actions: [
          if (cart.items.isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(cartProvider.notifier).clear();
              },
              child: Text(t('clear_cart') ?? 'Clear'),
            ),
        ],
      ),
      body: cart.items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('cart_empty') ?? 'Your cart is empty',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('cart_empty_hint') ??
                        'Add products from the marketplace to visit stores later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return _StoreCartSection(group: group);
              },
            ),
    );
  }
}

class _StoreCartSection extends ConsumerWidget {
  final CartStoreGroup group;

  const _StoreCartSection({required this.group});

  void _openStore(BuildContext context) {
    final storeId = group.storeId;
    if (storeId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(storeId: storeId),
      ),
    );
  }

  void _openProduct(BuildContext context, CartItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: productToDetailMap(item.product),
        ),
      ),
    );
  }

  double _groupSubtotal() {
    return group.items.fold(0.0, (sum, item) {
      final unit = CurrencyService.resolvedProductUnitPrice(item.product.toJson());
      return sum + unit * item.quantity;
    });
  }

  String? _groupCurrency() {
    if (group.items.isEmpty) return null;
    return CurrencyService.resolvedProductCurrency(group.items.first.product.toJson());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtotalCurrency = _groupCurrency() ?? 'SYP';
    final subtotal = _groupSubtotal();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: group.storeId != null ? () => _openStore(context) : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      group.storeName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (group.storeId != null)
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          ...group.items.map((item) {
            final productMap = item.product.toJson();
            final imageUrl = item.product.imageUrl;
            final priceText = CurrencyService.formatResolvedProductPrice(productMap);
            final unitPrice = CurrencyService.resolvedProductUnitPrice(productMap);
            final lineTotal = unitPrice * item.quantity;

            return InkWell(
              onTap: () => _openProduct(context, item),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: CachedAppImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.name ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            priceText,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.quantity > 1)
                            Text(
                              '${CurrencyService.formatPrice(lineTotal, subtotalCurrency)} total',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            ref
                                .read(cartProvider.notifier)
                                .updateQuantity(item.product.id, item.quantity - 1);
                          },
                        ),
                        Text(
                          '${item.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            ref
                                .read(cartProvider.notifier)
                                .updateQuantity(item.product.id, item.quantity + 1);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              '${t('subtotal') ?? 'Subtotal'}: ${CurrencyService.formatPrice(subtotal, subtotalCurrency)}',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
