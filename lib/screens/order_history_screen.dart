// lib/screens/order_history_screen.dart
// FIXED: Shows offline orders alongside server orders

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import 'receipt_screen.dart';
import '../lang/translations.dart';
import '../services/order_service.dart';
import '../services/offline_service.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _offset = 0;
        _orders = [];
        _hasMore = true;
      });
    }

    List<dynamic> allOrders = [];

    // 1. Load offline orders first (always available, never fails)
    try {
      final offlineOrders = await OfflineService.getOfflineOrders();
      allOrders.addAll(offlineOrders);
    } catch (_) {}

    // 2. Load pending orders (queued for sync but not yet sent)
    try {
      final pendingOrders = await OfflineService.getPendingOrders();
      for (final pending in pendingOrders) {
        final orderData = pending['order_data'] as Map<String, dynamic>? ?? {};
        allOrders.add({
          ...orderData,
          'id': 'pending_${pending['id']}',
          'offline': true,
          'pending_sync': true,
        });
      }
    } catch (_) {}

    // 3. Load server orders (optional — app works fine without this)
    List<dynamic> serverOrders = [];
    bool serverFailed = false;
    try {
      final data = await OrderService.fetchOrders(
        limit: _limit,
        offset: _offset,
      );
      serverOrders = data;
    } catch (e) {
      serverFailed = true;
    }

    // Merge server orders, avoiding duplicates with offline/pending
    final existingIds = <dynamic>{};
    for (final o in allOrders) {
      existingIds.add(o['receipt_number'] ?? o['id']);
    }
    for (final s in serverOrders) {
      final key = s['receipt_number'] ?? s['id'];
      if (!existingIds.contains(key)) {
        allOrders.add(s);
        existingIds.add(key);
      }
    }

    if (mounted) {
      setState(() {
        _orders = allOrders;
        _loading = false;
        _hasMore = !serverFailed && serverOrders.length >= _limit;
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading) return;
    setState(() => _offset += _limit);
    await _load();
  }

  Future<void> _syncOfflineOrders() async {
    if (_isSyncing) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
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

    setState(() => _isSyncing = true);

    final pending = await OfflineService.getPendingOrders();
    if (pending.isEmpty) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('no_pending_orders') ?? 'No pending orders to sync',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
      return;
    }

    int synced = 0;
    int failed = 0;
    String? lastError;

    for (final order in pending) {
      try {
        final orderData = order['order_data'] as Map<String, dynamic>;
        final itemsRaw = orderData['items'] as List<dynamic>? ?? [];

        // Convert items to backend format with defensive field mapping
        final List<Map<String, dynamic>> items = [];
        final List<String> pendingNames = [];

        for (final raw in itemsRaw) {
          final map = raw is Map<String, dynamic> ? raw : <String, dynamic>{};

          // Defensive: checkout may store fields under different names
          final dynamic productId =
              map['product_id'] ?? map['id'] ?? map['productId'];
          final productName =
              (map['product_name'] ??
                      map['name'] ??
                      map['productName'] ??
                      'Unknown')
                  .toString();
          final dynamic quantityRaw =
              map['quantity'] ?? map['qty'] ?? map['count'];
          final dynamic unitPriceRaw =
              map['unit_price'] ?? map['price'] ?? map['unitPrice'] ?? 0;
          final dynamic totalPriceRaw =
              map['total_price'] ??
              map['totalPrice'] ??
              map['line_total'] ??
              (unitPriceRaw * (quantityRaw ?? 0));
          final barcode = map['barcode'] ?? map['product_barcode'];

          int quantity;
          if (quantityRaw is int) {
            quantity = quantityRaw;
          } else if (quantityRaw is double) {
            quantity = quantityRaw.toInt();
          } else if (quantityRaw is String) {
            quantity = int.tryParse(quantityRaw) ?? 0;
          } else {
            quantity = 0;
          }

          final pidString = productId?.toString() ?? '';

          // Detect pending products that haven't been synced yet
          if (pidString.isEmpty || pidString.startsWith('pending_')) {
            pendingNames.add(productName);
            continue;
          }

          final serverProductId = productId is int
              ? productId
              : int.tryParse(pidString);
          if (serverProductId == null || serverProductId <= 0 || quantity < 1) {
            throw Exception(
              'Invalid item data for "$productName": product_id=$productId, quantity=$quantity',
            );
          }

          items.add({
            'product_id': serverProductId,
            'product_name': productName,
            'quantity': quantity,
            'unit_price': (unitPriceRaw is num
                ? unitPriceRaw.toDouble()
                : (num.tryParse(unitPriceRaw.toString()) ?? 0).toDouble()),
            'total_price': (totalPriceRaw is num
                ? totalPriceRaw.toDouble()
                : (num.tryParse(totalPriceRaw.toString()) ?? 0).toDouble()),
            'barcode': barcode?.toString(),
          });
        }

        if (pendingNames.isNotEmpty) {
          throw Exception(
            'Cannot sync order: products not yet on server: ${pendingNames.join(', ')}. Please sync products first.',
          );
        }

        if (items.isEmpty) {
          throw Exception('Order has no valid items to sync');
        }

        await OrderService.createOrder(
          items: List<Map<String, dynamic>>.from(items),
          customerName: orderData['customer_name']?.toString(),
          customerPhone: orderData['customer_phone']?.toString(),
          subtotal: (orderData['subtotal'] as num?)?.toDouble() ?? 0,
          discount: (orderData['discount'] as num?)?.toDouble() ?? 0,
          tax: (orderData['tax'] as num?)?.toDouble() ?? 0,
          total: (orderData['total'] as num?)?.toDouble() ?? 0,
          notes: orderData['notes']?.toString(),
          paymentMethod: orderData['payment_method']?.toString() ?? 'cash',
        );

        await OfflineService.markOrderSynced(order['id']);
        synced++;
      } catch (e) {
        failed++;
        lastError = e.toString();
      }
    }

    // Refresh the list
    await _load(refresh: true);

    if (mounted) {
      setState(() => _isSyncing = false);

      final message = failed > 0 && lastError != null
          ? '${t('synced') ?? 'Synced'}: $synced, ${t('failed') ?? 'Failed'}: $failed\n${lastError.substring(0, lastError.length > 100 ? 100 : lastError.length)}'
          : '${t('synced') ?? 'Synced'}: $synced, ${t('failed') ?? 'Failed'}: $failed';

      // FIXED: Removed 'const' from Duration since it uses runtime variable
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failed > 0 ? Colors.orange : Colors.green,
          duration: Duration(seconds: failed > 0 ? 5 : 3),
        ),
      );
    }
  }

  String _fmt(dynamic value, {String currency = 'SYP'}) {
    double d = 0;
    if (value is num) {
      d = value.toDouble();
    } else if (value is String) {
      d = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }
    return '${currency} ${d.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('order_history') ?? 'Order History'),
        actions: [
          // Sync button with badge
          FutureBuilder<int>(
            future: OfflineService.pendingOrderCount(),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    onPressed: _isSyncing ? null : _syncOfflineOrders,
                    tooltip: t('sync_orders') ?? 'Sync orders',
                  ),
                  if (count > 0 && !_isSyncing)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(refresh: true),
          ),
        ],
      ),
      body: _loading && _orders.isEmpty
          ? const _OrderListSkeleton()
          : _orders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('no_orders_yet') ?? 'No orders yet',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _orders.length + (_hasMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _orders.length) {
                    _loadMore();
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final order = _orders[i];
                  final isOffline = order['offline'] == true;
                  final isPending = order['pending_sync'] == true;
                  final date = DateTime.tryParse(
                    order['created_at']?.toString() ?? '',
                  );
                  final dateStr = date != null
                      ? DateFormat('yyyy-MM-dd HH:mm').format(date)
                      : '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isPending
                            ? Colors.blue.shade100
                            : isOffline
                            ? Colors.orange.shade100
                            : theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.receipt,
                          color: isPending
                              ? Colors.blue.shade700
                              : isOffline
                              ? Colors.orange.shade700
                              : theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        '${t('receipt') ?? 'Receipt'} #${order['receipt_number'] ?? order['id']}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (order['customer_name'] != null)
                            Text(
                              order['customer_name'].toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (isPending)
                            Text(
                              t('pending_sync') ?? 'Pending sync...',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (isOffline)
                            Text(
                              t('offline_receipt') ?? 'Offline Receipt',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      trailing: Text(
                        _fmt(
                          order['total'],
                          currency: order['currency']?.toString() ?? 'SYP',
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      onTap: () {
                        if (isOffline || isPending) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReceiptScreen(offlineOrder: order),
                            ),
                          );
                        } else {
                          final orderId = order['id'];
                          if (orderId is int) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReceiptScreen(orderId: orderId),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ============================================================
// SKELETON LOADING WIDGET
// ============================================================

class _OrderListSkeleton extends StatelessWidget {
  const _OrderListSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (_, __) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: baseColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 16,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 12,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 60,
                  height: 16,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
