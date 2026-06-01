// lib/screens/profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../providers/locale_provider.dart';
import '../lang/translations.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/guest_login_sheet.dart';
import 'my_store_screen.dart';
import 'main_nav_screen.dart';
import 'checkout_screen.dart';
import 'order_history_screen.dart';
import 'store_invitations_screen.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import '../services/offline_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await AuthService.logout();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('delete_account') ?? 'Delete Account'),
        content: Text(t('delete_account_confirm') ?? 'Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t('confirm') ?? 'Confirm',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AuthService.deleteAccount();
      await AuthService.logout();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('account_deleted') ?? 'Account deleted'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainNavScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ApiService.isLoggedIn(),
      builder: (context, authSnap) {
        final isLoggedIn = authSnap.data ?? false;

        if (!isLoggedIn) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t('login_to_continue') ?? 'Login to continue',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('guest_restricted') ??
                            'Some features are restricted for guests',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => showGuestSheet(context),
                        child: Text(t('login') ?? 'Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: _safeGetCurrentUser(),
          builder: (context, userSnap) {
            // Show skeleton while loading
            if (userSnap.connectionState == ConnectionState.waiting &&
                !userSnap.hasData) {
              return _ProfileSkeleton();
            }

            final user = userSnap.data;
            final hasError = userSnap.hasError;

            // FIXED: Check store context instead of role — works for both owner and worker
            final hasStoreAccess = user?['store'] != null;
            final isOwner = user?['store']?['role'] == 'owner';

            return FutureBuilder<List<dynamic>>(
              future: _safeFetchInvitations(),
              builder: (context, inviteSnap) {
                final invitations = inviteSnap.data ?? [];
                final hasPendingInvites = invitations.isNotEmpty;

                return Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        expandedHeight: 120,
                        flexibleSpace: FlexibleSpaceBar(
                          title: Text(t('profile') ?? 'My Profile'),
                        ),
                        actions: const [ThemeToggle(), SizedBox(width: 8)],
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // ── Avatar & Name ──
                              if (hasError || user == null)
                                _OfflineProfileHeader()
                              else ...[
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  child: Text(
                                    (user['full_name'] ?? '?')
                                        .toString()
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 32,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  user['full_name'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  user['email'] ?? '',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                              const SizedBox(height: 24),

                              // ── Offline warning banner ──
                              if (hasError)
                                _OfflineBanner(
                                  onRetry: () {
                                    // Trigger rebuild
                                    (context as Element).markNeedsBuild();
                                  },
                                ),

                              // ── Pending Invitations Banner ──
                              if (hasPendingInvites)
                                _InvitationsBanner(
                                  count: invitations.length,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const StoreInvitationsScreen(),
                                    ),
                                  ),
                                ),

                              // ── Store Tools (Owner or Accepted Worker) ──
                              if (hasStoreAccess) ...[
                                _sectionHeader(
                                  context,
                                  t('store_tools') ?? 'Store Tools',
                                ),
                                ListTile(
                                  leading: const Icon(Icons.store),
                                  title: Text(t('my_store') ?? 'My Store'),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const MyStoreScreen(),
                                    ),
                                  ),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.point_of_sale),
                                  title: Text(t('checkout') ?? 'Checkout'),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CheckoutScreen(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              // ── General ──
                              _sectionHeader(
                                context,
                                t('general') ?? 'General',
                              ),
                              ListTile(
                                leading: const Icon(Icons.receipt_long),
                                title: Text(
                                  t('order_history') ?? 'Order History',
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const OrderHistoryScreen(),
                                  ),
                                ),
                              ),
                              ListTile(
                                leading: const Icon(Icons.language),
                                title: Text(t('language') ?? 'Language'),
                                trailing: Text(
                                  localeNotifier.value.languageCode
                                      .toUpperCase(),
                                ),
                                onTap: () => showLanguagePicker(context),
                              ),
                              const SizedBox(height: 8),

                              // ── Account ──
                              _sectionHeader(
                                context,
                                t('account') ?? 'Account',
                                isDanger: true,
                              ),
                              ListTile(
                                leading: const Icon(
                                  Icons.logout,
                                  color: Colors.red,
                                ),
                                title: Text(
                                  t('logout') ?? 'Logout',
                                  style: const TextStyle(color: Colors.red),
                                ),
                                onTap: () => _logout(context),
                              ),
                              ListTile(
                                leading: const Icon(
                                  Icons.delete_forever,
                                  color: Colors.red,
                                ),
                                title: Text(
                                  t('delete_account') ?? 'Delete Account',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: () => _confirmDeleteAccount(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Safely get current user with fallback to cached data.
  /// NEVER rethrows — always returns a Map so the profile UI renders offline.
  Future<Map<String, dynamic>> _safeGetCurrentUser() async {
    try {
      final user = await AuthService.getCurrentUser();
      // Cache successful response for next offline use
      await OfflineService.cacheUser(user);
      return user;
    } catch (e) {
      // Try OfflineService cache
      try {
        final cached = await OfflineService.getCachedUser();
        if (cached != null) {
          return cached;
        }
      } catch (_) {}
      // Try SharedPreferences as last resort
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('cached_user');
        if (raw != null) {
          return jsonDecode(raw) as Map<String, dynamic>;
        }
      } catch (_) {}
      // Try token payload as absolute last resort
      try {
        final payload = await ApiService.decodeToken();
        if (payload != null) {
          return {
            'id': payload['userId'],
            'full_name': payload['full_name'] ?? payload['name'] ?? 'User',
            'email': payload['email'] ?? '',
            'role': payload['role'] ?? 'user',
            'store': payload['store'],
          };
        }
      } catch (_) {}
      // Absolute fallback — return minimal map so UI doesn't crash
      return {
        'full_name': t('offline_user') ?? 'Offline User',
        'email': '',
        'role': 'user',
        'store': null,
      };
    }
  }

  /// Safely fetch invitations with empty fallback
  Future<List<dynamic>> _safeFetchInvitations() async {
    try {
      return await StoreService.fetchMyInvitations();
    } catch (e) {
      return [];
    }
  }

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    bool isDanger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDanger
                ? Colors.red.shade400
                : Theme.of(context).colorScheme.primary,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

// ── Offline Profile Header (skeleton + offline icon) ──
class _OfflineProfileHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_off_outlined,
            size: 36,
            color: Colors.grey.shade400,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 140,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 180,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

// ── Offline Banner ──
class _OfflineBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _OfflineBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('you_are_offline') ?? 'You are offline',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t('offline_profile_desc') ??
                      'Some features are unavailable. Your data will refresh when you reconnect.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.orange.shade700, size: 20),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ── Profile Skeleton Loader (YouTube/Facebook style) ──
class _ProfileSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade800
        : Colors.grey.shade200;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(t('profile') ?? 'My Profile'),
            ),
            actions: const [ThemeToggle(), SizedBox(width: 8)],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Avatar skeleton
                  _SkeletonCircle(size: 80, baseColor: baseColor),
                  const SizedBox(height: 12),
                  // Name skeleton
                  _SkeletonBox(width: 140, height: 18, baseColor: baseColor),
                  const SizedBox(height: 8),
                  // Email skeleton
                  _SkeletonBox(width: 180, height: 14, baseColor: baseColor),
                  const SizedBox(height: 24),

                  // Section header skeleton
                  _SkeletonBox(width: 100, height: 12, baseColor: baseColor),
                  const SizedBox(height: 8),
                  // List tile skeletons
                  _SkeletonListTile(baseColor: baseColor),
                  const SizedBox(height: 8),
                  _SkeletonListTile(baseColor: baseColor),
                  const SizedBox(height: 8),
                  _SkeletonListTile(baseColor: baseColor),
                  const SizedBox(height: 24),

                  _SkeletonBox(width: 80, height: 12, baseColor: baseColor),
                  const SizedBox(height: 8),
                  _SkeletonListTile(baseColor: baseColor),
                  const SizedBox(height: 8),
                  _SkeletonListTile(baseColor: baseColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final Color baseColor;

  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  final double size;
  final Color baseColor;

  const _SkeletonCircle({required this.size, required this.baseColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: baseColor, shape: BoxShape.circle),
    );
  }
}

class _SkeletonListTile extends StatelessWidget {
  final Color baseColor;

  const _SkeletonListTile({required this.baseColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: baseColor.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: baseColor.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: baseColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending Invitations Banner ──
class _InvitationsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _InvitationsBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('pending_invitations') ?? 'Store Invitations',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t('tap_to_view_invitations') ??
                            'Tap to view and respond',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
