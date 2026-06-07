import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lang/translations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

final List<Locale> supportedLocales = [
  const Locale('en'),
  const Locale('ar'),
  const Locale('fr'),
  const Locale('es'),
  const Locale('tr'),
  const Locale('ur'),
  const Locale('hi'),
  const Locale('bn'),
  const Locale('ru'),
  const Locale('zh'),
];

ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('en'));

Future<void> initializeLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final savedLang = prefs.getString('preferred_language');

  if (savedLang != null) {
    // User has a saved preference — use it
    localeNotifier = ValueNotifier(Locale(savedLang));
  } else {
    // First time — use device language
    final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final code = platformLocale.languageCode;
    Locale selected = const Locale('en');
    for (final l in supportedLocales) {
      if (l.languageCode == code) {
        selected = l;
        break;
      }
    }
    localeNotifier = ValueNotifier(selected);
    await prefs.setString('preferred_language', selected.languageCode);
  }
}

Future<void> saveLanguageLocally(String code) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('preferred_language', code);
}

bool isRTL(Locale locale) {
  return ['ar', 'ur', 'he', 'fa'].contains(locale.languageCode);
}

void showLanguagePicker(BuildContext context) {
  final languages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'ar', 'name': 'Arabic', 'native': 'العربية'},
    {'code': 'fr', 'name': 'French', 'native': 'Français'},
    {'code': 'es', 'name': 'Spanish', 'native': 'Español'},
    {'code': 'tr', 'name': 'Turkish', 'native': 'Türkçe'},
    {'code': 'ur', 'name': 'Urdu', 'native': 'اردو'},
    {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी'},
    {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা'},
    {'code': 'ru', 'name': 'Russian', 'native': 'Русский'},
    {'code': 'zh', 'name': 'Chinese', 'native': '中文'},
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                t('language'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: languages.length,
                itemBuilder: (context, index) {
                  final lang = languages[index];
                  final isSelected =
                      localeNotifier.value.languageCode == lang['code'];
                  return ListTile(
                    leading: Text(
                      lang['native']!,
                      style: const TextStyle(fontSize: 16),
                    ),
                    title: Text(lang['name']!),
                    trailing: isSelected
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () async {
                      final code = lang['code']!;
                      localeNotifier.value = Locale(code);
                      await saveLanguageLocally(code);

                      // Sync to backend if logged in
                      try {
                        final token = await ApiService.getToken();
                        if (token != null) {
                          await AuthService.updatePreferredLanguage(code);
                        }
                      } catch (_) {}

                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
