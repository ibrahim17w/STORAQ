//profile_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../providers/locale_provider.dart';
import '../lang/translations.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/guest_login_sheet.dart';
import 'my_store_screen.dart';
import 'main_nav_screen.dart'; // FIX: added

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await ApiService.logout();
    if (context.mounted) {
      // FIX: Go to MainNavScreen (as guest) instead of LoginScreen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
        (route) => false,
      );
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
                        t('login_to_continue'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('guest_restricted'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => showGuestSheet(context),
                        child: Text(t('login')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: ApiService.getCurrentUser(),
          builder: (context, userSnap) {
            final user = userSnap.data;
            final isSeller = user?['role'] == 'store_owner';

            return Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 120,
                    flexibleSpace: FlexibleSpaceBar(title: Text(t('profile'))),
                    actions: const [ThemeToggle(), SizedBox(width: 8)],
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            child: Text(
                              (user?['full_name'] ?? '?')
                                  .toString()
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 32,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            user?['full_name'] ?? '',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            user?['email'] ?? '',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 24),

                          if (isSeller)
                            ListTile(
                              leading: const Icon(Icons.store),
                              title: Text(t('my_store')),
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
                            leading: const Icon(Icons.language),
                            title: Text(t('language')),
                            trailing: Text(
                              localeNotifier.value.languageCode.toUpperCase(),
                            ),
                            onTap: () => showLanguagePicker(context),
                          ),

                          ListTile(
                            leading: const Icon(
                              Icons.logout,
                              color: Colors.red,
                            ),
                            title: Text(
                              t('logout'),
                              style: const TextStyle(color: Colors.red),
                            ),
                            onTap: () => _logout(context),
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
}
