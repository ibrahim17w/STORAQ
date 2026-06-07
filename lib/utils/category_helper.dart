import '../lang/translations.dart';
import '../providers/locale_provider.dart';
import '../models/category.dart';

class CategoryHelper {
  static String makeTranslationKey(String name) {
    return 'cat_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim().replaceAll(RegExp(r'\s+'), '_')}';
  }

  static String displayNameFromMap(Map<String, dynamic> cat) {
    final rawName = cat['name']?.toString() ?? t('unnamed');
    final code = localeNotifier.value.languageCode;

    final translations = cat['translations'];
    if (translations is Map) {
      final localized = translations[code]?.toString();
      if (localized != null && localized.isNotEmpty) return localized;
    }

    final key = makeTranslationKey(rawName);
    final translated = t(key);
    if (translated != key && translated.isNotEmpty) return translated;
    return rawName;
  }

  static String displayName(Category cat) {
    final code = localeNotifier.value.languageCode;
    return cat.localizedName(code).isNotEmpty
        ? cat.localizedName(code)
        : displayNameFromMap(cat.toJson());
  }
}
