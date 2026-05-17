import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../data/countries.dart';
import '../services/api_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/theme_toggle.dart';
import '../widgets/app_notification.dart';
import '../providers/locale_provider.dart';
import '../lang/translations.dart';
import 'login_screen.dart';
import 'map_picker_screen.dart';
import '../utils/error_mapper.dart';

enum PasswordStrength { weak, medium, strong }

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _storeNameCtrl = TextEditingController();
  final _storeCityCtrl = TextEditingController();
  final _storeVillageCtrl = TextEditingController();
  final _storePhoneCtrl = TextEditingController();
  final _storeLatCtrl = TextEditingController();
  final _storeLngCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  PasswordStrength _strength = PasswordStrength.weak;
  String? _selectedRole;
  String? _selectedCountry;

  Map<String, String> get _roleLabels => {
    'store_owner': t('shop_owner'),
    'customer': t('consumer'),
  };

  PasswordStrength _checkPasswordStrength(String pwd) {
    if (pwd.isEmpty) return PasswordStrength.weak;
    int score = 0;
    if (pwd.length >= 8) score += 1;
    if (pwd.length >= 12) score += 1;
    if (pwd.length >= 16) score += 1;
    if (pwd.contains(RegExp(r'[A-Z]'))) score += 1;
    if (pwd.contains(RegExp(r'[a-z]'))) score += 1;
    if (pwd.contains(RegExp(r'[0-9]'))) score += 1;
    if (pwd.contains(RegExp(r'[!@#\$%^&*()_+\-=\[\]{}|;:,.<?]'))) score += 1;

    final lowerPwd = pwd.toLowerCase();
    final seqNums = [
      '012',
      '123',
      '234',
      '345',
      '456',
      '567',
      '678',
      '789',
      '890',
    ];
    for (final seq in seqNums) {
      if (pwd.contains(seq)) {
        score -= 2;
        break;
      }
    }
    final seqLet = [
      'abc',
      'bcd',
      'cde',
      'def',
      'efg',
      'fgh',
      'ghi',
      'hij',
      'ijk',
      'jkl',
      'klm',
      'lmn',
      'mno',
      'nop',
      'opq',
      'pqr',
      'qrs',
      'rst',
      'stu',
      'tuv',
      'uvw',
      'vwx',
      'wxy',
      'xyz',
    ];
    for (final seq in seqLet) {
      if (lowerPwd.contains(seq)) {
        score -= 2;
        break;
      }
    }
    if (pwd.length >= 6) {
      for (int i = 0; i <= pwd.length - 6; i++) {
        final chunk = pwd.substring(i, i + 3);
        final rest = pwd.substring(i + 3);
        if (rest.contains(chunk)) {
          score -= 2;
          break;
        }
      }
    }
    final weakPatterns = [
      'qwerty',
      'asdf',
      'zxcv',
      'password',
      'letmein',
      'admin',
      '123456',
      '111111',
      '000000',
    ];
    for (final pattern in weakPatterns) {
      if (lowerPwd.contains(pattern)) {
        score -= 3;
        break;
      }
    }
    final hasUpper = pwd.contains(RegExp(r'[A-Z]'));
    final hasLower = pwd.contains(RegExp(r'[a-z]'));
    final hasDigit = pwd.contains(RegExp(r'[0-9]'));
    final hasSymbol = pwd.contains(RegExp(r'[^A-Za-z0-9]'));
    final typeCount = [
      hasUpper,
      hasLower,
      hasDigit,
      hasSymbol,
    ].where((x) => x).length;
    if (typeCount < 3) score -= 1;

    if (score <= 2) return PasswordStrength.weak;
    if (score <= 4) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  void _onPasswordChanged(String value) {
    setState(() => _strength = _checkPasswordStrength(value));
  }

  String _generatePassword() {
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const numbers = '0123456789';
    const symbols = '!@#\$%^&*()_+-=[]{}|;:,.<?';
    const all = lower + upper + numbers + symbols;
    final random = Random.secure();
    final buffer = StringBuffer();
    buffer.write(lower[random.nextInt(lower.length)]);
    buffer.write(upper[random.nextInt(upper.length)]);
    buffer.write(numbers[random.nextInt(numbers.length)]);
    buffer.write(symbols[random.nextInt(symbols.length)]);
    for (int i = 4; i < 18; i++) {
      buffer.write(all[random.nextInt(all.length)]);
    }
    final chars = buffer.toString().split('');
    chars.shuffle(random);
    return chars.join();
  }

  void _suggestPassword() {
    String pwd;
    do {
      pwd = _generatePassword();
    } while (_checkPasswordStrength(pwd) != PasswordStrength.strong);
    setState(() {
      _passwordCtrl.text = pwd;
      _confirmCtrl.text = pwd;
      _obscurePassword = false;
      _obscureConfirm = false;
      _strength = PasswordStrength.strong;
    });
    showAppNotification(
      context,
      message: t('suggest_password'),
      isSuccess: true,
    );
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (result != null) {
      setState(() {
        _storeLatCtrl.text = result.latitude.toStringAsFixed(6);
        _storeLngCtrl.text = result.longitude.toStringAsFixed(6);
      });
    }
  }

  bool get _hasLocation =>
      _storeLatCtrl.text.isNotEmpty && _storeLngCtrl.text.isNotEmpty;

  bool get _isStrong => _strength == PasswordStrength.strong;

  Color get _strengthColor {
    switch (_strength) {
      case PasswordStrength.weak:
        return Colors.red;
      case PasswordStrength.medium:
        return Colors.orange;
      case PasswordStrength.strong:
        return Colors.green;
    }
  }

  String get _strengthText {
    switch (_strength) {
      case PasswordStrength.weak:
        return t('weak');
      case PasswordStrength.medium:
        return t('medium');
      case PasswordStrength.strong:
        return t('strong');
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return t('enter_email');
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) return t('invalid_credentials');
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return t('enter_phone');
    final phoneRegex = RegExp(r'^\+?[0-9\s\-\(\)]{7,20}$');
    if (!phoneRegex.hasMatch(value.trim())) return t('invalid_credentials');
    return null;
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().length < 2) return t('enter_name');
    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == null) {
      showAppNotification(
        context,
        message: t('select_account_type'),
        isError: true,
      );
      return;
    }
    if (_selectedRole == 'store_owner') {
      if (_storeNameCtrl.text.trim().isEmpty ||
          _storeCityCtrl.text.trim().isEmpty ||
          !_hasLocation ||
          _selectedCountry == null) {
        showAppNotification(
          context,
          message: t('fill_required'),
          isError: true,
        );
        return;
      }
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      showAppNotification(
        context,
        message: t('passwords_no_match'),
        isError: true,
      );
      return;
    }
    if (!_isStrong) {
      showAppNotification(
        context,
        message: t('password_not_strong'),
        isError: true,
      );
      return;
    }

    Map<String, dynamic>? storeData;
    if (_selectedRole == 'store_owner') {
      storeData = {
        'name': _storeNameCtrl.text.trim(),
        'city': _storeCityCtrl.text.trim(),
        'village': _storeVillageCtrl.text.trim(),
        'country': _selectedCountry,
        'phone': _storePhoneCtrl.text.trim(),
        'lat': double.tryParse(_storeLatCtrl.text.trim()),
        'lng': double.tryParse(_storeLngCtrl.text.trim()),
      };
    }

    setState(() => _isLoading = true);
    try {
      await ApiService.register(
        fullName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passwordCtrl.text,
        role: _selectedRole!,
        store: storeData,
        preferredLanguage: localeNotifier.value.languageCode,
      );
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(t('account_created')),
            content: Text(t('check_email_verify')),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                child: Text(t('ok')),
              ),
            ],
          ),
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
      if (mounted) setState(() => _isLoading = false);
    }
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
                            children: [
                              Icon(
                                Icons.storefront,
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
                                t('create_account'),
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
                                          controller: _nameCtrl,
                                          textInputAction: TextInputAction.next,
                                          validator: _validateName,
                                          decoration: InputDecoration(
                                            labelText: t('full_name'),
                                            prefixIcon: const Icon(
                                              Icons.person,
                                            ),
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
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
                                          controller: _phoneCtrl,
                                          keyboardType: TextInputType.phone,
                                          textInputAction: TextInputAction.next,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'[0-9+\-\s\(\)]'),
                                            ),
                                          ],
                                          textDirection: TextDirection.ltr,
                                          textAlign: TextAlign.left,
                                          validator: _validatePhone,
                                          decoration: InputDecoration(
                                            labelText: t('phone'),
                                            prefixIcon: const Icon(Icons.phone),
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        DropdownButtonFormField<String>(
                                          value: _selectedRole,
                                          decoration: InputDecoration(
                                            labelText: t('account_type'),
                                            prefixIcon: const Icon(Icons.badge),
                                            border: const OutlineInputBorder(),
                                          ),
                                          items: _roleLabels.entries.map((
                                            entry,
                                          ) {
                                            return DropdownMenuItem<String>(
                                              value: entry.key,
                                              child: Text(entry.value),
                                            );
                                          }).toList(),
                                          onChanged: (value) => setState(
                                            () => _selectedRole = value,
                                          ),
                                        ),
                                        if (_selectedRole == 'store_owner') ...[
                                          const SizedBox(height: 16),
                                          const Divider(),
                                          const SizedBox(height: 8),
                                          Text(
                                            t('shop_details'),
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _storeNameCtrl,
                                            textInputAction:
                                                TextInputAction.next,
                                            decoration: InputDecoration(
                                              labelText: '${t('store_name')} *',
                                              prefixIcon: const Icon(
                                                Icons.store,
                                              ),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _storeCityCtrl,
                                            textInputAction:
                                                TextInputAction.next,
                                            decoration: InputDecoration(
                                              labelText: '${t('city')} *',
                                              prefixIcon: const Icon(
                                                Icons.location_city,
                                              ),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _storeVillageCtrl,
                                            textInputAction:
                                                TextInputAction.next,
                                            decoration: InputDecoration(
                                              labelText: t('village'),
                                              prefixIcon: const Icon(Icons.map),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          DropdownButtonFormField<String>(
                                            value: _selectedCountry,
                                            decoration: InputDecoration(
                                              labelText: '${t('country')} *',
                                              prefixIcon: const Icon(
                                                Icons.public,
                                              ),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                            items: countries.map((c) {
                                              return DropdownMenuItem<String>(
                                                value: c,
                                                child: Text(c),
                                              );
                                            }).toList(),
                                            onChanged: (value) => setState(
                                              () => _selectedCountry = value,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _storePhoneCtrl,
                                            keyboardType: TextInputType.phone,
                                            textInputAction:
                                                TextInputAction.next,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'[0-9+\-\s\(\)]'),
                                              ),
                                            ],
                                            textDirection: TextDirection.ltr,
                                            textAlign: TextAlign.left,
                                            decoration: InputDecoration(
                                              labelText: t('store_phone'),
                                              prefixIcon: const Icon(
                                                Icons.phone_in_talk,
                                              ),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: OutlinedButton.icon(
                                                onPressed: _pickLocation,
                                                icon: const Icon(Icons.map),
                                                label: Text(t('pick_from_map')),
                                              ),
                                            ),
                                          ),
                                          if (_hasLocation)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.check_circle,
                                                    color:
                                                        Colors.green.shade600,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    t('location'),
                                                    style: TextStyle(
                                                      color:
                                                          Colors.green.shade700,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _passwordCtrl,
                                          obscureText: _obscurePassword,
                                          textInputAction: TextInputAction.next,
                                          onChanged: _onPasswordChanged,
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
                                        Row(
                                          children: [
                                            Expanded(
                                              child: LinearProgressIndicator(
                                                value:
                                                    _strength ==
                                                        PasswordStrength.weak
                                                    ? 0.33
                                                    : _strength ==
                                                          PasswordStrength
                                                              .medium
                                                    ? 0.66
                                                    : 1.0,
                                                backgroundColor:
                                                    Colors.grey.shade300,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(_strengthColor),
                                                minHeight: 6,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              _strengthText,
                                              style: TextStyle(
                                                color: _strengthColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: TextButton.icon(
                                              onPressed: _suggestPassword,
                                              icon: const Icon(
                                                Icons.auto_fix_high,
                                                size: 18,
                                              ),
                                              label: Text(
                                                t('suggest_password'),
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: _confirmCtrl,
                                          obscureText: _obscureConfirm,
                                          textInputAction: TextInputAction.done,
                                          onFieldSubmitted: (_) => _register(),
                                          decoration: InputDecoration(
                                            labelText: t('confirm_password'),
                                            prefixIcon: const Icon(
                                              Icons.lock_outline,
                                            ),
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                _obscureConfirm
                                                    ? Icons.visibility_off
                                                    : Icons.visibility,
                                              ),
                                              onPressed: () => setState(
                                                () => _obscureConfirm =
                                                    !_obscureConfirm,
                                              ),
                                            ),
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GradientButton(
                                            onPressed: _isLoading
                                                ? null
                                                : _register,
                                            isLoading: _isLoading,
                                            child: Text(
                                              t('signup'),
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
                                              Navigator.pushReplacement(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const LoginScreen(),
                                                ),
                                              );
                                            },
                                            child: Text(
                                              t('already_have_account'),
                                            ),
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _storeNameCtrl.dispose();
    _storeCityCtrl.dispose();
    _storeVillageCtrl.dispose();
    _storePhoneCtrl.dispose();
    _storeLatCtrl.dispose();
    _storeLngCtrl.dispose();
    super.dispose();
  }
}
