// lib/screens/my_store_screen.dart
// FIXED: Better offline loading with storeId fallback, no crashes on empty data

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../lang/translations.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';
import 'dart:convert';
import '../services/store_service.dart';
import '../services/product_service.dart';
import '../services/order_service.dart';

class MyStoreScreen extends StatefulWidget {
  const MyStoreScreen({super.key});

  @override
  State<MyStoreScreen> createState() => _MyStoreScreenState();
}

class _MyStoreScreenState extends State<MyStoreScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  Map<String, dynamic>? _store;
  List<dynamic> _products = [];
  List<dynamic> _staff = [];
  bool _loading = true;
  String? _error;
  bool _needsRefresh = false;
  bool _isOwner = false;
  bool _canManageInventory = false;
  bool _showStaffSection = false;

  // Offline state
  bool _isOffline = false;
  int _pendingCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConnectivity();
    _loadPermissions();
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _updateConnectivity(result);
    Connectivity().onConnectivityChanged.listen(
      (results) => _updateConnectivity(results),
    );
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final wasOffline = _isOffline;
    setState(() => _isOffline = results.contains(ConnectivityResult.none));
    if (wasOffline && !_isOffline) {
      // Came back online — auto-sync
      _syncAllPending();
    }
  }

  Future<void> _loadPermissions() async {
    _isOwner = await ApiService.isStoreOwner();
    _canManageInventory = await ApiService.canManageInventory();
  }

  /// Called when app lifecycle changes. When resumed, check if we need refresh.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _needsRefresh) {
      _needsRefresh = false;
      _loadData();
    }
  }

  /// Called when dependencies change — also when returning from navigation
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsRefresh) {
      _needsRefresh = false;
      // Use microtask to avoid setState during build
      scheduleMicrotask(() => _loadData());
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Step 1: Get store (try server, then cache, then context fallback)
      final store = await StoreService.getMyStore();
      final storeId = store['id'] as int;

      // Step 2: Load everything in PARALLEL (products, staff, pending count)
      final results = await Future.wait([
        _isOffline
            ? OfflineService.getMergedProducts(storeId)
            : ProductService.fetchProducts(
                storeId,
                useCache: false,
              ).catchError((_) => OfflineService.getMergedProducts(storeId)),
        ApiService.isStoreOwner().catchError((_) => false),
        OfflineService.pendingProductChangeCount().catchError((_) => 0),
        // Staff only loads if owner — wrapped to not block others
        Future.value(null), // placeholder, loaded separately if needed
      ]);

      List<dynamic> products = results[0] as List<dynamic>;
      final isOwner = results[1] as bool;
      final pending = results[2] as int;

      // Load staff in parallel with setting state (non-blocking)
      List<dynamic> staff = [];
      if (isOwner) {
        StoreService.fetchMyStoreStaff()
            .then((s) {
              if (mounted) setState(() => _staff = s);
            })
            .catchError((_) {});
      }

      if (mounted) {
        setState(() {
          _store = store;
          _products = products;
          _isOwner = isOwner;
          _canManageInventory =
              isOwner; // Owner always can; staff check done in _loadPermissions
          _pendingCount = pending;
          _staff = staff;
          _loading = false;
        });
      }
    } catch (e) {
      // getMyStore() already tried cache and context fallback — if all failed, we have nothing
      if (mounted) {
        setState(() {
          _error =
              t('no_store_found') ??
              'No store found. Please login online first.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _navigateToAddProduct() async {
    _needsRefresh = true;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
    // ALWAYS refresh when returning — product may have been added
    _needsRefresh = false;
    await _loadData();
  }

  Future<void> _navigateToEditProduct(Map<String, dynamic> product) async {
    _needsRefresh = true;
    // FIXED: Ensure all required fields are present for editing
    final editProduct = Map<String, dynamic>.from(product);

    // Normalize image fields — backend may return 'images' (JSONB) or 'image_urls'
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

    // Ensure category_ids is a list
    final categoryIds = product['category_ids'] ?? product['category_id'];
    if (categoryIds != null && editProduct['category_ids'] == null) {
      if (categoryIds is List) {
        editProduct['category_ids'] = categoryIds;
      } else if (categoryIds is int) {
        editProduct['category_ids'] = [categoryIds];
      }
    }

    // Ensure price is properly typed
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
    if (_isOffline) {
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

    setState(() => _loading = true);
    try {
      final storeId = _store?['id'] as int?;
      if (storeId != null) {
        await ProductService.syncPendingChanges(storeId);
      }

      // Also sync offline orders
      await _syncOfflineOrders();

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('synced') ?? 'Sync complete'),
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncOfflineOrders() async {
    final pending = await OfflineService.getPendingOrders();
    if (pending.isEmpty) return;

    int synced = 0;
    int failed = 0;

    for (final order in pending) {
      try {
        final orderData = order['order_data'] as Map<String, dynamic>;
        await OrderService.createOrder(
          items: List<Map<String, dynamic>>.from(orderData['items']),
          customerName: orderData['customer_name'],
          customerPhone: orderData['customer_phone'],
          discount: (orderData['discount'] as num?)?.toDouble() ?? 0,
          tax: (orderData['tax'] as num?)?.toDouble() ?? 0,
          notes: orderData['notes'],
          paymentMethod: orderData['payment_method'] ?? 'cash',
        );
        await OfflineService.markOrderSynced(order['id']);
        synced++;
      } catch (e) {
        failed++;
      }
    }

    // Also sync stock changes
    final stockChanges = await OfflineService.getUnsyncedStockChanges();
    for (final change in stockChanges) {
      try {
        await OfflineService.markStockChangeSynced(change['id']);
      } catch (_) {}
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
      final storeId = _store?['id'] as int?;

      // Handle pending products (string IDs like 'pending_123')
      if (id is String && id.startsWith('pending_')) {
        // Remove from pending_products table and cache
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

      // Handle server products (int IDs)
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

  // ==================== STAFF MANAGEMENT (Owner Only) ====================

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

    setState(() => _loading = true);
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
    } finally {
      if (mounted) setState(() => _loading = false);
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

    setState(() => _loading = true);
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStaffPermission(int staffId, bool currentValue) async {
    setState(() => _loading = true);
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_loading && _products.isEmpty) {
      return const _MyStoreSkeleton();
    }
    if (_error != null && _products.isEmpty) {
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

    final storeName =
        _store?['name']?.toString() ?? t('my_store') ?? 'My Store';
    final storeImage = _store?['image_url']?.toString();

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.light
          ? const Color(0xFFF8F9FA)
          : theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // App bar with store header
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  storeName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                background: storeImage != null && storeImage.isNotEmpty
                    ? Image.network(
                        storeImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
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

            // Offline banner
            if (_isOffline)
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

            // Sync button when online and pending changes exist
            if (!_isOffline && _pendingCount > 0)
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

            // Product count + add button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_products.length} ${t('products') ?? 'Products'}',
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

            // Staff Management Section (Owner Only)
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
                        '${_staff.length} ${t('members') ?? 'members'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      children: [
                        if (_staff.isEmpty)
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
                          ..._staff.map((s) {
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
                                  // Toggle inventory permission
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
                                  // Remove staff
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

            // Products grid
            if (_products.isEmpty)
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
                    final product = _products[index] as Map<String, dynamic>;
                    return _ProductCard(
                      product: product,
                      onEdit: _canManageInventory
                          ? () => _navigateToEditProduct(product)
                          : null,
                      onDelete: _canManageInventory
                          ? () => _deleteProduct(product['id'])
                          : null,
                    );
                  }, childCount: _products.length),
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

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ProductCard({required this.product, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = product['name']?.toString() ?? 'Unnamed';
    final price = product['price']?.toString() ?? '0';
    final qty = product['quantity'] ?? 0;
    final imageUrl = product['image_url']?.toString();
    final images = product['images'] as List<dynamic>?;
    final displayImage =
        imageUrl ??
        (images != null && images.isNotEmpty ? images.first.toString() : null);
    final isLowStock = (qty as num) <= (product['low_stock_threshold'] ?? 5);
    final isPendingCreate = product['_pendingCreate'] == true;
    final isPendingUpdate = product['_pendingUpdate'] == true;

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
                child: Container(
                  width: 72,
                  height: 72,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: displayImage != null
                      ? _buildImage(displayImage)
                      : const Icon(Icons.inventory_2_outlined),
                ),
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
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$price ${product['currency']?.toString() ?? 'SYP'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
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

  Widget _buildImage(String url) {
    if (url.startsWith('pending_') || url.startsWith('/')) {
      // Local file path (offline pending image)
      return const Icon(Icons.image, color: Colors.grey);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
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
// ============================================================
// MY STORE SKELETON LOADING
// ============================================================

class _MyStoreSkeleton extends StatelessWidget {
  const _MyStoreSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar skeleton
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(color: baseColor),
            ),
          ),
          // Stats row skeleton
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
          // Product cards skeleton
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
