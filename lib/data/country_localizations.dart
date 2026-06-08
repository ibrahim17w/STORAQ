import '../providers/locale_provider.dart';

/// Localized country names keyed by ISO 3166-1 alpha-2 code.
class CountryLocalizations {
  CountryLocalizations._();

  static const List<String> supportedLanguages = [
    'en',
    'ar',
    'fr',
    'es',
    'tr',
  ];

  static const Map<String, Map<String, String>> _names = {
    'AF': {
      'en': 'Afghanistan',
      'ar': 'أفغانستان',
      'fr': 'Afghanistan',
      'es': 'Afganistán',
      'tr': 'Afganistan',
    },
    'AL': {
      'en': 'Albania',
      'ar': 'ألبانيا',
      'fr': 'Albanie',
      'es': 'Albania',
      'tr': 'Arnavutluk',
    },
    'DZ': {
      'en': 'Algeria',
      'ar': 'الجزائر',
      'fr': 'Algérie',
      'es': 'Argelia',
      'tr': 'Cezayir',
    },
    'AR': {
      'en': 'Argentina',
      'ar': 'الأرجنتين',
      'fr': 'Argentine',
      'es': 'Argentina',
      'tr': 'Arjantin',
    },
    'AU': {
      'en': 'Australia',
      'ar': 'أستراليا',
      'fr': 'Australie',
      'es': 'Australia',
      'tr': 'Avustralya',
    },
    'AT': {
      'en': 'Austria',
      'ar': 'النمسا',
      'fr': 'Autriche',
      'es': 'Austria',
      'tr': 'Avusturya',
    },
    'BD': {
      'en': 'Bangladesh',
      'ar': 'بنغلاديش',
      'fr': 'Bangladesh',
      'es': 'Bangladés',
      'tr': 'Bangladeş',
    },
    'BE': {
      'en': 'Belgium',
      'ar': 'بلجيكا',
      'fr': 'Belgique',
      'es': 'Bélgica',
      'tr': 'Belçika',
    },
    'BR': {
      'en': 'Brazil',
      'ar': 'البرازيل',
      'fr': 'Brésil',
      'es': 'Brasil',
      'tr': 'Brezilya',
    },
    'CA': {
      'en': 'Canada',
      'ar': 'كندا',
      'fr': 'Canada',
      'es': 'Canadá',
      'tr': 'Kanada',
    },
    'CN': {
      'en': 'China',
      'ar': 'الصين',
      'fr': 'Chine',
      'es': 'China',
      'tr': 'Çin',
    },
    'CO': {
      'en': 'Colombia',
      'ar': 'كولومبيا',
      'fr': 'Colombie',
      'es': 'Colombia',
      'tr': 'Kolombiya',
    },
    'EG': {
      'en': 'Egypt',
      'ar': 'مصر',
      'fr': 'Égypte',
      'es': 'Egipto',
      'tr': 'Mısır',
    },
    'FR': {
      'en': 'France',
      'ar': 'فرنسا',
      'fr': 'France',
      'es': 'Francia',
      'tr': 'Fransa',
    },
    'DE': {
      'en': 'Germany',
      'ar': 'ألمانيا',
      'fr': 'Allemagne',
      'es': 'Alemania',
      'tr': 'Almanya',
    },
    'GR': {
      'en': 'Greece',
      'ar': 'اليونان',
      'fr': 'Grèce',
      'es': 'Grecia',
      'tr': 'Yunanistan',
    },
    'IN': {
      'en': 'India',
      'ar': 'الهند',
      'fr': 'Inde',
      'es': 'India',
      'tr': 'Hindistan',
    },
    'ID': {
      'en': 'Indonesia',
      'ar': 'إندونيسيا',
      'fr': 'Indonésie',
      'es': 'Indonesia',
      'tr': 'Endonezya',
    },
    'IR': {
      'en': 'Iran',
      'ar': 'إيران',
      'fr': 'Iran',
      'es': 'Irán',
      'tr': 'İran',
    },
    'IQ': {
      'en': 'Iraq',
      'ar': 'العراق',
      'fr': 'Irak',
      'es': 'Irak',
      'tr': 'Irak',
    },
    'IE': {
      'en': 'Ireland',
      'ar': 'أيرلندا',
      'fr': 'Irlande',
      'es': 'Irlanda',
      'tr': 'İrlanda',
    },
    'IT': {
      'en': 'Italy',
      'ar': 'إيطاليا',
      'fr': 'Italie',
      'es': 'Italia',
      'tr': 'İtalya',
    },
    'JP': {
      'en': 'Japan',
      'ar': 'اليابان',
      'fr': 'Japon',
      'es': 'Japón',
      'tr': 'Japonya',
    },
    'JO': {
      'en': 'Jordan',
      'ar': 'الأردن',
      'fr': 'Jordanie',
      'es': 'Jordania',
      'tr': 'Ürdün',
    },
    'KW': {
      'en': 'Kuwait',
      'ar': 'الكويت',
      'fr': 'Koweït',
      'es': 'Kuwait',
      'tr': 'Kuveyt',
    },
    'LB': {
      'en': 'Lebanon',
      'ar': 'لبنان',
      'fr': 'Liban',
      'es': 'Líbano',
      'tr': 'Lübnan',
    },
    'LY': {
      'en': 'Libya',
      'ar': 'ليبيا',
      'fr': 'Libye',
      'es': 'Libia',
      'tr': 'Libya',
    },
    'MY': {
      'en': 'Malaysia',
      'ar': 'ماليزيا',
      'fr': 'Malaisie',
      'es': 'Malasia',
      'tr': 'Malezya',
    },
    'MX': {
      'en': 'Mexico',
      'ar': 'المكسيك',
      'fr': 'Mexique',
      'es': 'México',
      'tr': 'Meksika',
    },
    'MA': {
      'en': 'Morocco',
      'ar': 'المغرب',
      'fr': 'Maroc',
      'es': 'Marruecos',
      'tr': 'Fas',
    },
    'NL': {
      'en': 'Netherlands',
      'ar': 'هولندا',
      'fr': 'Pays-Bas',
      'es': 'Países Bajos',
      'tr': 'Hollanda',
    },
    'NZ': {
      'en': 'New Zealand',
      'ar': 'نيوزيلندا',
      'fr': 'Nouvelle-Zélande',
      'es': 'Nueva Zelanda',
      'tr': 'Yeni Zelanda',
    },
    'NG': {
      'en': 'Nigeria',
      'ar': 'نيجيريا',
      'fr': 'Nigéria',
      'es': 'Nigeria',
      'tr': 'Nijerya',
    },
    'PK': {
      'en': 'Pakistan',
      'ar': 'باكستان',
      'fr': 'Pakistan',
      'es': 'Pakistán',
      'tr': 'Pakistan',
    },
    'PS': {
      'en': 'Palestine',
      'ar': 'فلسطين',
      'fr': 'Palestine',
      'es': 'Palestina',
      'tr': 'Filistin',
    },
    'PE': {
      'en': 'Peru',
      'ar': 'بيرو',
      'fr': 'Pérou',
      'es': 'Perú',
      'tr': 'Peru',
    },
    'PH': {
      'en': 'Philippines',
      'ar': 'الفلبين',
      'fr': 'Philippines',
      'es': 'Filipinas',
      'tr': 'Filipinler',
    },
    'PL': {
      'en': 'Poland',
      'ar': 'بولندا',
      'fr': 'Pologne',
      'es': 'Polonia',
      'tr': 'Polonya',
    },
    'QA': {
      'en': 'Qatar',
      'ar': 'قطر',
      'fr': 'Qatar',
      'es': 'Catar',
      'tr': 'Katar',
    },
    'RU': {
      'en': 'Russia',
      'ar': 'روسيا',
      'fr': 'Russie',
      'es': 'Rusia',
      'tr': 'Rusya',
    },
    'SA': {
      'en': 'Saudi Arabia',
      'ar': 'السعودية',
      'fr': 'Arabie saoudite',
      'es': 'Arabia Saudita',
      'tr': 'Suudi Arabistan',
    },
    'SG': {
      'en': 'Singapore',
      'ar': 'سنغافورة',
      'fr': 'Singapour',
      'es': 'Singapur',
      'tr': 'Singapur',
    },
    'ZA': {
      'en': 'South Africa',
      'ar': 'جنوب أفريقيا',
      'fr': 'Afrique du Sud',
      'es': 'Sudáfrica',
      'tr': 'Güney Afrika',
    },
    'KR': {
      'en': 'South Korea',
      'ar': 'كوريا الجنوبية',
      'fr': 'Corée du Sud',
      'es': 'Corea del Sur',
      'tr': 'Güney Kore',
    },
    'ES': {
      'en': 'Spain',
      'ar': 'إسبانيا',
      'fr': 'Espagne',
      'es': 'España',
      'tr': 'İspanya',
    },
    'SE': {
      'en': 'Sweden',
      'ar': 'السويد',
      'fr': 'Suède',
      'es': 'Suecia',
      'tr': 'İsveç',
    },
    'CH': {
      'en': 'Switzerland',
      'ar': 'سويسرا',
      'fr': 'Suisse',
      'es': 'Suiza',
      'tr': 'İsviçre',
    },
    'SY': {
      'en': 'Syria',
      'ar': 'سوريا',
      'fr': 'Syrie',
      'es': 'Siria',
      'tr': 'Suriye',
    },
    'TW': {
      'en': 'Taiwan',
      'ar': 'تايوان',
      'fr': 'Taïwan',
      'es': 'Taiwán',
      'tr': 'Tayvan',
    },
    'TH': {
      'en': 'Thailand',
      'ar': 'تايلاند',
      'fr': 'Thaïlande',
      'es': 'Tailandia',
      'tr': 'Tayland',
    },
    'TN': {
      'en': 'Tunisia',
      'ar': 'تونس',
      'fr': 'Tunisie',
      'es': 'Túnez',
      'tr': 'Tunus',
    },
    'TR': {
      'en': 'Turkey',
      'ar': 'تركيا',
      'fr': 'Turquie',
      'es': 'Turquía',
      'tr': 'Türkiye',
    },
    'UA': {
      'en': 'Ukraine',
      'ar': 'أوكرانيا',
      'fr': 'Ukraine',
      'es': 'Ucrania',
      'tr': 'Ukrayna',
    },
    'AE': {
      'en': 'United Arab Emirates',
      'ar': 'الإمارات',
      'fr': 'Émirats arabes unis',
      'es': 'Emiratos Árabes Unidos',
      'tr': 'Birleşik Arap Emirlikleri',
    },
    'GB': {
      'en': 'United Kingdom',
      'ar': 'المملكة المتحدة',
      'fr': 'Royaume-Uni',
      'es': 'Reino Unido',
      'tr': 'Birleşik Krallık',
    },
    'US': {
      'en': 'United States',
      'ar': 'الولايات المتحدة',
      'fr': 'États-Unis',
      'es': 'Estados Unidos',
      'tr': 'Amerika Birleşik Devletleri',
    },
    'YE': {
      'en': 'Yemen',
      'ar': 'اليمن',
      'fr': 'Yémen',
      'es': 'Yemen',
      'tr': 'Yemen',
    },
  };

  static final Map<String, String> _englishNameToCode = {
    for (final entry in _names.entries) entry.value['en']!.toLowerCase(): entry.key,
  };

  static String? resolveCode(String? value) {
    if (value == null || value.isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length == 2) return trimmed.toUpperCase();

    final lower = trimmed.toLowerCase();
    final byEnglish = _englishNameToCode[lower];
    if (byEnglish != null) return byEnglish;

    for (final entry in _names.entries) {
      for (final name in entry.value.values) {
        if (name.toLowerCase() == lower) return entry.key;
      }
    }
    return null;
  }

  static String name(String? value, {String? languageCode}) {
    if (value == null || value.isEmpty) return '';
    final code = resolveCode(value);
    if (code == null) return value;

    final lang = _normalizeLanguage(languageCode ?? localeNotifier.value.languageCode);
    final names = _names[code];
    if (names == null) return value;
    return names[lang] ?? names['en'] ?? value;
  }

  static String englishName(String code) {
    return _names[code.toUpperCase()]?['en'] ?? code;
  }

  static bool matchesQuery(String code, String query, {String? languageCode}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final upper = code.toUpperCase();
    if (upper.toLowerCase().contains(q)) return true;

    final names = _names[upper];
    if (names == null) return false;

    final lang = _normalizeLanguage(languageCode ?? localeNotifier.value.languageCode);
    final candidates = <String>{
      names['en'] ?? '',
      names[lang] ?? '',
      ...names.values,
    };

    for (final candidate in candidates) {
      if (candidate.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  static String _normalizeLanguage(String code) {
    if (supportedLanguages.contains(code)) return code;
    return 'en';
  }
}
