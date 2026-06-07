// lib/screens/store_invitations_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import 'store_products_screen.dart';
import '../services/store_service.dart';

class StoreInvitationsScreen extends ConsumerStatefulWidget {
  const StoreInvitationsScreen({super.key});

  @override
  ConsumerState<StoreInvitationsScreen> createState() => _StoreInvitationsScreenState();
}

class _StoreInvitationsScreenState extends ConsumerState<StoreInvitationsScreen> {
  List<dynamic> _invitations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await StoreService.fetchMyInvitations();
      if (mounted) {
        setState(() {
          _invitations = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _acceptInvitation(int invitationId) async {
    setState(() => _loading = true);
    try {
      // acceptInvitation returns void - it auto-updates store context internally
      await StoreService.acceptInvitation(invitationId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('invitation_accepted') ?? 'Invitation accepted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadInvitations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _rejectInvitation(int invitationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('reject_invitation') ?? 'Reject Invitation'),
        content: Text(
          t('reject_invitation_confirm') ??
              'Are you sure you want to reject this invitation?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t('reject') ?? 'Reject',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await StoreService.rejectInvitation(invitationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('invitation_rejected') ?? 'Invitation rejected'),
          ),
        );
      }
      await _loadInvitations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _viewStoreProducts(int storeId, String storeName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StoreProductsScreen(storeId: storeId, storeName: storeName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('store_invitations') ?? 'Store Invitations'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
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
                    t('error_loading_invitations') ??
                        'Failed to load invitations',
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadInvitations,
                    child: Text(t('retry')),
                  ),
                ],
              ),
            )
          : _invitations.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('no_invitations') ?? 'No pending invitations',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadInvitations,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _invitations.length,
                itemBuilder: (context, index) {
                  final inv = _invitations[index];
                  final storeName =
                      inv['store_name']?.toString() ??
                      t('unknown_store') ??
                      t('unknown_store');
                  final storeCity = inv['store_city']?.toString() ?? '';
                  final storeImage = inv['store_image']?.toString();
                  final invitedBy = inv['invited_by_name']?.toString();
                  final canManage = inv['can_manage_inventory'] == true;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Store header — tap to view public store page
                        InkWell(
                          onTap: () =>
                              _viewStoreProducts(inv['store_id'], storeName),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    color: theme.colorScheme.primaryContainer,
                                    child:
                                        storeImage != null &&
                                            storeImage.isNotEmpty
                                        ? Image.network(
                                            storeImage,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                                  Icons.store,
                                                  size: 32,
                                                ),
                                          )
                                        : const Icon(Icons.store, size: 32),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        storeName,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      if (storeCity.isNotEmpty)
                                        Text(
                                          storeCity,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      if (invitedBy != null)
                                        Text(
                                          '${t('invited_by') ?? 'Invited by'}: $invitedBy',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      if (canManage)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.inventory_2,
                                                size: 14,
                                                color: Colors.green.shade600,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                t('inventory_access_offered') ??
                                                    'Inventory management access offered',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.green.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Divider(height: 1),

                        // Accept / Reject buttons
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _rejectInvitation(inv['id']),
                                  icon: const Icon(Icons.close, size: 18),
                                  label: Text(t('reject') ?? 'Reject'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _acceptInvitation(inv['id']),
                                  icon: const Icon(Icons.check, size: 18),
                                  label: Text(t('accept') ?? 'Accept'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
