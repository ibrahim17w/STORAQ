// lib/screens/my_store_screen.dart
// FIXED: Image resolution now uses centralized CachedAppImage widget
// to properly display both cached server images and offline pending images.
//
// ADDED (multi-currency): Owner-only Currency Settings card + bottom sheet.
// All existing methods and behavior are preserved exactly.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/store_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../lang/translations.dart';
import '../widgets/cached_image.dart';
import 'store_qr_screen.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';
import 'dart:convert';
import '../services/store_service.dart';
import '../services/product_service.dart';
import '../services/order_service.dart';
import '../services/currency_service.dart';
import '../services/subscription_service.dart';
import '../models/models.dart';
import 'subscription_upgrade_screen.dart';
import 'online_products_screen.dart';

class MyStoreScreen extends ConsumerStatefulWidget {
  const MyStoreScreen({super.key});

  @override
  ConsumerState<MyStoreScreen> createState() => _MyStoreScreenState();
}

class _MyStoreScreenState extends ConsumerState<MyStoreScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  bool _needsRefresh = false;
  bool _isOwner = false;
  bool _canManageInventory = false;

  int _pendingCount = 0;

  // Currency display settings (defaults: no conversion until loaded)
  Map<String, dynamic> _currencySettings = {
    'display_currency': null,
    'show_both_prices': false,
    'exchange_rates': <dynamic>[],
  };

  Map<String, dynamic>? _subscriptionStatus;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(storeProvider.notifier).refresh());
    _loadPermissions();
    _loadCurrencySettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    _isOwner = await ApiService.isStoreOwner();
    _canManageInventory = await ApiService.canManageInventory();
  }

  Future<void> _loadCurrencySettings() async {
    try {
      final settings = await CurrencyService.getCurrencySettings();
      if (mounted) setState(() => _currencySettings = settings.toLegacyMap());
    } catch (_) {}
  }

  Future<void> _loadSubscriptionStatus() async {
    try {
      final status = await SubscriptionService.getStatus();
      if (mounted) setState(() => _subscriptionStatus = status);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _needsRefresh) {
      _needsRefresh = false;
      _loadData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsRefresh) {
      _needsRefresh = false;
      scheduleMicrotask(() => _loadData());
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    await ref.read(storeProvider.notifier).refresh();

    final results = await Future.wait([
      ApiService.isStoreOwner().catchError((_) => false),
      OfflineService.pendingProductChangeCount().catchError((_) => 0),
    ]);

    final isOwner = results[0] as bool;
    final pending = results[1] as int;
    final canManage = await ApiService.canManageInventory();

    if (mounted) {
      setState(() {
        _isOwner = isOwner;
        _canManageInventory = canManage;
        _pendingCount = pending;
      });
    }

    unawaited(_loadCurrencySettings());
    unawaited(_loadSubscriptionStatus());
  }

  Future<void> _navigateToAddProduct() async {
    _needsRefresh = true;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
    _needsRefresh = false;
    await _loadData();
  }

  Future<void> _navigateToEditProduct(Map<String, dynamic> product) async {
    _needsRefresh = true;
    final editProduct = Map<String, dynamic>.from(product);

    final images = product['images'];
    final imageUrls = product['image_urls'];
    if (imageUrls == null && images != null) {
      if (images is List) {
        editProduct['image_urls'] = images.map((e) => e.toString()).toList();
      } else if (images is String) {
        try {
          final decoded = jsonDecode(images);
          if (decoded is List) {
            editProduct['image_urls'] = decoded
                .map((e) => e.toString())
                .toList();
          }
        } catch (_) {}
      }
    }

    final categoryIds = product['category_ids'] ?? product['category_id'];
    if (categoryIds != null && editProduct['category_ids'] == null) {
      if (categoryIds is List) {
        editProduct['category_ids'] = categoryIds;
      } else if (categoryIds is int) {
        editProduct['category_ids'] = [categoryIds];
      }
    }

    if (product['price'] != null) {
      editProduct['price'] = product['price'].toString();
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => AddProductScreen(product: editProduct)),
    );
    _needsRefresh = false;
    await _loadData();
  }

  Future<void> _syncAllPending() async {
    if (!ref.read(connectivityProvider).isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('no_internet') ?? 'No internet connection'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final storeId = ref.read(storeProvider).myStore?.intId;
      if (storeId == null) {
        throw Exception(t('no_store_found') ?? 'No store found');
      }

      final result = await ProductService.syncStore(storeId);
      final productSummary = result['products'] as Map<String, dynamic>? ?? {};
      final orderResult = result['orders'] as Map<String, dynamic>? ?? {};
      final productErr = productSummary['error']?.toString();
      final orderSynced = orderResult['synced'] as int? ?? 0;
      final orderFailed = orderResult['failed'] as int? ?? 0;
      final orderErr = orderResult['lastError']?.toString();
      final productFailed = productSummary['failed'] as int? ?? 0;

      await _loadData();

      if (!mounted) return;

      if (productErr != null && productFailed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(productErr),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      final msg = orderFailed > 0 && orderErr != null
          ? '${t('synced')} ${t('products')}. ${t('orders')}: $orderSynced ${t('ok')}, $orderFailed ${t('failed')}.\n$orderErr'
          : '${t('sync_complete')} — ${t('orders')}: $orderSynced';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: orderFailed > 0 ? Colors.orange : Colors.green,
          duration: Duration(seconds: orderFailed > 0 ? 6 : 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _syncOfflineOrders() async {
    final pending = await OfflineService.getPendingOrders();
    if (pending.isEmpty) return;

    int synced = 0;
    int failed = 0;

    try {
      final result = await OrderService.syncPendingOrders();
      synced = result['synced'] as int? ?? 0;
      failed = result['failed'] as int? ?? 0;
    } catch (_) {
      failed = pending.length;
    }

    if (mounted && (synced > 0 || failed > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${t('synced') ?? 'Synced'}: $synced, ${t('failed') ?? 'Failed'}: $failed',
          ),
          backgroundColor: failed > 0 ? Colors.orange : Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteProduct(dynamic id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('delete_product') ?? 'Delete Product'),
        content: Text(t('delete_product_confirm') ?? 'Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t('delete') ?? 'Delete',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final storeId = ref.read(storeProvider).myStore?.intId;

      if (id is String && id.startsWith('pending_')) {
        final pendingId = int.tryParse(id.replaceFirst('pending_', ''));
        if (pendingId != null) {
          await OfflineService.removePending(pendingId);
          await OfflineService.removeCachedProduct(pendingId);
        }
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t('product_deleted') ?? 'Product deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      final intId = id is int ? id : int.tryParse(id.toString());
      if (intId != null && storeId != null) {
        await ProductService.deleteProductOfflineAware(intId, storeId);
      } else if (intId != null) {
        await ProductService.deleteProduct(intId);
      }
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('product_deleted') ?? 'Product deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _inviteStaffMember() async {
    final emailCtrl = TextEditingController();
    bool canManageInventory = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(t('add_staff') ?? 'Add Staff Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: t('email') ?? 'Email',
                  prefixIcon: const Icon(Icons.email),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: canManageInventory,
                onChanged: (v) =>
                    setDlgState(() => canManageInventory = v ?? false),
                title: Text(
                  t('can_manage_inventory') ?? 'Can manage inventory',
                ),
                subtitle: Text(
                  t('can_manage_inventory_desc') ??
                      'Allow adding, editing, and deleting products',
                  style: const TextStyle(fontSize: 12),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel') ?? 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('invite') ?? 'Invite'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    if (emailCtrl.text.trim().isEmpty) return;

    try {
      await StoreService.inviteStaffMember(
        email: emailCtrl.text.trim(),
        canManageInventory: canManageInventory,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('staff_invited') ?? 'Staff member invited'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeStaffMember(int staffId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('remove_staff') ?? 'Remove Staff Member'),
        content: Text(t('remove_staff_confirm') ?? 'Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t('remove') ?? 'Remove',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await StoreService.removeStaffMember(staffId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('staff_removed') ?? 'Staff member removed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleStaffPermission(int staffId, bool currentValue) async {
    try {
      await StoreService.updateStaffPermissions(
        staffId,
        canManageInventory: !currentValue,
      );
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ============================================================
  // CURRENCY SETTINGS (owner only)
  // ============================================================

  Future<void> _openCurrencySettings() async {
    final saved = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CurrencySettingsSheet(
        initialSettings: _currencySettings,
      ),
    );
    if (saved != null && mounted) {
      setState(() => _currencySettings = saved);
      // Refresh products so precomputed display prices are reflected.
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    final storeState = ref.watch(storeProvider);
    final connectivityState = ref.watch(connectivityProvider);
    final isOffline = !connectivityState.isOnline;
    final store = storeState.myStore;
    final products = storeState.catalog.map((p) => p.toJson()).toList();
    final staff = storeState.staff;

    if (storeState.isLoading && products.isEmpty) {
      return const _MyStoreSkeleton();
    }
    if (storeState.error != null && products.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                t('error_loading_store') ?? 'Error loading store',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadData,
                child: Text(t('retry') ?? 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final storeName = store?.name ?? t('my_store') ?? 'My Store';
    final storeImage = store?.imageUrl;

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.light
          ? const Color(0xFFF8F9FA)
          : theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  storeName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                background: storeImage != null && storeImage.isNotEmpty
                    ? CachedAppImage(
                        imageUrl: storeImage,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          color: theme.colorScheme.primaryContainer,
                        ),
                      )
                    : Container(color: theme.colorScheme.primaryContainer),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: t('refresh') ?? 'Refresh',
                ),
              ],
            ),

            if (isOffline)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_off,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('offline_working') ??
                              'Working offline — changes will sync when connection returns',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_pendingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_pendingCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            if (!isOffline && _pendingCount > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ElevatedButton.icon(
                    onPressed: _syncAllPending,
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: Text(
                      '${t('sync') ?? 'Sync'} $_pendingCount ${t('pending_changes') ?? 'pending changes'}',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),

            // Subscription card (owner only)
            if (_isOwner && _subscriptionStatus != null)
              SliverToBoxAdapter(
                child: _SubscriptionCard(
                  status: _subscriptionStatus!,
                  onUpgrade: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubscriptionUpgradeScreen(
                          initialStatus: _subscriptionStatus,
                        ),
                      ),
                    );
                    await _loadSubscriptionStatus();
                  },
                  onManageOnline: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OnlineProductsScreen(),
                      ),
                    );
                    await _loadData();
                  },
                ),
              ),

            // Currency Settings card (owner only) — near top of screen.
            if (_isOwner)
              SliverToBoxAdapter(
                child: _CurrencySettingsCard(
                  settings: _currencySettings,
                  onTap: _openCurrencySettings,
                ),
              ),

            if (_isOwner && store?.intId != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoreQrScreen(
                              storeId: store!.intId!,
                              storeName: storeName,
                            ),
                          ),
                        );
                      },
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.qr_code_2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        t('store_qr_code') ?? 'Store QR Code',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        t('store_qr_short_hint') ??
                            'Show, print, or share your store QR',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${products.length} ${t('products') ?? 'Products'}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_canManageInventory)
                      FilledButton.icon(
                        onPressed: _navigateToAddProduct,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(t('add_product') ?? 'Add Product'),
                      ),
                  ],
                ),
              ),
            ),

            if (_isOwner)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: ExpansionTile(
                      leading: const Icon(Icons.people),
                      title: Text(
                        t('staff_management') ?? 'Staff Management',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${staff.length} ${t('members') ?? 'members'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      children: [
                        if (staff.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              t('no_staff_yet') ??
                                  'No staff members yet. Tap + to invite.',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          ...staff.map((s) {
                            final name =
                                s['full_name']?.toString() ??
                                s['email']?.toString() ??
                                'Unknown';
                            final canManage = s['can_manage_inventory'] == true;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              title: Text(name),
                              subtitle: Text(
                                canManage
                                    ? (t('inventory_manager') ??
                                          'Inventory Manager')
                                    : (t('cashier_only') ?? 'Cashier Only'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: canManage
                                      ? Colors.green.shade700
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message:
                                        t('toggle_inventory') ??
                                        'Toggle inventory access',
                                    child: IconButton(
                                      icon: Icon(
                                        canManage
                                            ? Icons.inventory_2
                                            : Icons.inventory_2_outlined,
                                        color: canManage
                                            ? Colors.green
                                            : theme.colorScheme.outline,
                                      ),
                                      onPressed: () => _toggleStaffPermission(
                                        s['id'],
                                        canManage,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle,
                                      color: Colors.red,
                                    ),
                                    onPressed: () =>
                                        _removeStaffMember(s['id']),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _inviteStaffMember,
                              icon: const Icon(Icons.person_add),
                              label: Text(t('add_staff') ?? 'Add Staff Member'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t('no_products_yet') ?? 'No products yet',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_canManageInventory)
                        OutlinedButton.icon(
                          onPressed: _navigateToAddProduct,
                          icon: const Icon(Icons.add),
                          label: Text(
                            t('add_first_product') ?? 'Add First Product',
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final product = products[index];
                    return _ProductCard(
                      product: product,
                      currencySettings: _currencySettings,
                      onEdit: _canManageInventory
                          ? () => _navigateToEditProduct(product)
                          : null,
                      onDelete: _canManageInventory
                          ? () => _deleteProduct(product['id'])
                          : null,
                    );
                  }, childCount: products.length),
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
      floatingActionButton: _canManageInventory
          ? FloatingActionButton(
              onPressed: _navigateToAddProduct,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// ============================================================
// CURRENCY SETTINGS CARD (summary + entry point)
// ============================================================

class _SubscriptionCard extends StatelessWidget {
  final Map<String, dynamic> status;
  final VoidCallback onUpgrade;
  final VoidCallback onManageOnline;

  const _SubscriptionCard({
    required this.status,
    required this.onUpgrade,
    required this.onManageOnline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onlineCount = status['online_count'] as int? ?? 0;
    final onlineLimit = status['online_limit'] as int? ?? 5;
    final progress = onlineLimit > 0 ? (onlineCount / onlineLimit).clamp(0.0, 1.0) : 0.0;
    final tier = status['tier'] as Map<String, dynamic>?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.storefront, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('marketplace_listing') ?? 'Marketplace Listing',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          tier != null
                              ? '${tier['name']} ${t('plan') ?? 'plan'}'
                              : (t('free_plan') ?? 'Free plan'),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onUpgrade,
                    child: Text(t('upgrade') ?? 'Upgrade'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${t('online') ?? 'Online'}: $onlineCount / $onlineLimit',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onManageOnline,
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(t('manage_online_products') ?? 'Manage Online Products'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencySettingsCard extends StatelessWidget {
  final Map<String, dynamic> settings;
  final VoidCallback onTap;

  const _CurrencySettingsCard({required this.settings, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayCurrency = settings['display_currency']?.toString();
    final rates = CurrencyService.parseRates(settings['exchange_rates']);
    final hasCurrency = displayCurrency != null && displayCurrency.isNotEmpty;

    final subtitle = hasCurrency
        ? '${t('display') ?? 'Display'}: $displayCurrency • ${rates.length} ${t('exchange_rates') ?? 'exchange rates'}'
        : (t('no_display_currency_set') ?? 'No display currency set');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.currency_exchange,
              color: theme.colorScheme.primary,
            ),
          ),
          title: Text(
            t('currency_settings') ?? 'Currency Settings',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

// ============================================================
// CURRENCY SETTINGS BOTTOM SHEET
// ============================================================

class _RateRow {
  final TextEditingController fromCtrl;
  final TextEditingController rateCtrl;
  bool isAuto;
  String? provider;
  String? autoFetchedAt;
  String? autoSource;

  _RateRow({
    String from = '',
    String rate = '',
    this.isAuto = false,
    this.provider,
    this.autoFetchedAt,
    this.autoSource,
  }) : fromCtrl = TextEditingController(text: from),
       rateCtrl = TextEditingController(text: rate);

  void dispose() {
    fromCtrl.dispose();
    rateCtrl.dispose();
  }
}

class _CurrencySettingsSheet extends StatefulWidget {
  final Map<String, dynamic> initialSettings;

  const _CurrencySettingsSheet({required this.initialSettings});

  @override
  State<_CurrencySettingsSheet> createState() => _CurrencySettingsSheetState();
}

class _CurrencySettingsSheetState extends State<_CurrencySettingsSheet> {
  late TextEditingController _displayCurrencyCtrl;
  bool _showBothPrices = false;
  final List<_RateRow> _rows = [];
  bool _saving = false;
  bool _refreshing = false;

  // Auto-rate providers. IDs must match the backend (store_currency.js).
  static const List<String> _providerIds = [
    'frankfurter',
    'exchangerate',
    'syria_market',
    'syria_official',
  ];

  String _providerLabel(String id) {
    switch (id) {
      case 'frankfurter':
        return t('provider_frankfurter') ?? 'Frankfurter (official)';
      case 'exchangerate':
        return t('provider_exchangerate') ?? 'ExchangeRate-API (official)';
      case 'syria_market':
        return t('provider_syria_market') ??
            'Syria market rate (sp-today / syriato)';
      case 'syria_official':
        return t('provider_syria_official') ?? 'Syria central bank rate';
      default:
        return id;
    }
  }

  /// True when the display currency is the Syrian pound, in which case the
  /// Syria-specific market/official rate sources (sp-today / syriato) apply.
  bool get _isSyrianDisplay {
    final c = _displayCurrencyCtrl.text.trim().toLowerCase();
    return c == 'syp' ||
        c == 'sp' ||
        c.contains('ل.س') ||
        c.contains('سوري') ||
        c.contains('ليرة');
  }

  List<String> get _availableProviderIds {
    if (_isSyrianDisplay) return _providerIds;
    return _providerIds
        .where((id) => id != 'syria_market' && id != 'syria_official')
        .toList();
  }

  List<DropdownMenuItem<String>> _providerItems() {
    return _availableProviderIds
        .map(
          (id) => DropdownMenuItem<String>(
            value: id,
            child: Text(
              _providerLabel(id),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
    _displayCurrencyCtrl = TextEditingController(
      text: s['display_currency']?.toString() ?? '',
    );
    _showBothPrices = s['show_both_prices'] == true;
    final rates = CurrencyService.parseRates(s['exchange_rates']);
    for (final r in rates) {
      _rows.add(
        _RateRow(
          from: r['from']?.toString() ?? '',
          rate: r['rate'] != null ? r['rate'].toString() : '',
          isAuto: r['is_auto'] == true,
          provider: r['provider']?.toString(),
          autoFetchedAt: r['auto_fetched_at']?.toString(),
          autoSource: r['auto_source']?.toString(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _displayCurrencyCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRate() {
    setState(() => _rows.add(_RateRow()));
  }

  void _removeRate(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  bool get _anyAuto => _rows.any((r) => r.isAuto);

  List<Map<String, dynamic>> _buildRates(String displayCurrency) {
    final rates = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final from = r.fromCtrl.text.trim();
      if (from.isEmpty) continue;
      final rate = double.tryParse(r.rateCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      rates.add({
        'from': from,
        'to': displayCurrency,
        'rate': rate,
        'is_auto': r.isAuto,
        'provider': r.isAuto ? r.provider : null,
        'auto_fetched_at': r.autoFetchedAt,
        'auto_source': r.autoSource,
      });
    }
    return rates;
  }

  Future<void> _save() async {
    final displayCurrency = _displayCurrencyCtrl.text.trim();
    if (displayCurrency.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('display_currency_required') ?? 'Display currency is required',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await CurrencyService.updateCurrencySettings(
        displayCurrency,
        _showBothPrices,
        _buildRates(displayCurrency),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('currency_settings_saved') ?? 'Currency settings saved',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshAuto() async {
    final displayCurrency = _displayCurrencyCtrl.text.trim();
    if (displayCurrency.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('display_currency_required') ?? 'Display currency is required',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _refreshing = true);
    try {
      // Persist the current edits first so the server refreshes the right rows.
      await CurrencyService.updateCurrencySettings(
        displayCurrency,
        _showBothPrices,
        _buildRates(displayCurrency),
      );
      final result = await CurrencyService.refreshAutoRates();
      if (!mounted) return;

      // Re-hydrate rows from the refreshed server rates.
      final rates = CurrencyService.parseRates(result['exchange_rates']);
      for (final r in _rows) {
        r.dispose();
      }
      _rows.clear();
      for (final r in rates) {
        _rows.add(
          _RateRow(
            from: r['from']?.toString() ?? '',
            rate: r['rate'] != null
                ? CurrencyService.formatRate(r['rate'])
                : '',
            isAuto: r['is_auto'] == true,
            provider: r['provider']?.toString(),
            autoFetchedAt: r['auto_fetched_at']?.toString(),
            autoSource: r['auto_source']?.toString(),
          ),
        );
      }

      final warnings = (result['warnings'] is List)
          ? List<String>.from(result['warnings'])
          : <String>[];

      setState(() {});

      if (warnings.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(warnings.join('\n')),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('auto_rates_refreshed') ?? 'Automatic rates refreshed',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayCurrency = _displayCurrencyCtrl.text.trim();
    final displayLabel = displayCurrency.isEmpty
        ? (t('display') ?? 'Display')
        : displayCurrency;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Material(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.currency_exchange, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('currency_settings') ?? 'Currency Settings',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  TextField(
                    controller: _displayCurrencyCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: t('display_currency') ?? 'Display Currency',
                      hintText: 'USD',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _showBothPrices,
                    onChanged: (v) => setState(() => _showBothPrices = v),
                    title: Text(t('show_both_prices') ?? 'Show both prices'),
                    subtitle: Text(
                      t('show_both_prices_desc') ??
                          'Show the original price next to the converted price',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Warning banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade800,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t('auto_rate_warning') ??
                                'Auto rates may show official rates, not black market rates. For currencies like SYP, manual rates are recommended.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        t('exchange_rates') ?? 'Exchange Rates',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('exchange_rates_helper') ??
                        'Add a rate for each product currency to convert it into your display currency.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._rows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: row.fromCtrl,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: InputDecoration(
                                    labelText: t('from_currency') ?? 'From',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  displayLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: row.rateCtrl,
                                  enabled: !row.isAuto,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: t('rate') ?? 'Rate',
                                    isDense: true,
                                    helperText: row.isAuto && row.autoSource != null
                                        ? '${t('auto_from') ?? 'Auto from'} ${row.autoSource}'
                                        : (row.isAuto
                                              ? (t('auto') ?? 'Auto')
                                              : (t('manual_rate') ?? 'Manual')),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    t('auto') ?? 'Auto',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  Switch(
                                    value: row.isAuto,
                                    onChanged: (v) =>
                                        setState(() => row.isAuto = v),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removeRate(i),
                              ),
                            ],
                          ),
                          if (row.isAuto) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _availableProviderIds.contains(row.provider)
                                  ? row.provider
                                  : null,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: t('rate_source') ?? 'Rate source',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              hint: Text(t('auto_best') ?? 'Best available'),
                              items: _providerItems(),
                              onChanged: (v) =>
                                  setState(() => row.provider = v),
                            ),
                          ],
                          const Divider(height: 12),
                        ],
                      ),
                    );
                  }).toList(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addRate,
                      icon: const Icon(Icons.add),
                      label: Text(t('add_rate') ?? '+ Add Exchange Rate'),
                    ),
                  ),
                  if (_anyAuto) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _refreshing ? null : _refreshAuto,
                        icon: _refreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(t('refresh_auto') ?? 'Refresh Auto Rates'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(t('save_settings') ?? 'Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Map<String, dynamic>? currencySettings;

  const _ProductCard({
    required this.product,
    this.onEdit,
    this.onDelete,
    this.currencySettings,
  });

  // CRITICAL FIX: Use CachedAppImage which properly handles file:// prefix,
  // local file paths, remote URLs, and all edge cases.
  Widget _buildProductImage(BuildContext context) {
    final imagePaths = OfflineService.getProductImagePaths(product);
    final firstPath = imagePaths.isNotEmpty ? imagePaths.first : null;

    return CachedAppImage(
      imageUrl: firstPath,
      width: 72,
      height: 72,
      borderRadius: BorderRadius.circular(10),
      placeholder: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.inventory_2_outlined),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = product['name']?.toString() ?? t('unnamed');
    final qty = product['quantity'] ?? 0;
    final isLowStock = (qty as num) <= (product['low_stock_threshold'] ?? 5);
    final isPendingCreate = product['_pendingCreate'] == true;
    final isPendingUpdate = product['_pendingUpdate'] == true;
    final isStoreOnly = product['is_online'] == false && !isPendingCreate;

    final info = CurrencyService.getProductDisplayInfo(product, currencySettings);
    final originalPrice = info['original_price'];
    final originalCurrency = info['original_currency'] as String;
    final displayPrice = info['display_price'];
    final displayCurrency = info['display_currency'] as String?;
    final showBoth = info['show_both'] == true;
    final hasDisplay = displayPrice != null && displayCurrency != null;

    final primaryPriceText = hasDisplay
        ? CurrencyService.formatPrice(displayPrice, displayCurrency)
        : CurrencyService.formatPrice(originalPrice, originalCurrency);
    final showSecondary = hasDisplay && showBoth;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildProductImage(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPendingCreate)
                          _PendingBadge(
                            label: t('pending_create') ?? 'Pending create',
                            color: Colors.green,
                          )
                        else if (isPendingUpdate)
                          _PendingBadge(
                            label: t('pending_update') ?? 'Pending update',
                            color: Colors.orange,
                          )
                        else if (isStoreOnly)
                          _PendingBadge(
                            label: t('store_only') ?? 'Store only',
                            color: Colors.grey,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      primaryPriceText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (showSecondary)
                      Text(
                        '(${CurrencyService.formatPrice(originalPrice, originalCurrency)})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isLowStock ? Icons.warning_amber : Icons.inventory_2,
                          size: 14,
                          color: isLowStock
                              ? Colors.orange
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$qty ${t('in_stock') ?? 'in stock'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isLowStock
                                ? Colors.orange
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    if (onEdit != null)
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(t('edit') ?? 'Edit'),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          t('delete') ?? 'Delete',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _PendingBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _MyStoreSkeleton extends StatelessWidget {
  const _MyStoreSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(color: baseColor),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                );
              }, childCount: 6),
            ),
          ),
        ],
      ),
    );
  }
}
