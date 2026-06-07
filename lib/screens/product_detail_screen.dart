// lib/screens/product_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../services/favorites_service.dart';
import '../services/marketplace_service.dart';
import '../services/product_service.dart';
import '../lang/translations.dart';
import '../widgets/cached_image.dart';
import '../widgets/product/product_image_viewer.dart';
import '../utils/json_parsers.dart';
import '../utils/product_store_helper.dart';
import 'store_map_screen.dart';
import 'store_products_screen.dart';
import '../services/store_service.dart';
import '../services/currency_service.dart';
import '../services/chat_service.dart';
import '../models/models.dart';
import '../widgets/guest_login_sheet.dart' as guest;
import '../providers/cart_provider.dart';
import 'chat_screen.dart';
import 'shopping_cart_screen.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final dynamic product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  late Map<String, dynamic> _product;
  List<String> _images = [];
  bool _loadingImages = true;
  Store? _storeData;
  bool _loadingStore = true;
  bool _isFavorite = false;
  Map<String, dynamic> _currencySettings = const {};

  @override
  void initState() {
    super.initState();
    _product = productToDetailMap(widget.product);
    _loadImages();
    _loadStore();
    _loadCurrencySettings();
    _checkFavorite();
    _trackView();
  }

  Future<void> _loadImages() async {
    setState(() => _loadingImages = true);
    try {
      final id = _product['id'];
      final productId = id is int ? id : int.tryParse(id?.toString() ?? '');
      if (productId != null && productId > 0) {
        final detail = await MarketplaceService.fetchProductDetail(productId);
        if (detail != null) {
          _product = productToDetailMap({..._product, ...detail.toJson()});
        }
      }

      final images = await ProductService.resolveProductImages(_product);
      if (!mounted) return;
      setState(() {
        _images = images;
        _loadingImages = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _images = [];
          _loadingImages = false;
        });
      }
    }
  }

  Future<void> _loadCurrencySettings() async {
    try {
      final settings = await CurrencyService.getCurrencySettings();
      if (mounted) {
        setState(() => _currencySettings = settings.toLegacyMap());
      }
    } catch (_) {}
  }

  void _applyStoreCurrency(Store store) {
    if (store.displayCurrency == null || store.displayCurrency!.isEmpty) {
      return;
    }
    _currencySettings = {
      'display_currency': store.displayCurrency,
      'show_both_prices': store.showBothPrices ?? false,
      'exchange_rates': store.exchangeRates,
    };
  }

  Future<void> _trackView() async {
    final id = _product['id'];
    if (id == null) return;
    final pid = id is int ? id : int.tryParse(id.toString()) ?? 0;
    if (pid > 0) MarketplaceService.trackProductView(pid);
  }

  Future<void> _checkFavorite() async {
    final id = _product['id'];
    if (id == null) return;
    final pid = id is int ? id : int.tryParse(id.toString()) ?? 0;
    final fav = await FavoritesService.isFavorite(pid);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final id = _product['id'];
    if (id == null) return;
    final pid = id is int ? id : int.tryParse(id.toString()) ?? 0;
    await FavoritesService.toggleFavorite(pid, product: _product);
    if (mounted) setState(() => _isFavorite = !_isFavorite);
  }

  int? get _storeId {
    final shopId = _product['shop_id'] ?? _product['store_id'];
    if (shopId == null) return null;
    if (shopId is int) return shopId;
    return int.tryParse(shopId.toString());
  }

  double? get _effectiveLat =>
      _storeData?.lat ?? parseJsonDouble(_product['lat']);

  double? get _effectiveLng =>
      _storeData?.lng ?? parseJsonDouble(_product['lng']);

  Future<void> _loadStore() async {
    final fallback = storeFromProductMap(_product);
    final storeId = _storeId;

    if (storeId == null || storeId <= 0) {
      if (mounted) {
        setState(() {
          _storeData = fallback;
          _loadingStore = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _storeData = fallback;
        _loadingStore = true;
      });
    }

    try {
      final store = await StoreService.fetchStore(storeId);
      if (mounted) {
        setState(() {
          _applyStoreCurrency(store);
          _storeData = Store(
            id: store.id ?? storeId,
            name: store.name ?? fallback?.name,
            city: store.city ?? fallback?.city,
            country: store.country ?? fallback?.country,
            lat: store.lat ?? fallback?.lat,
            lng: store.lng ?? fallback?.lng,
            imageUrl: store.imageUrl ?? fallback?.imageUrl,
            phone: store.phone,
            displayCurrency: store.displayCurrency,
            showBothPrices: store.showBothPrices,
            exchangeRates: store.exchangeRates,
          );
          _loadingStore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _storeData = fallback;
          _loadingStore = false;
        });
      }
    }
  }

  void _openStoreOnMap() {
    final lat = _effectiveLat;
    final lng = _effectiveLng;
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('location_not_available'))),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreLocationView(
          target: LatLng(lat, lng),
          targetStoreId: _storeId,
          targetName: _storeData?.name ?? _product['shop_name']?.toString(),
          targetImageUrl: _storeData?.imageUrl,
          stores: _storeData != null ? [_storeData!.toJson()] : [],
        ),
      ),
    );
  }

  void _openStorePage() {
    final storeId = _storeId;
    if (storeId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(
          storeId: storeId,
          storeName: _storeData?.name ?? _product['shop_name']?.toString(),
        ),
      ),
    );
  }

  Future<void> _messageStore() async {
    final canProceed = await guest.requireAuth(context);
    if (!mounted || !canProceed) return;
    final storeId = _storeId;
    if (storeId == null) return;

    try {
      final conversation = await ChatService.startConversation(storeId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(conversation: conversation),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _addToCart() async {
    final canProceed = await guest.requireAuth(context);
    if (!canProceed) return;

    final qty = (_product['quantity'] as num?)?.toInt() ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('out_of_stock') ?? 'Out of stock')),
      );
      return;
    }

    final product = Product.fromJson(_product);
    ref.read(cartProvider.notifier).addProduct(product);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('added_to_cart') ?? 'Added to cart'),
        action: SnackBarAction(
          label: t('view_cart') ?? 'View cart',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShoppingCartScreen()),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPriceSection(BuildContext context) {
    final info =
        CurrencyService.getProductDisplayInfo(_product, _currencySettings);
    final originalPrice = info['original_price'];
    final originalCurrency = info['original_currency'] as String;
    final displayPrice = info['display_price'];
    final displayCurrency = info['display_currency'] as String?;
    final showBoth = info['show_both'] == true;
    final hasDisplay = displayPrice != null && displayCurrency != null;
    final primaryText = hasDisplay
        ? CurrencyService.formatPrice(displayPrice, displayCurrency)
        : CurrencyService.formatPrice(originalPrice, originalCurrency);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primaryText,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
            height: 1.1,
          ),
        ),
        if (hasDisplay && showBoth)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              CurrencyService.formatPrice(originalPrice, originalCurrency),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
                decorationColor:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: compactListCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildStoreSection(BuildContext context) {
    final p = _product;
    final theme = Theme.of(context);
    final storeName =
        _storeData?.name ?? p['shop_name']?.toString() ?? t('store');
    final city = _storeData?.city ?? p['city'] ?? p['store_city'] ?? '';
    final country =
        _storeData?.country ?? p['country'] ?? p['store_country'] ?? '';
    final locationLine = [city, country]
        .where((part) => part.toString().trim().isNotEmpty)
        .join(', ');
    final hasLocation = _effectiveLat != null && _effectiveLng != null;
    final canOpenStore = _storeId != null;

    if (_loadingStore && _storeData == null) {
      return const SizedBox(
        height: 88,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canOpenStore ? _openStorePage : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: compactListCardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _storeData?.imageUrl != null
                    ? CachedAppImage(
                        imageUrl: _storeData!.imageUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        memCacheWidth: 120,
                      )
                    : Container(
                        width: 52,
                        height: 52,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.storefront_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (locationLine.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          locationLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (hasLocation)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.location_on_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  tooltip: t('map'),
                  onPressed: _openStoreOnMap,
                ),
              if (canOpenStore)
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection(BuildContext context) {
    if (_loadingImages) {
      return Container(
        height: 340,
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return ProductImageViewer(
      images: _images,
      height: 340,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    final theme = Theme.of(context);
    final qty = (p['quantity'] as num?)?.toInt() ?? 0;
    final inStock = qty > 0;
    final description = p['description']?.toString().trim() ?? '';
    final shopName = (p['shop_name'] ?? _storeData?.name ?? '').toString();

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 1,
            backgroundColor: theme.colorScheme.surface,
            title: Text(
              p['name'] ?? t('product_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                ),
                color: _isFavorite ? Colors.red : null,
                onPressed: _toggleFavorite,
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildImageSection(context)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (shopName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        shopName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    p['name'] ?? '',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: _buildPriceSection(context)),
                      stockBadge(
                        context,
                        qty,
                        label: inStock
                            ? '$qty ${t('in_stock')}'
                            : t('out_of_stock'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: _buildInfoCard(
                  context: context,
                  title: t('description'),
                  child: Text(
                    description,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ),
          if (p['barcode'] != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.qr_code_2_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('barcode'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              p['barcode'].toString(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                t('store'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: _buildStoreSection(context),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _storeId != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _messageStore,
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: Text(t('message_store') ?? 'Message'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: inStock ? _addToCart : null,
                            icon: const Icon(Icons.add_shopping_cart_outlined),
                            label: Text(t('add_to_cart') ?? 'Add to cart'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _openStorePage,
                      icon: const Icon(Icons.storefront_outlined),
                      label: Text('${t('see_all')} — ${t('store')}'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
