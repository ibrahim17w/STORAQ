//guest_login_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../widgets/gradient_button.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';

/// Shows a bottom sheet prompting the guest user to log in or register
/// when they try to access a restricted feature.
void showGuestSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              t('login_to_continue'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              t('guest_restricted'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),
            GradientButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: Text(t('login'), style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                );
              },
              child: Text(t('dont_have_account')),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Helper to check if user can perform an action.
/// If guest, shows the login sheet and returns false.
/// If logged in, returns true.
Future<bool> requireAuth(BuildContext context) async {
  final isGuest = await ApiService.isGuest();
  final isLoggedIn = await ApiService.isLoggedIn();

  if (isGuest && !isLoggedIn) {
    showGuestSheet(context);
    return false;
  }
  return true;
}
