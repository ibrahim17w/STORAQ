import '../lang/translations.dart';
import '../providers/locale_provider.dart';
import '../data/country_localizations.dart';
import '../services/location_service.dart';

/// Resolves store/city labels for the active app language without changing
/// stored values in the database.
class LocationDisplayHelper {
  LocationDisplayHelper._();

  static String localizedStoreCity(
    Map<String, dynamic>? store, {
    String? languageCode,
  }) {
    if (store == null) return '';

    final lang = languageCode ?? localeNotifier.value.languageCode;
    final displayNames = _parseDisplayNames(store['city_display_names']);
    if (displayNames != null) {
      final localized = _pickLocalized(displayNames, lang);
      if (localized.isNotEmpty) {
        return translateAddressTerms(localized);
      }
    }

    final raw = store['city']?.toString();
    if (raw == null || raw.isEmpty) return '';
    return translateAddressTerms(raw);
  }

  /// Best-effort localized address; fetches from geocoder when stored names
  /// are missing the active language (e.g. English-only "Masyaf" on Arabic UI).
  static Future<String> resolveStoreAddress(
    Map<String, dynamic> store, {
    String? languageCode,
  }) async {
    final lang = languageCode ?? localeNotifier.value.languageCode;
    final sync = localizedStoreCity(store, languageCode: lang);
    if (!_needsRemoteLocalization(store, lang)) return sync;

    final lat = _parseDouble(store['lat']);
    final lng = _parseDouble(store['lng']);
    if (lat != null && lng != null) {
      try {
        final geo = await LocationService.reverseGeocode(lat, lng, lang);
        final remote = fromGeocodeResult(geo, languageCode: lang);
        if (remote.isNotEmpty) return remote;
      } catch (_) {}
    }

    return sync;
  }

  static String fromGeocodeResult(
    Map<String, dynamic> geo, {
    String? languageCode,
  }) {
    final display = geo['display_name']?.toString().trim();
    if (display != null && display.isNotEmpty) {
      return translateAddressTerms(display);
    }

    final addr = geo['address'];
    if (addr is Map) {
      return formatAddressParts(
        addr.map((k, v) => MapEntry(k.toString(), v)),
        languageCode: languageCode,
      );
    }
    return '';
  }

  static String formatAddressParts(
    Map<String, dynamic> addr, {
    String? languageCode,
  }) {
    final parts = <String>[];
    for (final key in [
      'village',
      'hamlet',
      'suburb',
      'neighbourhood',
      'town',
      'city',
      'municipality',
      'county',
      'state_district',
      'state',
      'country',
    ]) {
      final value = addr[key]?.toString().trim();
      if (value == null || value.isEmpty) continue;
      if (!parts.any((p) => p.toLowerCase() == value.toLowerCase())) {
        parts.add(value);
      }
    }

    if (parts.isEmpty) return '';
    return translateAddressTerms(parts.join(', '));
  }

  static String localizedCountryLabel({
    String? country,
    String? countryCode,
    String? languageCode,
  }) {
    final code = countryCode?.trim();
    if (code != null && code.isNotEmpty) {
      final localized = CountryLocalizations.name(code, languageCode: languageCode);
      if (localized.isNotEmpty) return localized;
    }
    if (country != null && country.isNotEmpty) {
      return CountryLocalizations.name(country, languageCode: languageCode);
    }
    return '';
  }

  static String localizedCityLabel({
    String? city,
    String? cityId,
    Map<String, dynamic>? cityDisplayNames,
    String? languageCode,
  }) {
    final names = _parseDisplayNames(cityDisplayNames);
    if (names != null) {
      final picked = _pickLocalized(names, languageCode ?? localeNotifier.value.languageCode);
      if (picked.isNotEmpty) return translateAddressTerms(picked);
    }
    if (city != null && city.isNotEmpty && city.toLowerCase() != 'null') {
      return translateAddressTerms(city);
    }
    if (cityId != null && cityId.isNotEmpty) {
      return translateAddressTerms(_humanizeCanonicalId(cityId));
    }
    return '';
  }

  static String localizedVillageLabel(String? village, {String? villageId}) {
    if (village != null && village.isNotEmpty) {
      return translateAddressTerms(village);
    }
    if (villageId != null && villageId.isNotEmpty) {
      return translateAddressTerms(villageId);
    }
    return '';
  }

  static String localizedStoreCountry(
    Map<String, dynamic>? store, {
    String? languageCode,
  }) {
    if (store == null) return '';
    return localizedCountryLabel(
      country: store['country']?.toString(),
      countryCode: store['country_code']?.toString(),
      languageCode: languageCode,
    );
  }

  /// Swaps generic administrative terms and country names using translation
  /// keys. Proper nouns from geocoder are already in the target language.
  static String translateAddressTerms(String raw) {
    if (raw.isEmpty) return raw;

    var result = raw;
    final replacements = <String, String>{
      'Governorate': t('governorate'),
      'District': t('district'),
      'Subdistrict': t('subdistrict'),
      'Sub-district': t('subdistrict'),
      'Syria': t('syria'),
      'Syrian Arab Republic': t('syria'),
      'governorate': t('governorate'),
      'district': t('district'),
      'subdistrict': t('subdistrict'),
      'syria': t('syria'),
      'محافظة': t('governorate'),
      'منطقة': t('district'),
      'ناحية': t('subdistrict'),
    };

    replacements.forEach((source, translated) {
      if (translated.isNotEmpty && source != translated) {
        result = result.replaceAll(source, translated);
      }
    });

    result = _replaceTrailingCountryNames(result);
    return result;
  }

  static bool _needsRemoteLocalization(Map<String, dynamic> store, String lang) {
    final names = _parseDisplayNames(store['city_display_names']);
    if (names == null || names.isEmpty) return true;

    final localized = names[lang]?.trim();
    if (localized == null || localized.isEmpty) return true;

    if (lang != 'en') {
      final english = names['en']?.trim() ?? '';
      if (english.isNotEmpty && localized == english) return true;
      if (_looksLikeEnglishAddress(localized)) return true;
    }
    return false;
  }

  static bool _looksLikeEnglishAddress(String value) {
    final lower = value.toLowerCase();
    return lower.contains('governorate') ||
        lower.contains('district') ||
        lower.contains('subdistrict') ||
        RegExp(r'\bsyria\b').hasMatch(lower);
  }

  static String _replaceTrailingCountryNames(String raw) {
    var result = raw.trim();
    final parts = result.split(',').map((p) => p.trim()).toList();
    if (parts.isEmpty) return result;

    final last = parts.last;
    final localizedCountry = CountryLocalizations.name(last);
    if (localizedCountry.isNotEmpty && localizedCountry != last) {
      parts[parts.length - 1] = localizedCountry;
      result = parts.join(', ');
    }
    return result;
  }

  static String _humanizeCanonicalId(String id) {
    final parts = id.split('-');
    if (parts.length >= 3) {
      final city = parts[2].replaceAll('-', ' ');
      final state = parts[1].replaceAll('-', ' ');
      return translateAddressTerms('$city, $state');
    }
    return id;
  }

  static Map<String, String>? _parseDisplayNames(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
    return null;
  }

  static String _pickLocalized(Map<String, String> names, String lang) {
    final direct = names[lang]?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final english = names['en']?.trim();
    if (english != null && english.isNotEmpty) return english;

    for (final value in names.values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
