// lib/screens/profile_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../providers/locale_provider.dart';
import '../providers/auth_provider.dart';
import '../lang/translations.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/guest_login_sheet.dart';
import 'my_store_screen.dart';
import 'main_nav_screen.dart';
import 'checkout_screen.dart';
import 'store_settings_screen.dart';
import 'order_history_screen.dart';
import 'store_invitations_screen.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import '../models/models.dart';
import 'admin_subscription_payments_screen.dart';
import '../services/offline_service.dart';
import '../widgets/cached_image.dart';
import 'chat_conversations_screen.dart';
import 'support_tickets_screen.dart';
import '../providers/cart_provider.dart';
import 'shopping_cart_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authProvider.notifier).logout();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
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
      await ref.read(authProvider.notifier).logout();
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
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isLoggedIn = auth.isAuthenticated && !auth.isGuest;

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

    return FutureBuilder<User>(
      future: _safeGetCurrentUser(),
      builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting &&
                !userSnap.hasData) {
              return _ProfileSkeleton();
            }

            final user = userSnap.data;
            final hasError = userSnap.hasError;

            final hasStoreAccess = user?.store != null;
            final isOwner = user?.store?['role'] == 'owner';
            final isAdmin = user?.role == 'admin';

            return FutureBuilder<List<dynamic>>(
              future: _safeFetchInvitations(),
              builder: (context, inviteSnap) {
                final invitations = inviteSnap.data ?? [];
                final hasPendingInvites = invitations.isNotEmpty;

                final theme = Theme.of(context);
                final pageBg = theme.brightness == Brightness.dark
                    ? const Color(0xFF121212)
                    : const Color(0xFFF5F5F7);

                return Scaffold(
                  backgroundColor: pageBg,
                  body: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        surfaceTintColor: Colors.transparent,
                        backgroundColor: pageBg,
                        title: Text(
                          t('profile') ?? 'My Profile',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.02,
                          ),
                        ),
                        actions: const [ThemeToggle(), SizedBox(width: 8)],
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: Column(
                            children: [
                              hasError || user == null
                                  ? _OfflineProfileHeader()
                                  : _ProfileAvatarHeader(
                                      user: user,
                                      onUpdated: () {
                                        (context as Element).markNeedsBuild();
                                      },
                                    ),
                              const SizedBox(height: 20),

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
                                _ProfileMenuCard(
                                  children: [
                                    _ProfileListTile(
                                      icon: Icons.storefront_outlined,
                                      title: t('my_store') ?? 'My Store',
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const MyStoreScreen(),
                                        ),
                                      ),
                                    ),
                                    _ProfileListTile(
                                      icon: Icons.point_of_sale_outlined,
                                      title: t('checkout') ?? 'Checkout',
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const CheckoutScreen(),
                                        ),
                                      ),
                                    ),
                                    if (isOwner)
                                      _ProfileListTile(
                                        icon: Icons.settings_outlined,
                                        title: t('store_settings') ?? 'Store Settings',
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const StoreSettingsScreen(),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],

                              if (isAdmin) ...[
                                _sectionHeader(
                                  context,
                                  t('admin') ?? 'Admin',
                                ),
                                _ProfileMenuCard(
                                  children: [
                                    _ProfileListTile(
                                      icon: Icons.payments_outlined,
                                      title: t('subscription_payments') ??
                                          'Subscription Payments',
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AdminSubscriptionPaymentsScreen(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],

                              // ── General ──
                              _sectionHeader(
                                context,
                                t('general') ?? 'General',
                              ),
                              _ProfileMenuCard(
                                children: [
                                  _ProfileListTile(
                                    icon: Icons.shopping_cart_outlined,
                                    title: t('cart') ?? 'Cart',
                                    subtitle: t('cart_saved_hint') ??
                                        'Products grouped by store — tap to visit',
                                    trailing: ref.watch(cartProvider).itemCount > 0
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: theme.colorScheme.primary
                                                    .withValues(alpha: 0.25),
                                              ),
                                            ),
                                            child: Text(
                                              '${ref.watch(cartProvider).itemCount}',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: theme.colorScheme.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          )
                                        : null,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const ShoppingCartScreen(),
                                      ),
                                    ),
                                  ),
                                  _ProfileListTile(
                                    icon: Icons.support_agent_outlined,
                                    title: t('help_support') ?? 'Help & Support',
                                    subtitle: t('support_ticket_hint_short') ??
                                        'Contact STORAQ support team',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const SupportTicketsScreen(),
                                      ),
                                    ),
                                  ),
                                  _ProfileListTile(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    title: t('store_messages') ?? 'Store Messages',
                                    subtitle: t('store_messages_hint') ??
                                        'Chat with shops you buy from',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ChatConversationsScreen(),
                                      ),
                                    ),
                                  ),
                                  _ProfileListTile(
                                    icon: Icons.receipt_long_outlined,
                                    title: t('order_history') ?? 'Order History',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const OrderHistoryScreen(),
                                      ),
                                    ),
                                  ),
                                  _ProfileListTile(
                                    icon: Icons.language_outlined,
                                    title: t('language') ?? 'Language',
                                    trailing: Text(
                                      localeNotifier.value.languageCode
                                          .toUpperCase(),
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    showChevron: false,
                                    onTap: () => showLanguagePicker(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // ── Account ──
                              _sectionHeader(
                                context,
                                t('account') ?? 'Account',
                                isDanger: true,
                              ),
                              _ProfileMenuCard(
                                isDanger: true,
                                children: [
                                  _ProfileListTile(
                                    icon: Icons.logout_rounded,
                                    title: t('logout') ?? 'Logout',
                                    isDanger: true,
                                    showChevron: false,
                                    onTap: () => _logout(context, ref),
                                  ),
                                  _ProfileListTile(
                                    icon: Icons.delete_outline_rounded,
                                    title: t('delete_account') ?? 'Delete Account',
                                    isDanger: true,
                                    showChevron: false,
                                    onTap: () => _confirmDeleteAccount(context, ref),
                                  ),
                                ],
                              ),
                              SizedBox(
                                height: MediaQuery.of(context).padding.bottom + 100,
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
  }

  /// Safely get current user with fallback to cached data.
  /// NEVER rethrows — always returns a Map so the profile UI renders offline.
  Future<User> _safeGetCurrentUser() async {
    try {
      final user = await AuthService.getCurrentUser();
      await OfflineService.cacheUser(user.toJson());
      return user;
    } catch (e) {
      try {
        final cached = await OfflineService.getCachedUser();
        if (cached != null) return User.fromJson(cached);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('cached_user');
        if (raw != null) {
          return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        }
      } catch (_) {}
      try {
        final payload = await ApiService.decodeToken();
        if (payload != null) {
          return User.fromJson({
            'id': payload['userId'],
            'full_name': payload['full_name'] ?? payload['name'] ?? 'User',
            'email': payload['email'] ?? '',
            'role': payload['role'] ?? 'user',
            'store': payload['store'],
          });
        }
      } catch (_) {}
      return User(
        fullName: t('offline_user') ?? 'Offline User',
        email: '',
        role: 'user',
      );
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: isDanger
                ? Colors.red.shade400
                : theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

class _ProfileListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool isDanger;
  final bool showChevron;

  const _ProfileListTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.isDanger = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = isDanger ? Colors.red.shade400 : theme.colorScheme.onSurface;
    final iconBg = isDanger
        ? Colors.red.withValues(alpha: 0.1)
        : theme.colorScheme.onSurface.withValues(alpha: 0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                trailing!,
                if (showChevron) const SizedBox(width: 6),
              ],
              if (showChevron)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuCard extends StatelessWidget {
  final List<Widget> children;
  final bool isDanger;

  const _ProfileMenuCard({
    required this.children,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: isDanger
            ? Colors.red.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.1 : 0.04,
              )
            : surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDanger
              ? Colors.red.withValues(alpha: 0.22)
              : theme.dividerColor.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.55 : 0.35,
                ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 66,
                endIndent: 16,
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
          ],
        ],
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

    final pageBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFF5F5F7);

    return Scaffold(
      backgroundColor: pageBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: pageBg,
            title: Text(t('profile') ?? 'My Profile'),
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

class _ProfileAvatarHeader extends StatefulWidget {
  final User user;
  final VoidCallback onUpdated;

  const _ProfileAvatarHeader({
    required this.user,
    required this.onUpdated,
  });

  @override
  State<_ProfileAvatarHeader> createState() => _ProfileAvatarHeaderState();
}

class _ProfileAvatarHeaderState extends State<_ProfileAvatarHeader> {
  bool _uploading = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.user.avatarUrl;
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final updated = await AuthService.uploadAvatar(File(picked.path));
      if (!mounted) return;
      setState(() {
        _avatarUrl = updated.avatarUrl;
        _uploading = false;
      });
      widget.onUpdated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('profile_photo_updated') ?? 'Profile photo updated'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = (widget.user.fullName ?? '?').isNotEmpty
        ? widget.user.fullName!.substring(0, 1).toUpperCase()
        : '?';

    final surface = theme.brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.55 : 0.35,
          ),
        ),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 46,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                      ? ClipOval(
                          child: CachedAppImage(
                            imageUrl: _avatarUrl,
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                            memCacheWidth: 180,
                          ),
                        )
                      : Text(
                          initial,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: theme.colorScheme.primary,
                  shape: const CircleBorder(),
                  elevation: 0,
                  child: InkWell(
                    onTap: _uploading ? null : _pickAvatar,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: surface, width: 2),
                      ),
                      child: _uploading
                          ? Padding(
                              padding: const EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Icon(
                              Icons.edit_outlined,
                              size: 15,
                              color: theme.colorScheme.onPrimary,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.user.fullName ?? '',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.user.email ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
