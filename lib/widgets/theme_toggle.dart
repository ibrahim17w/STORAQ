import 'package:flutter/material.dart';
import '../lang/translations.dart';
import '../theme_provider.dart';

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, child) {
        IconData icon;
        switch (mode) {
          case ThemeMode.light:
            icon = Icons.light_mode;
            break;
          case ThemeMode.dark:
            icon = Icons.dark_mode;
            break;
          default:
            icon = Icons.brightness_auto;
        }
        return IconButton(
          icon: Icon(icon),
          tooltip: t('toggle_theme'),
          onPressed: () {
            ThemeMode next;
            switch (mode) {
              case ThemeMode.light:
                next = ThemeMode.dark;
                break;
              case ThemeMode.dark:
                next = ThemeMode.system;
                break;
              default:
                next = ThemeMode.light;
            }
            setThemeMode(next);
          },
        );
      },
    );
  }
}
