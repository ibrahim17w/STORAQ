//forgot_password_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/app_notification.dart';
import '../providers/locale_provider.dart';
import '../lang/translations.dart';
import '../utils/error_mapper.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  bool _isLoading = false;
  bool _codeSent = false;
  bool _obscure = true;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_cooldown > 0) {
          _cooldown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  /// Converts backend OTP/reset errors into human-friendly text.
  String _getFriendlyError(dynamic error) {
    final raw = error.toString();
    final isAr = localeNotifier.value.languageCode == 'ar';

    String msg(String en, String ar) => isAr ? ar : en;

    final jsonMatch = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(raw);
    final serverMsg = jsonMatch?.group(1)?.toLowerCase() ?? raw.toLowerCase();

    if (serverMsg.contains('too many failed attempts') ||
        serverMsg.contains('locked')) {
      return msg(
        'Too many failed attempts. This code has been locked for your security. Please request a new reset code.',
        'لقد تجاوزت الحد المسموح من المحاولات. تم إلغاء هذا الرمز لحماية حسابك. يرجى طلب رمز جديد.',
      );
    }

    if (serverMsg.contains('expired') ||
        serverMsg.contains('no longer valid')) {
      return msg(
        'This code has expired or is no longer valid. Please request a new one.',
        'انتهت صلاحية هذا الرمز أو لم يعد صالحاً. يرجى طلب رمز جديد.',
      );
    }

    if (serverMsg.contains('incorrect') ||
        serverMsg.contains('invalid') ||
        serverMsg.contains('wrong')) {
      return msg(
        'Incorrect code. Please try again.',
        'الرمز غير صحيح. يرجى المحاولة مرة أخرى.',
      );
    }

    if (serverMsg.contains('wait')) {
      final waitMatch = RegExp(r'Please wait [^.]+').firstMatch(raw);
      if (waitMatch != null) {
        return waitMatch.group(0)!;
      }
      return msg(
        'Please wait a moment before trying again.',
        'يرجى الانتظار لحظة قبل المحاولة مرة أخرى.',
      );
    }

    return mapBackendError(raw);
  }

  /// Live checklist that shows exactly which rules are met.
  Widget _buildPasswordChecklist(String pwd) {
    final requirements = [
      ('At least 8 characters', pwd.length >= 8),
      ('Uppercase letter (A-Z)', pwd.contains(RegExp(r'[A-Z]'))),
      ('Lowercase letter (a-z)', pwd.contains(RegExp(r'[a-z]'))),
      ('Number (0-9)', pwd.contains(RegExp(r'[0-9]'))),
      ('Special character (!@#\$%^&*)', pwd.contains(RegExp(r'[^A-Za-z0-9]'))),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: requirements.map((req) {
          final met = req.$2;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  met ? Icons.check_circle : Icons.cancel,
                  size: 14,
                  color: met ? Colors.green.shade600 : Colors.red.shade300,
                ),
                const SizedBox(width: 8),
                Text(
                  req.$1,
                  style: TextStyle(
                    fontSize: 12,
                    color: met ? Colors.green.shade700 : Colors.grey.shade600,
                    fontWeight: met ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _sendCode() async {
    if (_cooldown > 0) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService.forgotPassword(_emailCtrl.text.trim()).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(t('request_timeout')),
      );
      setState(() => _codeSent = true);
      _startCooldown();
      showAppNotification(
        context,
        message: t('reset_code_sent'),
        isSuccess: true,
      );
    } on TimeoutException catch (_) {
      showAppNotification(
        context,
        message: t('request_timeout'),
        isError: true,
      );
    } catch (e) {
      showAppNotification(
        context,
        message: _getFriendlyError(e),
        isError: true,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_newPassCtrl.text.length < 8) {
      showAppNotification(
        context,
        message: t('password_not_strong'),
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.resetPassword(
        email: _emailCtrl.text.trim(),
        code: _codeCtrl.text.trim(),
        newPassword: _newPassCtrl.text,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(t('request_timeout')),
      );
      showAppNotification(
        context,
        message: t('password_reset_success'),
        isSuccess: true,
      );
      Navigator.pop(context);
    } on TimeoutException catch (_) {
      showAppNotification(
        context,
        message: t('request_timeout'),
        isError: true,
      );
    } catch (e) {
      showAppNotification(
        context,
        message: _getFriendlyError(e),
        isError: true,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return t('enter_email');
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) return t('invalid_credentials');
    return null;
  }

  String? _validateCode(String? value) {
    if (value == null || value.trim().isEmpty) return t('reset_code');
    if (value.trim().length != 6) return t('invalid_code');
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return t('enter_password');
    if (value.length < 8) return t('password_not_strong');
    return null;
  }

  @override
  Widget build(BuildContext context) {
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
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_reset,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Market Bridge',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t('forgot_password'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color.fromARGB(255, 78, 76, 76),
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
                                          textInputAction: TextInputAction.done,
                                          validator: _validateEmail,
                                          onFieldSubmitted: (_) {
                                            if (!_codeSent) _sendCode();
                                          },
                                          enabled: !_codeSent,
                                          decoration: InputDecoration(
                                            labelText: t('email'),
                                            prefixIcon: const Icon(Icons.email),
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        if (_codeSent) ...[
                                          TextFormField(
                                            controller: _codeCtrl,
                                            keyboardType: TextInputType.number,
                                            textInputAction:
                                                TextInputAction.next,
                                            validator: _validateCode,
                                            decoration: InputDecoration(
                                              labelText: t('reset_code'),
                                              prefixIcon: const Icon(
                                                Icons.confirmation_number,
                                              ),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          TextFormField(
                                            controller: _newPassCtrl,
                                            obscureText: _obscure,
                                            textInputAction:
                                                TextInputAction.done,
                                            validator: _validatePassword,
                                            onFieldSubmitted: (_) =>
                                                _resetPassword(),
                                            decoration: InputDecoration(
                                              labelText: t('new_password'),
                                              prefixIcon: const Icon(
                                                Icons.lock,
                                              ),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _obscure
                                                      ? Icons.visibility_off
                                                      : Icons.visibility,
                                                ),
                                                onPressed: () => setState(
                                                  () => _obscure = !_obscure,
                                                ),
                                              ),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          // Live password requirement checklist
                                          _buildPasswordChecklist(
                                            _newPassCtrl.text,
                                          ),
                                          const SizedBox(height: 24),
                                          MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: GradientButton(
                                              onPressed: _isLoading
                                                  ? null
                                                  : _resetPassword,
                                              isLoading: _isLoading,
                                              child: Text(
                                                t('reset_password'),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: GradientButton(
                                              onPressed:
                                                  (_isLoading || _cooldown > 0)
                                                  ? null
                                                  : _sendCode,
                                              isLoading: _isLoading,
                                              child: Text(
                                                _cooldown > 0
                                                    ? '${t('send_reset_code')} ($_cooldown)'
                                                    : t('send_reset_code'),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: TextButton(
                                            onPressed: () {
                                              Navigator.pushReplacement(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const LoginScreen(),
                                                ),
                                              );
                                            },
                                            child: Text(t('back')),
                                          ),
                                        ),
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
}
