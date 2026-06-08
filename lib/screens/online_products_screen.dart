import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lang/translations.dart';
import '../services/subscription_service.dart';
import '../widgets/cached_image.dart';
import 'subscription_upgrade_screen.dart';
import 'sponsor_product_screen.dart';

class OnlineProductsScreen extends ConsumerStatefulWidget {
  const OnlineProductsScreen({super.key});

  @override
  ConsumerState<OnlineProductsScreen> createState() => _OnlineProductsScreenState();
}

class _OnlineProductsScreenState extends ConsumerState<OnlineProductsScreen> {
  List<dynamic> _products = [];
  int _onlineCount = 0;
  int _onlineLimit = 5;
  bool _loading = true;
  String? _error;
  final Set<int> _pending = {};

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
      final data = await SubscriptionService.getOnlineProducts();
      if (mounted) {
        setState(() {
          _products = data['products'] as List<dynamic>? ?? [];
          _onlineCount = data['online_count'] as int? ?? 0;
          _onlineLimit = data['online_limit'] as int? ?? 5;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleOnline(Map<String, dynamic> product, bool online) async {
    final id = product['id'] as int;
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    try {
      await SubscriptionService.setProductOnline(id, online);
      await _load();
    } on SubscriptionLimitException catch (e) {
      if (mounted) _showUpgradeDialog(e);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  void _showUpgradeDialog(SubscriptionLimitException e) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('online_limit_reached') ?? 'Online Limit Reached'),
        content: Text(
          '${t('online_limit_message') ?? 'You can only have'} ${e.onlineLimit} ${t('products_online') ?? 'products online'}. ${t('upgrade_to_add_more') ?? 'Upgrade to add more.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel') ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubscriptionUpgradeScreen(
                    initialStatus: {'online_count': e.onlineCount, 'online_limit': e.onlineLimit, 'tiers': e.tiers},
                  ),
                ),
              );
            },
            child: Text(t('upgrade') ?? 'Upgrade'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _onlineLimit > 0 ? (_onlineCount / _onlineLimit).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('manage_online_products') ?? 'Manage Online Products'),
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
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t('online') ?? 'Online'}: $_onlineCount / $_onlineLimit',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade300,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('offline_products_note') ??
                                'Offline products are saved in your store but hidden from the marketplace.',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: _products.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 80),
                                  Center(child: Text(t('no_products') ?? 'No products yet')),
                                ],
                              )
                            : ListView.builder(
                                itemCount: _products.length,
                                itemBuilder: (context, index) {
                                  final p = _products[index] as Map<String, dynamic>;
                                  final id = p['id'] as int;
                                  final isOnline = p['is_online'] == true;
                                  final isSponsored = p['is_sponsored'] == true;
                                  final hasPendingSponsorship =
                                      p['has_pending_sponsorship'] == true ||
                                      p['sponsorship_state'] == 'pending';
                                  final scope = p['sponsorship_scope']?.toString();
                                  final pendingScope =
                                      p['sponsorship_pending_scope']?.toString();
                                  final busy = _pending.contains(id);
                                  String _scopeLabel() {
                                    if (!isSponsored) return '';
                                    switch (scope) {
                                      case 'world':
                                        return t('worldwide') ?? 'Worldwide';
                                      case 'country':
                                        return p['sponsorship_target_country']?.toString() ?? (t('country') ?? 'Country');
                                      case 'city':
                                        return p['sponsorship_target_city']?.toString() ?? (t('city') ?? 'City');
                                      case 'village':
                                        return p['sponsorship_target_village']?.toString() ?? (t('village') ?? 'Village');
                                      case 'radius':
                                        final km = p['sponsorship_radius_km'];
                                        return km != null ? '${km}km' : (t('radius') ?? 'Radius');
                                      default:
                                        return scope ?? '';
                                    }
                                  }

                                  String _pendingScopeLabel() {
                                    switch (pendingScope) {
                                      case 'world':
                                        return t('worldwide') ?? 'Worldwide';
                                      case 'country':
                                        return p['sponsorship_pending_target_country']
                                                ?.toString() ??
                                            (t('country') ?? 'Country');
                                      case 'city':
                                        return p['sponsorship_pending_target_city']
                                                ?.toString() ??
                                            (t('city') ?? 'City');
                                      case 'village':
                                        return p['sponsorship_pending_target_village']
                                                ?.toString() ??
                                            (t('village') ?? 'Village');
                                      case 'radius':
                                        final km =
                                            p['sponsorship_pending_radius_km'];
                                        return km != null
                                            ? '${km}km'
                                            : (t('radius') ?? 'Radius');
                                      default:
                                        return pendingScope ?? '';
                                    }
                                  }
                                  return ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: p['image_url'] != null
                                            ? CachedAppImage(
                                                imageUrl: p['image_url'].toString(),
                                                fit: BoxFit.cover,
                                              )
                                            : Container(color: theme.colorScheme.surfaceContainerHighest),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Flexible(child: Text(p['name']?.toString() ?? '', overflow: TextOverflow.ellipsis)),
                                        if (isSponsored) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade700,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              t('sponsored') ?? 'SPONSORED',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (!isSponsored && hasPendingSponsorship) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade700,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              t('sponsorship_pending_short'),
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isOnline
                                              ? (t('listed_on_marketplace') ?? 'Listed on marketplace')
                                              : (t('store_only') ?? 'Store only'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isOnline ? Colors.green.shade700 : Colors.grey.shade600,
                                          ),
                                        ),
                                        if (isSponsored)
                                          Text(
                                            '${t('sponsored_scope') ?? 'Sponsored'}: ${_scopeLabel()}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.amber.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        if (!isSponsored &&
                                            hasPendingSponsorship)
                                          Text(
                                            '${t('sponsorship_pending')}: ${_pendingScopeLabel()}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: busy
                                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isOnline &&
                                                  !isSponsored &&
                                                  !hasPendingSponsorship)
                                                IconButton(
                                                  tooltip: t('sponsor_product') ?? 'Sponsor Product',
                                                  icon: const Icon(Icons.campaign_outlined),
                                                  onPressed: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => SponsorProductScreen(product: p),
                                                    ),
                                                  ).then((_) => _load()),
                                                ),
                                              if (isOnline && isSponsored)
                                                Icon(Icons.check_circle, color: Colors.amber.shade700, size: 22),
                                              if (isOnline &&
                                                  !isSponsored &&
                                                  hasPendingSponsorship)
                                                Icon(Icons.hourglass_top_rounded,
                                                    color: Colors.orange.shade700,
                                                    size: 22),
                                              Switch(
                                                value: isOnline,
                                                onChanged: (v) => _toggleOnline(p, v),
                                              ),
                                            ],
                                          ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
