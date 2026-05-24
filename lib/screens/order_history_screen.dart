// lib/screens/order_history_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'receipt_screen.dart';
import '../lang/translations.dart';

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
      setState(() { _offset = 0; _orders = []; _hasMore = true; });
    }
    try {
      final data = await ApiService.fetchOrders(limit: _limit, offset: _offset);
      if (mounted) {
        setState(() {
          _orders.addAll(data);
          _loading = false;
          _hasMore = data.length >= _limit;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading) return;
    setState(() => _offset += _limit);
    await _load();
  }

  String _fmt(dynamic value) {
    final d = (value as num?)?.toDouble() ?? 0;
    return 'SYP ${d.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('order_history')),
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
                      Icon(Icons.receipt_long, size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(t('no_orders_yet'), style: TextStyle(color: theme.colorScheme.outline)),
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
                        return const Center(child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ));
                      }
                      final order = _orders[i];
                      final date = DateTime.tryParse(order['created_at']?.toString() ?? '');
                      final dateStr = date != null
                          ? DateFormat('yyyy-MM-dd HH:mm').format(date)
                          : '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: const Icon(Icons.receipt),
                          ),
                          title: Text('${t('receipt')} #${order['receipt_number'] ?? order['id']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(dateStr, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              if (order['customer_name'] != null)
                                Text(order['customer_name'].toString(), style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          trailing: Text(
                            _fmt(order['total']),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReceiptScreen(orderId: order['id'] as int),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
