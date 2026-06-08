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
import '../widgets/product/product_price_display.dart';
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
import '../widgets/reviews_section.dart';
import '../services/review_service.dart';
import '../widgets/report_dialog.dart';

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
            rating: store.rating,
            reviewCount: store.reviewCount,
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

  Future<void> _reportProduct() async {
    final productId = _product['id'];
    final pid = productId is int
        ? productId
        : int.tryParse(productId?.toString() ?? '');
    if (pid == null || pid <= 0) return;

    await showContentReportDialog(
      context,
      targetType: 'product',
      targetId: pid,
      storeId: _storeId,
      title: t('report_product') ?? 'Report product',
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
    if (!canProceed || !mounted) return;

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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(t('added_to_cart') ?? 'Added to cart'),
        action: SnackBarAction(
          label: t('view_cart') ?? 'View cart',
          onPressed: () {
            navigator.push(
              MaterialPageRoute(builder: (_) => const ShoppingCartScreen()),
            );
          },
        ),
      ),
    );
  }

  Color _detailSurface(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white;
  }

  Color _detailBorder(ThemeData theme) {
    return theme.dividerColor.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.55 : 0.35,
    );
  }

  BoxDecoration _detailCardDecoration(ThemeData theme) {
    return BoxDecoration(
      color: _detailSurface(theme),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _detailBorder(theme)),
    );
  }

  Widget _buildPriceSection(BuildContext context) {
    final theme = Theme.of(context);
    final onSale = CurrencyService.isOnSale(_product);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductPriceDisplay(
          product: _product,
          currencySettings: _currencySettings,
          priceStyle: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: onSale ? theme.colorScheme.error : theme.colorScheme.primary,
            letterSpacing: -0.03,
            height: 1.05,
          ),
        ),
        if (onSale)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                t('on_sale'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _inventoryPill(BuildContext context, int qty, bool inStock) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = inStock
        ? (isDark ? const Color(0xFF95D5B2) : const Color(0xFF1B4332))
        : theme.colorScheme.onErrorContainer;
    final bg = inStock
        ? (isDark ? const Color(0xFF1B4332) : const Color(0xFFD8F3DC))
        : theme.colorScheme.errorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
        color: bg,
      ),
      child: Text(
        inStock ? '$qty ${t('in_stock')}' : t('out_of_stock'),
        style: theme.textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
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
      padding: const EdgeInsets.all(20),
      decoration: _detailCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 12),
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
    final locationLine = _shortLocation(
      city.toString(),
      country.toString(),
    );
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
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: _detailCardDecoration(theme),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _storeData?.imageUrl != null
                    ? CachedAppImage(
                        imageUrl: _storeData!.imageUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        memCacheWidth: 120,
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.storefront_outlined,
                          size: 22,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                      ),
                    ),
                    if (locationLine.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                locationLine,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (hasLocation)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.map_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: t('map'),
                  onPressed: _openStoreOnMap,
                ),
              if (canOpenStore)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortLocation(String? city, String? country) {
    final parts = <String>[];
    if (city != null && city.trim().isNotEmpty) {
      parts.add(city.split(',').first.trim());
    }
    if (country != null && country.trim().isNotEmpty) {
      final c = country.trim();
      if (!parts.any((p) => p.toLowerCase() == c.toLowerCase())) {
        parts.add(c);
      }
    }
    return parts.join(', ');
  }

  Widget _buildProductRatingRow(BuildContext context) {
    final rating = parseJsonDouble(_product['rating']);
    final count = parseJsonInt(_product['review_count']) ?? 0;
    if (rating == null && count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final value = rating ?? 5.0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          ...List.generate(5, (i) {
            return Icon(
              i < value.round() ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 16,
              color: i < value.round()
                  ? Colors.amber.shade700.withValues(alpha: 0.85)
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            );
          }),
          const SizedBox(width: 8),
          Text(
            '${value.toStringAsFixed(1)} · $count ${t('reviews') ?? 'reviews'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    ThemeData theme,
    String label,
    String value, {
    bool strikethrough = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor,
                decoration:
                    strikethrough ? TextDecoration.lineThrough : null,
                decorationColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    final p = _product;
    final name = p['name']?.toString() ?? '';
    final info =
        CurrencyService.getProductDisplayInfo(_product, _currencySettings);
    final originalPrice = info['original_price'];
    final originalCurrency = info['original_currency'] as String;
    final displayPrice = info['display_price'];
    final displayCurrency = info['display_currency'] as String?;
    final showBoth = info['show_both'] == true;
    final onSale = info['is_on_sale'] == true;
    final listPrice = info['list_price'];
    final listCurrency = info['original_currency'] as String;
    final strikePrice = info['list_display_price'] ?? listPrice;
    final strikeCurrency =
        (info['list_display_currency'] ?? listCurrency) as String;
    final hasDisplay = displayPrice != null && displayCurrency != null;
    final primaryText = hasDisplay
        ? CurrencyService.formatPrice(displayPrice, displayCurrency)
        : CurrencyService.formatPrice(originalPrice, originalCurrency);
    final description = p['description']?.toString().trim() ?? '';

    final rows = <Widget>[
      if (name.isNotEmpty) _infoRow(theme, t('name'), name),
      if (onSale)
        _infoRow(
          theme,
          t('original_price') ?? 'Original',
          CurrencyService.formatPrice(strikePrice, strikeCurrency),
          strikethrough: true,
        ),
      _infoRow(
        theme,
        t('price'),
        primaryText,
        valueColor: onSale ? theme.colorScheme.error : null,
      ),
      if (!onSale && hasDisplay && showBoth)
        _infoRow(
          theme,
          t('original_price') ?? 'Original',
          CurrencyService.formatPrice(originalPrice, originalCurrency),
        ),
      if (p['barcode'] != null)
        _infoRow(theme, t('barcode'), p['barcode'].toString()),
      if (description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
    ];

    return _buildInfoCard(
      context: context,
      title: t('description') ?? 'Product Info',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  Widget _buildImageSection(BuildContext context) {
    final theme = Theme.of(context);
    const imageHeight = 340.0;

    if (_loadingImages) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SizedBox(
          height: imageHeight,
          child: DecoratedBox(
            decoration: _detailCardDecoration(theme),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Stack(
        children: [
          ProductImageViewer(
            images: _images,
            height: imageHeight,
            displayStyle: ProductImageDisplayStyle.cardCarousel,
          ),
          if (CurrencyService.isOnSale(_product))
            PositionedDirectional(
              top: 12,
              start: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  t('on_sale'),
                  style: TextStyle(
                    color: theme.colorScheme.onError,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    final theme = Theme.of(context);
    final qty = (p['quantity'] as num?)?.toInt() ?? 0;
    final inStock = qty > 0;
    final categoryName = p['category_name']?.toString().trim() ?? '';

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F7),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            backgroundColor: theme.brightness == Brightness.dark
                ? const Color(0xFF121212)
                : const Color(0xFFF5F5F7),
            foregroundColor: theme.colorScheme.onSurface,
            iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
            title: Text(
              p['name'] ?? t('product_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.flag_outlined),
                tooltip: t('report') ?? 'Report',
                onPressed: _reportProduct,
              ),
              IconButton(
                icon: Icon(
                  _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                ),
                color: _isFavorite
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                onPressed: _toggleFavorite,
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildImageSection(context)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (categoryName.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _detailBorder(theme)),
                        color: _detailSurface(theme),
                      ),
                      child: Text(
                        categoryName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    p['name'] ?? '',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.03,
                      height: 1.2,
                    ),
                  ),
                  _buildProductRatingRow(context),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _buildPriceSection(context)),
                      const SizedBox(width: 12),
                      _inventoryPill(context, qty, inStock),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: _buildProductInfoCard(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Builder(
                builder: (context) {
                  final productId = _product['id'];
                  final pid = productId is int
                      ? productId
                      : int.tryParse(productId?.toString() ?? '');
                  if (pid == null || pid <= 0) return const SizedBox.shrink();
                  return Container(
                    decoration: _detailCardDecoration(theme),
                    padding: const EdgeInsets.all(20),
                    child: ReviewsSection(
                      type: ReviewTargetType.product,
                      targetId: pid,
                      targetName: p['name']?.toString(),
                      initialRating: parseJsonDouble(_product['rating']),
                      initialReviewCount:
                          parseJsonInt(_product['review_count']),
                    ),
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
              child: Text(
                t('store'),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _buildStoreSection(context),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: _storeId != null
                  ? MediaQuery.of(context).padding.bottom + 140
                  : 32,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _storeId != null
          ? SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: _detailSurface(theme),
                  border: Border(top: BorderSide(color: _detailBorder(theme))),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: inStock ? _addToCart : null,
                        icon: const Icon(Icons.add_shopping_cart_outlined, size: 20),
                        label: Text(t('add_to_cart') ?? 'Add to cart'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          disabledBackgroundColor:
                              theme.colorScheme.primary.withValues(alpha: 0.35),
                          disabledForegroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _messageStore,
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                        label: Text(t('message_store') ?? 'Message'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 1.25,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
