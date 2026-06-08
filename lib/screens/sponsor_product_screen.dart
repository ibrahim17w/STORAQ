import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lang/translations.dart';
import '../services/sponsored_products_service.dart';
import '../widgets/payment/geo_payment_price.dart';
import '../services/currency_service.dart';
import '../providers/viewer_location_provider.dart';
import '../utils/json_parsers.dart';
import '../utils/payment_support_chat.dart';

class SponsorProductScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> product;

  const SponsorProductScreen({super.key, required this.product});

  @override
  ConsumerState<SponsorProductScreen> createState() => _SponsorProductScreenState();
}

class _SponsorProductScreenState extends ConsumerState<SponsorProductScreen> {
  Map<String, dynamic>? _pricingData;
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _paymentRates;
  Map<String, dynamic>? _sponsorshipStatus;
  bool _loading = true;
  bool _statusLoading = true;
  bool _quoting = false;
  bool _requesting = false;
  String? _error;

  String _scopeType = 'city';
  int _durationDays = 7;
  int _radiusKm = 10;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SponsoredProductsService.getPricing();
      if (mounted) {
        setState(() {
          _pricingData = data;
          _paymentRates = data['payment_rates'] as Map<String, dynamic>?;
        });
        await _loadSponsorshipStatus();
        await _refreshQuote();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _productId => widget.product['id'] as int;

  Future<void> _loadSponsorshipStatus() async {
    if (mounted) setState(() => _statusLoading = true);
    try {
      final data = await SponsoredProductsService.getMyCampaigns();
      final campaigns = (data['campaigns'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final pending = (data['pending_payments'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      final activeForProduct = campaigns.where((c) {
        final pid = c['product_id'];
        if (pid != _productId) return false;
        if ((c['status']?.toString() ?? '') != 'active') return false;
        final expiresAt =
            DateTime.tryParse(c['expires_at']?.toString() ?? '');
        return expiresAt != null && expiresAt.isAfter(DateTime.now());
      }).toList();
      final pendingForProduct = pending.where((p) {
        final pid = p['product_id'];
        return pid == _productId;
      }).toList();

      activeForProduct.sort(
        (a, b) => (b['expires_at']?.toString() ?? '')
            .compareTo(a['expires_at']?.toString() ?? ''),
      );
      pendingForProduct.sort(
        (a, b) => (b['created_at']?.toString() ?? '')
            .compareTo(a['created_at']?.toString() ?? ''),
      );

      if (!mounted) return;
      setState(() {
        _sponsorshipStatus = {
          'active': activeForProduct.isNotEmpty ? activeForProduct.first : null,
          'pending': pendingForProduct.isNotEmpty ? pendingForProduct.first : null,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sponsorshipStatus = null;
      });
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  Future<void> _refreshQuote() async {
    setState(() => _quoting = true);
    try {
      final quote = await SponsoredProductsService.getQuote(
        productId: _productId,
        scopeType: _scopeType,
        durationDays: _durationDays,
        radiusKm: _scopeType == 'radius' ? _radiusKm : null,
      );
      if (mounted) {
        setState(() {
          _quote = quote;
          _paymentRates ??= quote['payment_rates'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _quote = null);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _requestPayment() async {
    setState(() => _requesting = true);
    try {
      final result = await SponsoredProductsService.requestSponsorship(
        productId: _productId,
        scopeType: _scopeType,
        durationDays: _durationDays,
        radiusKm: _scopeType == 'radius' ? _radiusKm : null,
      );
      if (mounted) {
        final payment = result['payment'] as Map<String, dynamic>? ?? {};
        setState(() {
          _sponsorshipStatus = {
            'active': _sponsorshipStatus?['active'],
            'pending': payment,
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('sponsorship_pending')),
            backgroundColor: Colors.orange.shade700,
          ),
        );
        _showPaymentDialog(result);
      }
      await _loadSponsorshipStatus();
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

  void _showPaymentDialog(Map<String, dynamic> result) {
    final payment = result['payment'] as Map<String, dynamic>? ?? {};
    final quote = result['quote'] as Map<String, dynamic>? ?? _quote;
    final ref = payment['reference_code']?.toString() ?? '';
    final usd = quote?['amount_usd'] is num
        ? (quote!['amount_usd'] as num).toDouble()
        : double.tryParse(quote?['amount_usd']?.toString() ?? '');
    final originalUsd = quote?['original_amount_usd'] is num
        ? (quote!['original_amount_usd'] as num).toDouble()
        : null;
    final hasDiscount = quote?['discount_usd'] is num &&
        (quote!['discount_usd'] as num) > 0;
    final prices = quote?['payment_prices'] as Map<String, dynamic>?;
    final originalPrices =
        quote?['original_payment_prices'] as Map<String, dynamic>?;
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
                originalUsdAmount: hasDiscount ? originalUsd : null,
                paymentPrices: prices,
                originalPaymentPrices: originalPrices,
                paymentRates: _paymentRates,
                label: t('amount_due') ?? 'Amount due',
              ),
              const SizedBox(height: 12),
            ],
            Text(
              t('sponsor_payment_instructions') ??
                  'Pay the sponsorship fee to an authorized agent with this reference:',
            ),
            const SizedBox(height: 12),
            SelectableText(
              ref,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              t('sponsor_verify_note') ??
                  'Once verified in the admin panel, your product appears in the Sponsored section for the selected area and duration.',
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
                paymentType: t('sponsor_product') ?? 'Product Sponsorship',
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

  String _scopeLabel(String scope) {
    switch (scope) {
      case 'radius':
        return t('sponsor_scope_radius') ?? 'Nearby radius';
      case 'village':
        return t('sponsor_scope_village') ?? 'Village';
      case 'city':
        return t('sponsor_scope_city') ?? 'City';
      case 'country':
        return t('sponsor_scope_country') ?? 'Country';
      case 'world':
        return t('sponsor_scope_world') ?? 'Worldwide';
      default:
        return scope;
    }
  }

  String _scopeDescription(String scope) {
    switch (scope) {
      case 'radius':
        return t('sponsor_scope_radius_desc') ?? 'Show to shoppers within your chosen radius';
      case 'village':
        return t('sponsor_scope_village_desc') ?? 'Show to shoppers in your village';
      case 'city':
        return t('sponsor_scope_city_desc') ?? 'Show to shoppers in your city';
      case 'country':
        return t('sponsor_scope_country_desc') ?? 'Show to shoppers in your country';
      case 'world':
        return t('sponsor_scope_world_desc') ?? 'Show to all shoppers worldwide';
      default:
        return '';
    }
  }

  Widget _buildSponsorshipStatusCard(ThemeData theme) {
    if (_statusLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final active = _sponsorshipStatus?['active'] as Map<String, dynamic>?;
    final pending = _sponsorshipStatus?['pending'] as Map<String, dynamic>?;
    if (active == null && pending == null) return const SizedBox.shrink();

    if (active != null) {
      final scope = active['scope_type']?.toString() ?? '';
      final expires = active['expires_at']?.toString() ?? '';
      return Card(
        color: Colors.green.withValues(alpha: 0.08),
        child: ListTile(
          leading: const Icon(Icons.verified_rounded, color: Colors.green),
          title: Text(t('sponsorship_approved')),
          subtitle: Text(
            '${t('sponsored_scope')}: ${_scopeLabel(scope)}'
            '${expires.isNotEmpty ? ' • ${t('expires')}: ${expires.substring(0, expires.length >= 10 ? 10 : expires.length)}' : ''}',
          ),
        ),
      );
    }

    final scope = pending?['scope_type']?.toString() ?? '';
    final refCode = pending?['reference_code']?.toString() ?? '';
    return Card(
      color: Colors.amber.withValues(alpha: 0.12),
      child: ListTile(
        leading: Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade800),
        title: Text(t('sponsorship_pending')),
        subtitle: Text(
          '${t('sponsored_scope')}: ${_scopeLabel(scope)}'
          '${refCode.isNotEmpty ? ' • ${t('reference_code')}: $refCode' : ''}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productName = widget.product['name']?.toString() ?? '';
    final pricing = (_pricingData?['pricing'] as List<dynamic>?) ?? [];
    final amount = _quote?['amount_usd'];
    final originalAmount = _quote?['original_amount_usd'];
    final hasDiscount = _quote?['discount_usd'] is num &&
        (_quote!['discount_usd'] as num) > 0;
    final hasActive = _sponsorshipStatus?['active'] != null;
    final hasPending = _sponsorshipStatus?['pending'] != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('sponsor_product') ?? 'Sponsor Product'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t('refresh') ?? 'Refresh',
            onPressed: _loading
                ? null
                : () async {
                    await _loadSponsorshipStatus();
                    await _refreshQuote();
                  },
          ),
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
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadPricing, child: Text(t('retry') ?? 'Retry')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        title: Text(productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          t('sponsor_product_desc') ??
                              'Boost visibility in the home screen Sponsored section',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSponsorshipStatusCard(theme),
                    const SizedBox(height: 16),
                    Text(
                      t('sponsor_audience') ?? 'Who should see this?',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...pricing.map((p) {
                      final scope = p['scope_type']?.toString() ?? '';
                      final selected = _scopeType == scope;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected ? theme.colorScheme.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: RadioListTile<String>(
                          value: scope,
                          groupValue: _scopeType,
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() => _scopeType = v);
                            await _refreshQuote();
                          },
                          title: Text(_scopeLabel(scope)),
                          subtitle: Consumer(
                            builder: (context, ref, _) {
                              final currency =
                                  ref.watch(viewerLocationProvider).paymentCurrency;
                              final dailyUsd =
                                  parseJsonDouble(p['price_usd_per_day']);
                              final dailyPrices =
                                  p['payment_prices_daily'] as Map<String, dynamic>?;
                              final parts = <String>[_scopeDescription(scope)];
                              if (dailyPrices != null && dailyPrices[currency] != null) {
                                parts.add(
                                  '${CurrencyService.formatPrice(dailyPrices[currency], currency)}/${t('day') ?? 'day'}',
                                );
                              } else if (dailyUsd != null) {
                                parts.add(
                                  '${CurrencyService.formatPrice(dailyUsd, 'USD')}/${t('day') ?? 'day'}',
                                );
                              }
                              return Text(
                                parts.join(' · '),
                                style: const TextStyle(fontSize: 12),
                              );
                            },
                          ),
                        ),
                      );
                    }),
                    if (_scopeType == 'radius') ...[
                      const SizedBox(height: 8),
                      Text(t('sponsor_radius') ?? 'Radius (km)', style: theme.textTheme.titleSmall),
                      Slider(
                        value: _radiusKm.toDouble(),
                        min: 5,
                        max: 50,
                        divisions: 9,
                        label: '$_radiusKm km',
                        onChanged: (v) => setState(() => _radiusKm = v.round()),
                        onChangeEnd: (_) => _refreshQuote(),
                      ),
                      Center(child: Text('$_radiusKm km')),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      t('sponsor_duration') ?? 'Duration',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [3, 7, 14, 30].map((days) {
                        final selected = _durationDays == days;
                        return ChoiceChip(
                          label: Text('$days ${t('days') ?? 'days'}'),
                          selected: selected,
                          onSelected: (_) async {
                            setState(() => _durationDays = days);
                            await _refreshQuote();
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('total_cost') ?? 'Total cost',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            if (_quoting)
                              const SizedBox(
                                height: 28,
                                width: 28,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              GeoPaymentPrice(
                                usdAmount: amount is num
                                    ? amount.toDouble()
                                    : double.tryParse('$amount'),
                                originalUsdAmount: hasDiscount && originalAmount is num
                                    ? originalAmount.toDouble()
                                    : null,
                                paymentPrices:
                                    _quote?['payment_prices'] as Map<String, dynamic>?,
                                originalPaymentPrices:
                                    _quote?['original_payment_prices'] as Map<String, dynamic>?,
                                paymentRates: _paymentRates,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              t('sponsor_affordable_note') ??
                                  'Affordable daily rates — pay only for the area and time you need.',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: (_requesting ||
                              _quoting ||
                              amount == null ||
                              hasActive ||
                              hasPending)
                          ? null
                          : _requestPayment,
                      icon: _requesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              hasActive
                                  ? Icons.verified_rounded
                                  : hasPending
                                      ? Icons.hourglass_top_rounded
                                      : Icons.campaign_outlined,
                            ),
                      label: Text(
                        hasActive
                            ? t('sponsorship_approved')
                            : hasPending
                                ? t('sponsorship_pending')
                                : (t('request_sponsorship') ?? 'Request Sponsorship'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
