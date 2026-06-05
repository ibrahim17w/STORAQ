// lib/screens/order_history_screen.dart
// FIXED: Shows offline orders alongside server orders

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'receipt_screen.dart';
import '../lang/translations.dart';
import '../services/order_service.dart';
import '../services/offline_service.dart';
import '../services/product_service.dart';

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
    _tryAutoSync();
  }

  Future<void> _tryAutoSync() async {
    try {
      if (!await ApiService.isServerReachable()) return;
      final storeId = await ApiService.getMyStoreId();
      if (storeId == null) return;
      final hasWork =
          await OfflineService.pendingProductChangeCount() > 0 ||
          await OfflineService.pendingOrderCount() > 0;
      if (!hasWork) return;
      await ProductService.syncStore(storeId);
      if (mounted) await _load(refresh: true);
    } catch (_) {}
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
    final pendingReceipts = <String>{};

    try {
      final pendingOrders = await OfflineService.getPendingOrders();
      for (final pending in pendingOrders) {
        final orderData = pending['order_data'] as Map<String, dynamic>? ?? {};
        final receipt = orderData['receipt_number']?.toString();
        if (receipt != null && receipt.isNotEmpty) {
          pendingReceipts.add(receipt);
        }
      }
    } catch (_) {}

    try {
      final offlineOrders = await OfflineService.getOfflineOrders();
      for (final order in offlineOrders) {
        final receipt = order['receipt_number']?.toString() ?? '';
        order['pending_sync'] = pendingReceipts.contains(receipt);
        allOrders.add(order);
      }
    } catch (_) {}

    // Legacy queued orders saved before offline_orders persistence
    try {
      final pendingOrders = await OfflineService.getPendingOrders();
      final existingReceipts = allOrders
          .map((o) => o['receipt_number']?.toString() ?? '')
          .where((r) => r.isNotEmpty)
          .toSet();
      for (final pending in pendingOrders) {
        final orderData = pending['order_data'] as Map<String, dynamic>? ?? {};
        final receipt = orderData['receipt_number']?.toString() ?? '';
        if (receipt.isNotEmpty && existingReceipts.contains(receipt)) continue;
        allOrders.add({
          ...orderData,
          'id': 'pending_${pending['id']}',
          'offline': true,
          'pending_sync': true,
        });
      }
    } catch (_) {}
    List<dynamic> serverOrders = [];
    bool serverFailed = false;
    try {
      if (await ApiService.isServerReachable()) {
        serverOrders = await OrderService.fetchOrders(
          limit: _limit,
          offset: _offset,
        );
      } else {
        serverOrders = await OrderService.fetchOrdersOffline(
          limit: _limit,
          offset: _offset,
        );
        serverFailed = true;
      }
    } catch (e) {
      try {
        serverOrders = await OrderService.fetchOrdersOffline(
          limit: _limit,
          offset: _offset,
        );
      } catch (_) {}
      serverFailed = true;
    }

    // Merge server orders; server copy wins over offline with same receipt #
    final receiptKeys = <String>{
      for (final o in allOrders)
        o['receipt_number']?.toString() ?? '',
    }..remove('');
    final serverReceipts = <String>{};
    for (final s in serverOrders) {
      final receipt = s['receipt_number']?.toString() ?? '';
      if (receipt.isNotEmpty) serverReceipts.add(receipt);
    }

    allOrders.removeWhere((o) {
      if (o['offline'] != true) return false;
      final receipt = o['receipt_number']?.toString() ?? '';
      if (receipt.isNotEmpty && serverReceipts.contains(receipt)) {
        return true;
      }
      for (final s in serverOrders) {
        if (_isLikelySameReceipt(o, s)) return true;
      }
      return false;
    });

    for (final s in serverOrders) {
      final key = s['receipt_number']?.toString() ?? s['id']?.toString() ?? '';
      if (key.isEmpty || receiptKeys.contains(key)) continue;
      allOrders.add(s);
      receiptKeys.add(key);
    }

    if (mounted) {
      setState(() {
        _orders = allOrders
          ..sort((a, b) {
            final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });
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

    if (!await ApiService.isServerReachable()) {
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

    try {
      final storeId = await ApiService.getMyStoreId();
      if (storeId == null) {
        throw Exception(t('no_store_found') ?? 'No store found');
      }
      final combined = await ProductService.syncStore(storeId);
      final result = combined['orders'] as Map<String, dynamic>? ?? {};
      await _load(refresh: true);

      if (!mounted) return;
      final synced = result['synced'] as int? ?? 0;
      final failed = result['failed'] as int? ?? 0;
      final lastError = result['lastError']?.toString();

      if (synced == 0 && failed == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('no_pending_orders') ?? 'No pending orders to sync',
            ),
            backgroundColor: Colors.blue,
          ),
        );
        return;
      }

      final message = failed > 0 && lastError != null
          ? '${t('synced') ?? 'Synced'}: $synced, ${t('failed') ?? 'Failed'}: $failed\n${lastError.substring(0, lastError.length > 100 ? 100 : lastError.length)}'
          : '${t('synced') ?? 'Synced'}: $synced, ${t('failed') ?? 'Failed'}: $failed';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failed > 0 ? Colors.orange : Colors.green,
          duration: Duration(seconds: failed > 0 ? 5 : 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  bool _isLikelySameReceipt(Map<dynamic, dynamic> offline, dynamic server) {
    final tOff = DateTime.tryParse(offline['created_at']?.toString() ?? '');
    final tSrv = DateTime.tryParse(server['created_at']?.toString() ?? '');
    if (tOff == null || tSrv == null) return false;
    if (tOff.difference(tSrv).inMinutes.abs() > 10) return false;

    double totalOff = 0;
    double totalSrv = 0;
    final vOff = offline['total'];
    final vSrv = server['total'];
    if (vOff is num) totalOff = vOff.toDouble();
    if (vSrv is num) totalSrv = vSrv.toDouble();
    return (totalOff - totalSrv).abs() < 0.02;
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
