import 'package:flutter/material.dart';
import 'providers/locale_provider.dart';
import 'services/prefs_service.dart';
import 'theme_provider.dart';

/// Loads saved locale + theme from a single SharedPreferences read.
/// Safe to call after [runApp] — defaults apply until this completes.
Future<void> bootstrapAppSettings() async {
  try {
    final prefs = await PrefsService.instance;

    final savedLang = prefs.getString('preferred_language');
    if (savedLang != null) {
      localeNotifier.value = Locale(savedLang);
    } else {
      final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final code = platformLocale.languageCode;
      Locale selected = const Locale('en');
      for (final l in supportedLocales) {
        if (l.languageCode == code) {
          selected = l;
          break;
        }
      }
      localeNotifier.value = selected;
      await prefs.setString('preferred_language', selected.languageCode);
    }

    final savedTheme = prefs.getString('theme_mode');
    if (savedTheme == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    } else {
      themeNotifier.value = ThemeMode.system;
    }
  } catch (e) {
    debugPrint('bootstrapAppSettings failed: $e');
  }
}
