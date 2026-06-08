import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../lang/translations.dart';
import '../services/subscription_service.dart';
import '../utils/payment_price_helper.dart';
import '../widgets/payment/geo_payment_price.dart';
import '../utils/payment_support_chat.dart';

class SubscriptionUpgradeScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialStatus;
  const SubscriptionUpgradeScreen({super.key, this.initialStatus});

  @override
  ConsumerState<SubscriptionUpgradeScreen> createState() => _SubscriptionUpgradeScreenState();
}

class _SubscriptionUpgradeScreenState extends ConsumerState<SubscriptionUpgradeScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;
  bool _requesting = false;
  Map<String, dynamic>? _lastPayment;
  final _promoCtrl = TextEditingController();
  bool _redeemingPromo = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await SubscriptionService.getStatus();
      var tiers = status['tiers'] as List<dynamic>? ?? [];
      if (tiers.isEmpty) {
        try {
          tiers = await SubscriptionService.getTiers();
          status['tiers'] = tiers;
        } catch (_) {}
      }
      if (mounted) setState(() => _status = status);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _currentTierSlots() {
    final fromStatus = _status?['current_tier_slots'];
    if (fromStatus is int) return fromStatus;
    if (fromStatus is num) return fromStatus.toInt();
    final tier = _status?['tier'] as Map<String, dynamic>?;
    final slots = tier?['online_slots'];
    if (slots is int) return slots;
    if (slots is num) return slots.toInt();
    return 5;
  }

  bool _hasActiveSubscription() => _status?['is_subscribed'] == true;

  bool _hasPendingPayment() => _status?['pending_payment'] != null;

  bool _canSelectTier(Map<String, dynamic> tier) {
    if (_hasPendingPayment()) return false;
    final slots = tier['online_slots'];
    final tierSlots = slots is int
        ? slots
        : slots is num
            ? slots.toInt()
            : int.tryParse(slots?.toString() ?? '') ?? 0;
    if (!_hasActiveSubscription()) return true;
    return tierSlots > _currentTierSlots();
  }

  String? _tierDisabledReason(Map<String, dynamic> tier) {
    if (_hasPendingPayment()) {
      return t('subscription_pending_payment_note') ??
          'You already have a pending payment. Wait until it is verified.';
    }
    if (!_hasActiveSubscription()) return null;
    final slots = tier['online_slots'];
    final tierSlots = slots is int
        ? slots
        : slots is num
            ? slots.toInt()
            : int.tryParse(slots?.toString() ?? '') ?? 0;
    if (tierSlots > _currentTierSlots()) return null;
    if (tierSlots == _currentTierSlots()) {
      return t('subscription_same_tier_note') ??
          'Your current plan is still active. Renew after it expires.';
    }
    return t('subscription_downgrade_note') ??
        'Downgrading is not allowed while your current plan is active.';
  }

  Future<void> _requestTier(Map<String, dynamic> tier, String track) async {
    if (!_canSelectTier(tier)) {
      final reason = _tierDisabledReason(tier);
      if (reason != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason)),
        );
      }
      return;
    }
    setState(() => _requesting = true);
    try {
      final result = await SubscriptionService.requestSubscription(
        tierId: tier['id'] as int,
        paymentTrack: track,
      );
      if (mounted) {
        setState(() => _lastPayment = result);
        _showSyriaPaymentDialog(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _redeemPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _redeemingPromo = true);
    try {
      final result = await SubscriptionService.redeemPromo(code);
      if (mounted) {
        _promoCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? t('done')),
            backgroundColor: Colors.green,
          ),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _redeemingPromo = false);
    }
  }

  void _showSyriaPaymentDialog(Map<String, dynamic> result) {
    final payment = result['payment'] as Map<String, dynamic>? ?? {};
    final tier = result['tier'] as Map<String, dynamic>? ?? {};
    final promoPricing = result['promo_pricing'] as Map<String, dynamic>?;
    final ref = payment['reference_code']?.toString() ?? '';
    final usd = payment['amount_usd'] is num
        ? (payment['amount_usd'] as num).toDouble()
        : PaymentPriceHelper.tierUsdPrice(tier) ??
            (payment['amount_usd'] is num
                ? (payment['amount_usd'] as num).toDouble()
                : double.tryParse(payment['amount_usd']?.toString() ?? ''));
    final originalUsd = promoPricing?['original_amount_usd'] is num
        ? (promoPricing!['original_amount_usd'] as num).toDouble()
        : PaymentPriceHelper.tierUsdPrice(tier);
    final paymentRates = _status?['payment_rates'] as Map<String, dynamic>?;
    final prices = promoPricing?['payment_prices'] as Map<String, dynamic>? ??
        PaymentPriceHelper.paymentPricesForTier(tier);
    final originalPrices =
        promoPricing?['original_payment_prices'] as Map<String, dynamic>?;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('pay_via_agent') ?? 'Pay via Agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (usd != null) ...[
              GeoPaymentPrice(
                usdAmount: usd,
                originalUsdAmount: originalUsd,
                paymentPrices: prices.isNotEmpty ? prices : null,
                originalPaymentPrices: originalPrices,
                paymentRates: paymentRates,
                label: t('amount_due') ?? 'Amount due',
              ),
              const SizedBox(height: 12),
            ],
            Text(t('syria_payment_instructions') ??
                'Pay cash to an authorized agent and provide this reference code:'),
            const SizedBox(height: 12),
            SelectableText(
              ref,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              t('agent_verify_note') ??
                  'The agent will verify your payment in the admin panel. Your subscription activates for 30 days once verified.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ref));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('copied') ?? 'Copied')),
              );
            },
            child: Text(t('copy_code') ?? 'Copy Code'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final nav = Navigator.of(context);
              nav.pop();
              await openPaymentConfirmationChat(
                context,
                referenceCode: ref,
                paymentType: t('subscription') ?? 'Subscription',
                amountText: usd != null ? '\$${usd.toStringAsFixed(2)}' : null,
              );
            },
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: Text(t('start_payment_chat') ?? 'Start live chat'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('done') ?? 'Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiers = (_status?['tiers'] as List<dynamic>?) ?? [];
    final paymentRates = _status?['payment_rates'] as Map<String, dynamic>?;
    final activePromo = _status?['active_promo'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('upgrade_plan') ?? 'Upgrade Plan'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: Text(t('retry') ?? 'Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_status?['tier'] != null) ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.verified, color: Colors.green),
                            title: Text(
                              '${(_status!['tier'] as Map)['name']} ${t('plan_active') ?? 'Plan Active'}',
                            ),
                            subtitle: Text(
                              '${t('expires') ?? 'Expires'}: ${(_status!['tier'] as Map)['expires_at']}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              t('subscription_upgrade_only_note') ??
                                  'While your plan is active you can only upgrade to a higher plan. Renew or switch plans after it expires.',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_status?['pending_payment'] != null) ...[
                        Card(
                          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45),
                          child: ListTile(
                            leading: Icon(
                              Icons.hourglass_top_rounded,
                              color: theme.colorScheme.tertiary,
                            ),
                            title: Text(
                              t('subscription_pending_payment_title') ??
                                  'Pending subscription payment',
                            ),
                            subtitle: Text(
                              '${(_status!['pending_payment'] as Map)['tier_name']} · ${(_status!['pending_payment'] as Map)['reference_code']}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        t('choose_plan') ?? 'Choose a plan to list more products on the marketplace',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('free_tier_note') ??
                            'Every store gets 5 free online slots. Upgrade for more marketplace visibility.',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('payment_rates_syria_note') ??
                            'SYP uses live Syria market rates (sp-today / syriato).',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (activePromo != null) ...[
                        Card(
                          color: Colors.green.withValues(alpha: 0.1),
                          child: ListTile(
                            leading: const Icon(Icons.local_offer_outlined, color: Colors.green),
                            title: Text(t('promo_active') ?? 'Promo active'),
                            subtitle: Text(
                              '${activePromo['code']} · ${activePromo['discount_percent'] != null && (activePromo['discount_percent'] as num) > 0 ? '${activePromo['discount_percent']}% off' : ''}${activePromo['discount_fixed'] != null && (activePromo['discount_fixed'] as num) > 0 ? '\$${(activePromo['discount_fixed'] as num).toStringAsFixed(2)} off' : ''} ${t('platform_fees') ?? 'platform fees'}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (tiers.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              t('no_plans_available') ??
                                  'No upgrade plans available right now. Restart the backend server and try again.',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ...tiers.map((tier) {
                        final tMap = tier as Map<String, dynamic>;
                        final slots = tMap['online_slots'] ?? 0;
                        final originalUsd = PaymentPriceHelper.tierUsdPrice(tMap);
                        final discountedUsd = tMap['discounted_price_usd'];
                        final usdPrice = discountedUsd is num
                            ? discountedUsd.toDouble()
                            : originalUsd;
                        final prices = discountedUsd != null
                            ? (tMap['discounted_payment_prices'] as Map<String, dynamic>? ??
                                PaymentPriceHelper.paymentPricesForTier(tMap))
                            : PaymentPriceHelper.paymentPricesForTier(tMap);
                        final originalPrices = discountedUsd != null
                            ? PaymentPriceHelper.paymentPricesForTier(tMap)
                            : null;
                        final canSelect = _canSelectTier(tMap);
                        final disabledReason = _tierDisabledReason(tMap);
                        final isCurrentPlan = _hasActiveSubscription() &&
                            (tMap['online_slots'] is num
                                ? (tMap['online_slots'] as num).toInt()
                                : int.tryParse(tMap['online_slots']?.toString() ?? '')) ==
                                _currentTierSlots();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tMap['name']?.toString() ?? '',
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (isCurrentPlan)
                                      Chip(
                                        label: Text(
                                          t('current_plan') ?? 'Current plan',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                GeoPaymentPrice(
                                  usdAmount: usdPrice,
                                  originalUsdAmount: discountedUsd != null ? originalUsd : null,
                                  paymentPrices: prices.isNotEmpty ? prices : null,
                                  originalPaymentPrices: originalPrices,
                                  paymentRates: paymentRates,
                                  label: '${t('per_month') ?? 'Per month'}:',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$slots ${t('online_products') ?? 'online products'}',
                                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 12),
                                if (!canSelect && disabledReason != null) ...[
                                  Text(
                                    disabledReason,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _requesting || !canSelect
                                        ? null
                                        : () => _requestTier(tMap, 'syria_agent'),
                                    icon: Icon(
                                      canSelect
                                          ? Icons.payments_outlined
                                          : Icons.lock_outline,
                                      size: 18,
                                    ),
                                    label: Text(
                                      canSelect
                                          ? (t('pay_via_agent') ?? 'Pay via Agent')
                                          : (t('not_available') ?? 'Not available'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text(
                        t('have_promo_code') ?? 'Have a promo code?',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _promoCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: t('enter_promo_code') ?? 'Enter promo code',
                                prefixIcon: const Icon(Icons.card_giftcard),
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: _redeemingPromo ? null : _redeemPromo,
                              child: _redeemingPromo
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(t('redeem') ?? 'Redeem'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }
}
