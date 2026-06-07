import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bootstrap.dart';
import 'services/desktop_db_init.dart';
import 'services/deep_link_service.dart';
import 'screens/login_screen.dart';
import 'theme_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/auth_provider.dart';
import 'lang/translations.dart';
import 'screens/main_nav_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ProviderScope(child: MyApp()));

  // Never block the first frame on disk I/O or native SQLite init.
  unawaited(bootstrapAppSettings());
  unawaited(DesktopDbInit.ensureInitialized());
  unawaited(DeepLinkService.init());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        return ValueListenableBuilder<Locale>(
          valueListenable: localeNotifier,
          builder: (context, locale, child) {
            return MaterialApp(
              title: t('app_name'),
              debugShowCheckedModeBanner: false,
              themeMode: themeMode,
              locale: locale,
              supportedLocales: supportedLocales,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                scaffoldBackgroundColor: const Color(0xFFF0F4F8),
                colorScheme: ColorScheme.light(
                  primary: Colors.blue.shade700,
                  onPrimary: Colors.white,
                  secondary: Colors.blue.shade500,
                  surface: Colors.white,
                  onSurface: Colors.black87,
                  inversePrimary: Colors.blue.shade900,
                ),
                appBarTheme: AppBarTheme(
                  centerTitle: true,
                  elevation: 0,
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  titleTextStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                cardTheme: const CardThemeData(
                  elevation: 2,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                scaffoldBackgroundColor: const Color(0xFF0A0A0A),
                colorScheme: ColorScheme.dark(
                  primary: Colors.red.shade700,
                  onPrimary: Colors.white,
                  secondary: Colors.red.shade500,
                  surface: const Color(0xFF1A1A1A),
                  onSurface: Colors.white,
                  inversePrimary: Colors.red.shade900,
                ),
                appBarTheme: AppBarTheme(
                  centerTitle: true,
                  elevation: 0,
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  titleTextStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                cardTheme: const CardThemeData(
                  elevation: 2,
                  color: Color(0xFF1A1A1A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade700),
                  ),
                ),
              ),
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _authTimedOut = false;

  @override
  void initState() {
    super.initState();
    // If prefs hang on Windows, never stay on a blank spinner forever.
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (ref.read(authProvider).isLoading) {
        setState(() => _authTimedOut = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (auth.isLoading && !_authTimedOut) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.isAuthenticated) {
      return const PopScope(canPop: false, child: MainNavScreen());
    }
    return const LoginScreen();
  }
}
