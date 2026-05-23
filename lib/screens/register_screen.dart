//register_screen.dart
import 'dart:async';
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

  // ── Canonical location (NEW) ──
  String? _selectedCityId;
  String? _selectedCityDisplay;
  bool _geocoding = false;
  List<dynamic> _geocodeResults = [];

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
      // Auto-geocode to canonical city
      await _autoGeocode(result.latitude, result.longitude);
    }
  }

  Future<void> _autoGeocode(double lat, double lng) async {
    setState(() => _geocoding = true);
    try {
      final lang = localeNotifier.value.languageCode;
      final geo = await ApiService.reverseGeocode(lat, lng, lang);
      if (geo != null && mounted) {
        setState(() {
          _selectedCityId = geo['canonical_id']?.toString();
          _selectedCityDisplay = geo['display_name']?.toString();
          _storeCityCtrl.text = geo['display_name']?.toString() ?? '';
          // Extract country from canonical_id (e.g. "sy-hama-masyaf")
          final parts = _selectedCityId?.split('-');
          if (parts != null && parts.isNotEmpty) {
            final cc = parts[0].toUpperCase();
            if (countries.contains(cc)) {
              _selectedCountry = cc;
            }
          }
        });
      }
    } catch (e) {
      // Silent fail — user can type manually
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _searchCity(String query) async {
    if (query.trim().length < 2) return;
    setState(() => _geocoding = true);
    try {
      final lang = localeNotifier.value.languageCode;
      final results = await ApiService.geocodeSearch(query, lang);
      if (mounted) {
        setState(() {
          _geocodeResults = results;
          _geocoding = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  void _selectGeocodeResult(dynamic result) {
    setState(() {
      _selectedCityId = result['canonical_id']?.toString();
      _selectedCityDisplay = result['display_name']?.toString();
      _storeCityCtrl.text = result['display_name']?.toString() ?? '';
      _storeLatCtrl.text = result['lat']?.toString() ?? '';
      _storeLngCtrl.text = result['lng']?.toString() ?? '';
      _geocodeResults = [];
      final cc = result['country_code']?.toString().toUpperCase();
      if (cc != null && countries.contains(cc)) {
        _selectedCountry = cc;
      }
    });
  }

  /// Auto-select first result (used by Enter key or initial tap)
  void _autoSelectFirstResult() {
    if (_geocodeResults.isNotEmpty) {
      _selectGeocodeResult(_geocodeResults.first);
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
        'Too many failed attempts. This code has been locked for your security. Please request a new code.',
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
      if (waitMatch != null) return waitMatch.group(0)!;
      return msg(
        'Please wait a moment before trying again.',
        'يرجى الانتظار لحظة قبل المحاولة مرة أخرى.',
      );
    }
    return mapBackendError(raw);
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
        'location_description': _storeVillageCtrl.text.trim().isNotEmpty
            ? _storeVillageCtrl.text.trim()
            : null,
        'country': _selectedCountry,
        'phone': _storePhoneCtrl.text.trim(),
        'lat': double.tryParse(_storeLatCtrl.text.trim()),
        'lng': double.tryParse(_storeLngCtrl.text.trim()),
        // NEW: canonical IDs for multilingual matching
        'city_id': _selectedCityId,
        'country_code': _selectedCountry != null
            ? _selectedCountry!.toLowerCase()
            : null,
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
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(t('request_timeout')),
      );
      if (mounted) {
        _showOtpDialog(_emailCtrl.text.trim());
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        showAppNotification(
          context,
          message: t('request_timeout'),
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(
          context,
          message: _getFriendlyError(e),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        await ApiService.resendVerification(email).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException(t('request_timeout')),
        );
        startCooldown();
        showAppNotification(
          context,
          message: t('verification_email_sent'),
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
      }
    }

    Future<void> verify() async {
      if (otpCtrl.text.trim().length != 6) {
        showAppNotification(context, message: t('invalid_code'), isError: true);
        return;
      }
      verifying = true;
      try {
        await ApiService.verifyEmail(
          email: email,
          code: otpCtrl.text.trim(),
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException(t('request_timeout')),
        );
        if (mounted) {
          Navigator.pop(context);
          showAppNotification(
            context,
            message: t('email_verified'),
            isSuccess: true,
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } on TimeoutException catch (_) {
        if (mounted) {
          showAppNotification(
            context,
            message: t('request_timeout'),
            isError: true,
          );
        }
      } catch (e) {
        if (mounted) {
          showAppNotification(
            context,
            message: _getFriendlyError(e),
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
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    if (v.length == 6) {
                      setDlgState(() {});
                      verify().then((_) => setDlgState(() {}));
                    }
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
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                child: Text(t('skip')),
              ),
              TextButton(
                onPressed: verifying
                    ? null
                    : () {
                        setDlgState(() {});
                        verify().then((_) => setDlgState(() {}));
                      },
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
                                          // NEW: Searchable city field with geocoding + auto-select
                                          TextFormField(
                                            controller: _storeCityCtrl,
                                            textInputAction:
                                                TextInputAction.next,
                                            onChanged: (v) {
                                              if (v.trim().length >= 3) {
                                                _searchCity(v.trim());
                                              } else if (v.trim().isEmpty) {
                                                setState(
                                                  () => _geocodeResults = [],
                                                );
                                              }
                                            },
                                            onEditingComplete: () {
                                              // Auto-select first result on Enter/dismiss keyboard
                                              _autoSelectFirstResult();
                                              FocusScope.of(
                                                context,
                                              ).nextFocus();
                                            },
                                            decoration: InputDecoration(
                                              labelText: '${t('city')} *',
                                              prefixIcon: const Icon(
                                                Icons.location_city,
                                              ),
                                              suffixIcon: _geocoding
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : (_selectedCityId != null
                                                        ? const Icon(
                                                            Icons.check_circle,
                                                            color: Colors.green,
                                                          )
                                                        : null),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          // Geocoding results dropdown
                                          if (_geocodeResults.isNotEmpty)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline
                                                      .withOpacity(0.3),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.1),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              constraints: const BoxConstraints(
                                                maxHeight: 200,
                                              ),
                                              child: SingleChildScrollView(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    // Auto-select hint
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 6,
                                                          ),
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primaryContainer
                                                          .withOpacity(0.3),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .keyboard_return,
                                                            size: 14,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Text(
                                                            t(
                                                                  'press_enter_auto',
                                                                ) ??
                                                                'Press Enter to select first',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    ..._geocodeResults.map((r) {
                                                      final display =
                                                          r['display_name']
                                                              ?.toString() ??
                                                          '';
                                                      final cid =
                                                          r['canonical_id']
                                                              ?.toString() ??
                                                          '';
                                                      return ListTile(
                                                        dense: true,
                                                        leading: const Icon(
                                                          Icons.place,
                                                          size: 20,
                                                        ),
                                                        title: Text(
                                                          display,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        subtitle: Text(
                                                          cid,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors
                                                                .grey
                                                                .shade500,
                                                          ),
                                                        ),
                                                        onTap: () =>
                                                            _selectGeocodeResult(
                                                              r,
                                                            ),
                                                      );
                                                    }).toList(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          if (_selectedCityId != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.check_circle,
                                                    size: 14,
                                                    color:
                                                        Colors.green.shade600,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'ID: $_selectedCityId',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .green
                                                            .shade700,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _storeVillageCtrl,
                                            textInputAction:
                                                TextInputAction.next,
                                            maxLines: 2,
                                            decoration: InputDecoration(
                                              labelText:
                                                  '${t('location_description') ?? 'Location description'} (${t('optional') ?? 'optional'})',
                                              hintText:
                                                  t('location_hint') ??
                                                  'e.g. Next to Al-Fayhaa Market, Main Street',
                                              prefixIcon: const Icon(
                                                Icons.notes,
                                              ),
                                              border:
                                                  const OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          // Searchable country dropdown with auto-detection
                                          _SearchableCountryField(
                                            value: _selectedCountry,
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
                                        // Live password requirement checklist
                                        _buildPasswordChecklist(
                                          _passwordCtrl.text,
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

// ============================================================
// SEARCHABLE COUNTRY DROPDOWN (inline typing + Enter selects)
// ============================================================

class _SearchableCountryField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _SearchableCountryField({this.value, required this.onChanged});

  @override
  State<_SearchableCountryField> createState() =>
      _SearchableCountryFieldState();
}

class _SearchableCountryFieldState extends State<_SearchableCountryField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isOpen = false;
  List<String> _filtered = [];

  // Common names so users can type "syr" / "syria" and find SY
  static const Map<String, String> _countryNames = {
    'AF': 'Afghanistan',
    'AL': 'Albania',
    'DZ': 'Algeria',
    'AR': 'Argentina',
    'AU': 'Australia',
    'AT': 'Austria',
    'BD': 'Bangladesh',
    'BE': 'Belgium',
    'BR': 'Brazil',
    'CA': 'Canada',
    'CN': 'China',
    'CO': 'Colombia',
    'EG': 'Egypt',
    'FR': 'France',
    'DE': 'Germany',
    'GR': 'Greece',
    'IN': 'India',
    'ID': 'Indonesia',
    'IR': 'Iran',
    'IQ': 'Iraq',
    'IE': 'Ireland',
    'IT': 'Italy',
    'JP': 'Japan',
    'JO': 'Jordan',
    'KW': 'Kuwait',
    'LB': 'Lebanon',
    'LY': 'Libya',
    'MY': 'Malaysia',
    'MX': 'Mexico',
    'MA': 'Morocco',
    'NL': 'Netherlands',
    'NZ': 'New Zealand',
    'NG': 'Nigeria',
    'PK': 'Pakistan',
    'PS': 'Palestine',
    'PE': 'Peru',
    'PH': 'Philippines',
    'PL': 'Poland',
    'QA': 'Qatar',
    'RU': 'Russia',
    'SA': 'Saudi Arabia',
    'SG': 'Singapore',
    'ZA': 'South Africa',
    'KR': 'South Korea',
    'ES': 'Spain',
    'SE': 'Sweden',
    'CH': 'Switzerland',
    'SY': 'Syria',
    'TW': 'Taiwan',
    'TH': 'Thailand',
    'TN': 'Tunisia',
    'TR': 'Turkey',
    'UA': 'Ukraine',
    'AE': 'United Arab Emirates',
    'GB': 'United Kingdom',
    'US': 'United States',
    'YE': 'Yemen',
  };

  @override
  void initState() {
    super.initState();
    _filtered = countries;
    if (widget.value != null) _controller.text = widget.value!;
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() {
        _isOpen = true;
        _filtered = countries;
      });
    } else {
      // Slight delay so a tap on a dropdown item registers before closing
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focusNode.hasFocus) {
          setState(() => _isOpen = false);
        }
      });
    }
  }

  @override
  void didUpdateWidget(_SearchableCountryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value != null) {
        if (_controller.text != widget.value) _controller.text = widget.value!;
      } else {
        _controller.clear();
      }
    }
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = countries;
      } else {
        final q = query.toLowerCase();
        _filtered = countries.where((c) {
          final name = _countryNames[c.toUpperCase()]?.toLowerCase() ?? '';
          return c.toLowerCase().contains(q) || name.contains(q);
        }).toList();
      }
      _isOpen = true;
    });
  }

  void _select(String country) {
    _controller.text = country;
    widget.onChanged(country);
    setState(() => _isOpen = false);
    _focusNode.unfocus();
  }

  void _onSubmitted(String value) {
    if (_filtered.isNotEmpty) {
      _select(_filtered.first);
    } else {
      setState(() => _isOpen = false);
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _filter,
          onEditingComplete: () => _onSubmitted(_controller.text),
          decoration: InputDecoration(
            labelText: '${t('country')} *',
            prefixIcon: const Icon(Icons.public),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.value != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 20,
                    ),
                  ),
                Icon(
                  _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: Colors.grey,
                ),
              ],
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_isOpen)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.text.isNotEmpty && _filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No countries found'),
                  ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final country = _filtered[i];
                      final isSelected = widget.value == country;
                      return ListTile(
                        dense: true,
                        leading: Text(
                          _countryEmoji(country),
                          style: const TextStyle(fontSize: 20),
                        ),
                        title: Text(
                          '${_countryNames[country.toUpperCase()] ?? country} ($country)',
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: Theme.of(context).colorScheme.primary,
                                size: 18,
                              )
                            : null,
                        tileColor: isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primaryContainer.withOpacity(0.3)
                            : null,
                        onTap: () => _select(country),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _countryEmoji(String countryCode) {
    final code = countryCode.toUpperCase();
    if (code.length != 2) return '🌐';
    final flagOffset = 0x1F1E6;
    final a = code.codeUnitAt(0);
    final b = code.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return '🌐';
    return String.fromCharCode(flagOffset + a - 65) +
        String.fromCharCode(flagOffset + b - 65);
  }
}
