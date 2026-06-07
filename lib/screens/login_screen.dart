//login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/theme_toggle.dart';
import '../providers/locale_provider.dart';
import '../providers/auth_provider.dart';
import '../lang/translations.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import '../widgets/app_notification.dart';
import '../utils/error_mapper.dart';
import 'main_nav_screen.dart';
import '../services/auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await ref.read(authProvider.notifier).login(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      try {
        await AuthService.updatePreferredLanguage(
          localeNotifier.value.languageCode,
        );
      } catch (_) {}

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainNavScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      final rawMsg = e.toString();
      final isVerifyError =
          rawMsg.toLowerCase().contains('not verified') ||
          rawMsg.toLowerCase().contains('verify your email');
      final msg = mapBackendError(rawMsg);
      if (mounted) {
        if (isVerifyError) {
          showAppNotification(context, message: msg, isError: true);
          _showOtpDialog(_emailCtrl.text.trim());
        } else {
          showAppNotification(context, message: msg, isError: true);
        }
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return t('enter_email');
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) return t('invalid_credentials');
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return t('enter_password');
    if (value.length < 8) return t('password_not_strong');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final _isLoading = auth.isLoading;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 80,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: ValueListenableBuilder<Locale>(
                            valueListenable: localeNotifier,
                            builder: (context, locale, _) => Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.storefront,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                t('app_name'),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t('login_subtitle'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 32),
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(
                                        context,
                                      ).shadowColor.withOpacity(0.1),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      children: [
                                        TextFormField(
                                          controller: _emailCtrl,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textInputAction: TextInputAction.next,
                                          validator: _validateEmail,
                                          decoration: InputDecoration(
                                            labelText: t('email'),
                                            prefixIcon: const Icon(Icons.email),
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _passwordCtrl,
                                          obscureText: _obscurePassword,
                                          textInputAction: TextInputAction.done,
                                          validator: _validatePassword,
                                          onFieldSubmitted: (_) => _login(),
                                          decoration: InputDecoration(
                                            labelText: t('password'),
                                            prefixIcon: const Icon(Icons.lock),
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                _obscurePassword
                                                    ? Icons.visibility_off
                                                    : Icons.visibility,
                                              ),
                                              onPressed: () => setState(
                                                () => _obscurePassword =
                                                    !_obscurePassword,
                                              ),
                                            ),
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: TextButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const ForgotPasswordScreen(),
                                                  ),
                                                );
                                              },
                                              child: Text(t('forgot_password')),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GradientButton(
                                            onPressed: _isLoading
                                                ? null
                                                : _login,
                                            isLoading: _isLoading,
                                            child: Text(
                                              t('login'),
                                              style: const TextStyle(
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: TextButton(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const RegisterScreen(),
                                                ),
                                              );
                                            },
                                            child: Text(t('dont_have_account')),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              try {
                                                await ref.read(authProvider.notifier).guestLogin();
                                              } catch (_) {
                                                await ApiService.setGuest(true);
                                              }
                                              if (mounted) {
                                                Navigator.pushAndRemoveUntil(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const MainNavScreen(),
                                                  ),
                                                  (route) => false,
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.person_outline,
                                            ),
                                            label: Text(t('continue_as_guest')),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(
                                                double.infinity,
                                                48,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: SafeArea(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ThemeToggle(),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: IconButton(
                            icon: ValueListenableBuilder<Locale>(
                              valueListenable: localeNotifier,
                              builder: (_, locale, __) => Text(
                                locale.languageCode.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            onPressed: () => showLanguagePicker(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showOtpDialog(String email) {
    final otpCtrl = TextEditingController();
    bool verifying = false;
    int cooldown = 0;
    Timer? timer;

    void startCooldown() {
      cooldown = 60;
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (cooldown > 0) {
          cooldown--;
        } else {
          t.cancel();
        }
      });
    }

    Future<void> resendCode() async {
      try {
        await AuthService.resendVerification(email);
        startCooldown();
        showAppNotification(
          context,
          message: t('verification_email_sent'),
          isSuccess: true,
        );
      } catch (e) {
        showAppNotification(
          context,
          message: mapBackendError(e.toString()),
          isError: true,
        );
      }
    }

    Future<void> verify() async {
      if (otpCtrl.text.trim().length != 6) {
        showAppNotification(context, message: t('invalid_code'), isError: true);
        return;
      }
      verifying = true;
      try {
        await AuthService.verifyEmail(email: email, code: otpCtrl.text.trim());
        if (mounted) {
          Navigator.pop(context);
          showAppNotification(
            context,
            message: t('email_verified'),
            isSuccess: true,
          );
        }
      } catch (e) {
        if (mounted) {
          showAppNotification(
            context,
            message: mapBackendError(e.toString()),
            isError: true,
          );
        }
      } finally {
        verifying = false;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: Text(t('verify_email')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('enter_6_digit_code')),
                const SizedBox(height: 16),
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: t('verification_code_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    if (v.length == 6) verify();
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: cooldown > 0
                      ? null
                      : () {
                          setDlgState(() {});
                          resendCode().then((_) => setDlgState(() {}));
                        },
                  child: Text(
                    cooldown > 0
                        ? '${t('resend')} (${cooldown}s)'
                        : t('resend'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  timer?.cancel();
                  Navigator.pop(ctx);
                },
                child: Text(t('cancel')),
              ),
              TextButton(
                onPressed: verifying ? null : verify,
                child: verifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t('verify')),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}
