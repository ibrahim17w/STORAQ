/// Maps viewer country to the currency used for platform payments and defaults.
class GeoCurrencyHelper {
  static const defaultCurrency = 'USD';

  static String currencyForCountryCode(String? countryCode) {
    if (countryCode == null || countryCode.trim().isEmpty) return defaultCurrency;
    switch (countryCode.trim().toUpperCase()) {
      case 'SY':
        return 'SYP';
      case 'US':
        return 'USD';
      case 'GB':
      case 'UK':
        return 'GBP';
      case 'TR':
        return 'TRY';
      case 'SA':
        return 'SAR';
      case 'AE':
        return 'AED';
      case 'JO':
        return 'JOD';
      case 'QA':
        return 'QAR';
      case 'CA':
        return 'CAD';
      case 'CH':
        return 'CHF';
      case 'EU':
        return 'EUR';
      case 'DE':
      case 'FR':
      case 'IT':
      case 'ES':
      case 'NL':
      case 'BE':
      case 'AT':
      case 'PT':
      case 'IE':
      case 'GR':
        return 'EUR';
      default:
        return defaultCurrency;
    }
  }
}
