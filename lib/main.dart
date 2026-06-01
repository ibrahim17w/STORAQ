import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'theme_provider.dart';
import 'providers/locale_provider.dart';
import 'lang/translations.dart';
import 'screens/main_nav_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeLocale();
  await initializeTheme();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const MyApp());
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
              title: 'Market Bridge',
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

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _isAuthenticated;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final hasToken = await ApiService.isLoggedIn();
    final isGuest = await ApiService.isGuest();

    // Stay logged in if we have a token OR if we are in guest mode.
    // This check is LOCAL ONLY — it never contacts the server.
    if (mounted) {
      setState(() => _isAuthenticated = hasToken || isGuest);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_isAuthenticated == true) {
      return const PopScope(canPop: false, child: MainNavScreen());
    }
    return const LoginScreen();
  }
}
