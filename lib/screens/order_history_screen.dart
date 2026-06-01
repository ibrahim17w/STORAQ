// lib/screens/order_history_screen.dart
// FIXED: Shows offline orders alongside server orders

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(refresh: true),
          ),
        ],
      ),
      body: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator())
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
                        backgroundColor: isOffline
                            ? Colors.orange.shade100
                            : theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.receipt,
                          color: isOffline
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
                          if (isOffline)
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
                        if (isOffline) {
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
