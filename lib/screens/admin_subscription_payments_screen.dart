import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../lang/translations.dart';
import '../services/subscription_service.dart';

class AdminSubscriptionPaymentsScreen extends ConsumerStatefulWidget {
  const AdminSubscriptionPaymentsScreen({super.key});

  @override
  ConsumerState<AdminSubscriptionPaymentsScreen> createState() =>
      _AdminSubscriptionPaymentsScreenState();
}

class _AdminSubscriptionPaymentsScreenState
    extends ConsumerState<AdminSubscriptionPaymentsScreen> {
  List<dynamic> _payments = [];
  bool _loading = true;
  String? _error;
  final Set<int> _verifying = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payments = await SubscriptionService.getPendingPayments();
      if (mounted) setState(() => _payments = payments);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify(int paymentId) async {
    setState(() => _verifying.add(paymentId));
    try {
      await SubscriptionService.verifyPayment(paymentId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('payment_verified') ?? 'Payment verified'),
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
      if (mounted) setState(() => _verifying.remove(paymentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('subscription_payments') ?? 'Subscription Payments'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      ElevatedButton(onPressed: _load, child: Text(t('retry') ?? 'Retry')),
                    ],
                  ),
                )
              : _payments.isEmpty
                  ? Center(child: Text(t('no_pending_payments') ?? 'No pending payments'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _payments.length,
                        itemBuilder: (context, index) {
                          final p = _payments[index] as Map<String, dynamic>;
                          final id = p['id'] as int;
                          final busy = _verifying.contains(id);
                          final ref = p['reference_code']?.toString() ?? '';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p['store_name']?.toString() ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${p['owner_name']} • ${p['owner_email']}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  ),
                                  const Divider(),
                                  Text('${t('tier') ?? 'Tier'}: ${p['tier_name']} (${p['online_slots']} slots)'),
                                  Text('${t('amount') ?? 'Amount'}: \$${p['amount_usd']}'),
                                  if (ref.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${t('reference_code') ?? 'Reference'}: $ref',
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 18),
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: ref));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text(t('copied') ?? 'Copied')),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: busy ? null : () => _verify(id),
                                      child: busy
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Text(t('verify_payment') ?? 'Verify Payment'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
