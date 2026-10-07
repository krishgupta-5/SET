/// Standardized currency formatting service for the startup expense tracker
///
/// Ensures consistent currency formatting across all UI components
/// and eliminates formatting inconsistencies that can cause confusion.
library;

import 'currency_preference_service.dart';

class CurrencyFormatter {
  // Private constructor to prevent instantiation
  CurrencyFormatter._();

  // Currency mapping based on country codes
  static const Map<String, String> _countryCurrencies = {
    '+1': '\$', // United States - USD
    '+91': '₹', // India - INR
    '+44': '£', // United Kingdom - GBP
    '+61': 'A\$', // Australia - AUD
    '+81': '¥', // Japan - JPY
    '+49': '€', // Germany - EUR
    '+33': '€', // France - EUR
    '+971': 'د.إ', // UAE - AED
    '+65': 'S\$', // Singapore - SGD
  };

  // Currency decimal places mapping
  static const Map<String, int> _currencyDecimals = {
    '+1': 2, // USD
    '+91': 2, // INR
    '+44': 2, // GBP
    '+61': 2, // AUD
    '+81': 0, // JPY (no decimal places)
    '+49': 2, // EUR
    '+33': 2, // EUR
    '+971': 2, // AED
    '+65': 2, // SGD
  };

  // Get currency symbol from country code
  static String getCurrencySymbol(String countryCode) {
    return _countryCurrencies[countryCode] ?? '\$'; // Default to USD
  }

  // Get decimal places for currency
  static int getDecimalPlaces(String countryCode) {
    return _currencyDecimals[countryCode] ?? 2; // Default to 2 decimal places
  }

  /// Get the current user's preferred currency code
  /// Uses the currency preference service to get user's selection
  static Future<String> getCurrentCurrencyCode() async {
    return await CurrencyPreferenceService.getCurrencyPreference();
  }

  /// Get the current user's preferred currency code synchronously
  /// Uses cached value from currency preference service
  static String getCurrentCurrencyCodeSync() {
    return CurrencyPreferenceService.getCurrencyPreferenceSync();
  }

  /// Format currency value with proper formatting based on country code
  ///
  /// [value] - The monetary value to format
  /// [countryCode] - Country code for currency symbol and formatting (default: user's preferred currency)
  /// [includeSymbol] - Whether to include currency symbol (default: true)
  /// [decimalPlaces] - Number of decimal places (default: based on currency)
  /// Returns formatted currency string
  static String format(
    double value, {
    String? countryCode,
    bool includeSymbol = true,
    int? decimalPlaces,
  }) {
    // Use user's preferred currency if no country code is provided
    final effectiveCountryCode = countryCode ?? getCurrentCurrencyCodeSync();

    // Get decimal places for the currency if not specified
    final places = decimalPlaces ?? getDecimalPlaces(effectiveCountryCode);

    // Round to avoid floating point precision issues
    final roundedValue = double.parse(value.toStringAsFixed(places));

    // Convert to string and add commas for thousands
    String formatted = roundedValue.toStringAsFixed(places);

    // Format based on country
    if (effectiveCountryCode == '+91') {
      // Indian format: 1,00,000
      if (places == 0) {
        formatted = formatted.replaceAllMapped(
          RegExp(r'(\d)(?=(\d\d)+\d$)'),
          (match) => '${match[1]},',
        );
      } else {
        // For decimal values, format the integer part
        final parts = formatted.split('.');
        final integerPart = parts[0].replaceAllMapped(
          RegExp(r'(\d)(?=(\d\d)+\d$)'),
          (match) => '${match[1]},',
        );
        formatted = '$integerPart.${parts[1]}';
      }
    } else {
      // International format: 1,000,000
      final parts = formatted.split('.');
      final integerPart = _formatWithCommas(int.parse(parts[0]));
      formatted = places == 0 ? integerPart : '$integerPart.${parts[1]}';
    }

    // Add currency symbol if requested
    if (includeSymbol) {
      return '${getCurrencySymbol(effectiveCountryCode)}$formatted';
    }

    return formatted;
  }

  /// Extension method for international number formatting
  static String _formatWithCommas(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
  }

  /// Format currency with symbol and no decimal places (most common use case)
  /// Uses user's preferred currency automatically
  static Future<String> formatWithUserPreference(double value) async {
    final currencyCode = await getCurrentCurrencyCode();
    return format(
      value,
      countryCode: currencyCode,
      includeSymbol: true,
      decimalPlaces: 0,
    );
  }

  /// Format currency with symbol and no decimal places (synchronous version)
  /// Uses cached user's preferred currency
  static String formatWithUserPreferenceSync(double value) {
    return format(
      value,
      includeSymbol: true,
      decimalPlaces: 0,
    ); // Will use user preference by default
  }

  /// Format currency with symbol and appropriate decimal places
  /// Uses user's preferred currency automatically
  static Future<String> formatFinancialWithUserPreference(double value) async {
    final currencyCode = await getCurrentCurrencyCode();
    return format(
      value,
      countryCode: currencyCode,
      includeSymbol: true,
      decimalPlaces: 2,
    );
  }

  /// Format currency with symbol and appropriate decimal places (synchronous version)
  /// Uses cached user's preferred currency
  static String formatFinancialWithUserPreferenceSync(double value) {
    return format(
      value,
      includeSymbol: true,
      decimalPlaces: 2,
    ); // Will use user preference by default
  }

  /// Format currency for display in financial statements
  static String formatFinancial(double value) {
    return format(value, includeSymbol: true, decimalPlaces: 2);
  }

  /// Format currency based on country code with symbol and appropriate decimal places
  static String formatByCountry(double value, String countryCode) {
    return format(value, countryCode: countryCode, includeSymbol: true);
  }

  /// Format currency without symbol (for table columns where symbol is in header)
  static String formatAmount(double value) {
    return format(value, includeSymbol: false, decimalPlaces: 0);
  }

  /// Format currency with symbol and no decimal places (most common use case)
  static String formatRupees(double value) {
    return format(value, includeSymbol: true, decimalPlaces: 0);
  }

  /// Format currency for charts and graphs (abbreviated format)
  /// DEPRECATED: Use formatCompact() instead for better currency support
  static String formatAbbreviated(double value, {String? countryCode}) {
    return formatCompact(value, countryCode: countryCode);
  }

  /// Smart compact currency formatting that abbreviates large numbers
  ///
  /// INR uses Indian system: K (1,000), L (1,00,000), Cr (1,00,00,000), Ar (1,00,00,00,000)
  /// All other currencies use international: K (1,000), M (1,000,000), B (1,000,000,000)
  /// Numbers below 1,000 are shown in full format.
  /// Trailing .0 is dropped for cleaner display (e.g. ₹5L not ₹5.0L)
  /// Negative amounts are supported with a leading - sign.
  static String formatCompact(double value, {String? countryCode}) {
    final effectiveCountryCode = countryCode ?? getCurrentCurrencyCodeSync();
    final symbol = getCurrencySymbol(effectiveCountryCode);

    // Handle negative amounts
    final isNegative = value < 0;
    final absValue = value.abs();
    final prefix = isNegative ? '-' : '';

    String result;

    if (effectiveCountryCode == '+91') {
      // Indian number system abbreviations
      if (absValue >= 1000000000) {
        // 1 Arab (100 Crore)
        result = '$prefix$symbol${_cleanDecimal(absValue / 1000000000)}Ar';
      } else if (absValue >= 10000000) {
        // 1 Crore
        result = '$prefix$symbol${_cleanDecimal(absValue / 10000000)}Cr';
      } else if (absValue >= 100000) {
        // 1 Lakh
        result = '$prefix$symbol${_cleanDecimal(absValue / 100000)}L';
      } else {
        result = '$prefix${formatByCountry(absValue, effectiveCountryCode)}';
      }
    } else {
      // International number system abbreviations
      if (absValue >= 1000000000) {
        // 1 Billion
        result = '$prefix$symbol${_cleanDecimal(absValue / 1000000000)}B';
      } else if (absValue >= 1000000) {
        // 1 Million
        result = '$prefix$symbol${_cleanDecimal(absValue / 1000000)}M';
      } else if (absValue >= 100000) {
        // 100 Thousand +
        result = '$prefix$symbol${_cleanDecimal(absValue / 1000)}K';
      } else {
        result = '$prefix${formatByCountry(absValue, effectiveCountryCode)}';
      }
    }

    return result;
  }

  /// Format compact with country code convenience method
  static String formatByCountryCompact(double value, String countryCode) {
    return formatCompact(value, countryCode: countryCode);
  }

  /// PDF-safe compact formatting — uses ASCII-safe currency prefixes
  /// since PDF fonts often can't render ₹, €, ¥, د.إ etc.
  static String formatCompactPdfSafe(double value, {String? countryCode}) {
    final effectiveCountryCode = countryCode ?? getCurrentCurrencyCodeSync();

    // PDF-safe currency prefixes
    const Map<String, String> pdfSymbols = {
      '+1': '\$',
      '+91': 'Rs.',
      '+44': 'GBP ',
      '+61': 'A\$',
      '+81': 'JPY ',
      '+49': 'EUR ',
      '+33': 'EUR ',
      '+971': 'AED ',
      '+65': 'S\$',
    };

    final symbol = pdfSymbols[effectiveCountryCode] ?? '\$';

    // Handle negative amounts
    final isNegative = value < 0;
    final absValue = value.abs();
    final prefix = isNegative ? '-' : '';

    if (effectiveCountryCode == '+91') {
      if (absValue >= 1000000000) {
        return '$prefix$symbol${_cleanDecimal(absValue / 1000000000)}Ar';
      } else if (absValue >= 10000000) {
        return '$prefix$symbol${_cleanDecimal(absValue / 10000000)}Cr';
      } else if (absValue >= 100000) {
        return '$prefix$symbol${_cleanDecimal(absValue / 100000)}L';
      }
    } else {
      if (absValue >= 1000000000) {
        return '$prefix$symbol${_cleanDecimal(absValue / 1000000000)}B';
      } else if (absValue >= 1000000) {
        return '$prefix$symbol${_cleanDecimal(absValue / 1000000)}M';
      } else if (absValue >= 100000) {
        return '$prefix$symbol${_cleanDecimal(absValue / 1000)}K';
      }
    }

    // For small amounts, show exact with PDF-safe symbol
    final decimals = effectiveCountryCode == '+81' ? 0 : 2;
    return '$prefix$symbol${absValue.toStringAsFixed(decimals)}';
  }

  /// Helper: format number with 1 decimal, drop trailing .0
  static String _cleanDecimal(double value) {
    final formatted = value.toStringAsFixed(1);
    if (formatted.endsWith('.0')) {
      return formatted.substring(0, formatted.length - 2);
    }
    return formatted;
  }

  /// Parse formatted currency string back to double
  /// Supports parsing compact formats like "1.5K", "2.3L", "5Cr", "1.2B"
  static double? parse(String formattedString) {
    try {
      // Remove all non-numeric characters EXCEPT dots, minus signs, and known suffixes
      // First, let's normalize the string
      String clean = formattedString.trim().toUpperCase();

      // Remove known currency symbols
      clean = clean
          .replaceAll('₹', '')
          .replaceAll('\$', '')
          .replaceAll('£', '')
          .replaceAll('A\$', '')
          .replaceAll('JPY', '')
          .replaceAll('EUR', '')
          .replaceAll('€', '')
          .replaceAll('AED', '')
          .replaceAll('S\$', '')
          .replaceAll('د.إ', '')
          .replaceAll('RS.', '')
          .replaceAll('GBP', '')
          .replaceAll(',', '')
          .trim();

      double multiplier = 1.0;

      if (clean.endsWith('AR')) {
        multiplier = 1000000000.0;
        clean = clean.replaceAll('AR', '');
      } else if (clean.endsWith('CR')) {
        multiplier = 10000000.0;
        clean = clean.replaceAll('CR', '');
      } else if (clean.endsWith('C')) {
        multiplier = 10000000.0;
        clean = clean.replaceAll('C', '');
      } else if (clean.endsWith('L')) {
        multiplier = 100000.0;
        clean = clean.replaceAll('L', '');
      } else if (clean.endsWith('B')) {
        multiplier = 1000000000.0;
        clean = clean.replaceAll('B', '');
      } else if (clean.endsWith('M')) {
        multiplier = 1000000.0;
        clean = clean.replaceAll('M', '');
      } else if (clean.endsWith('K')) {
        multiplier = 1000.0;
        clean = clean.replaceAll('K', '');
      }

      return double.parse(clean.trim()) * multiplier;
    } catch (e) {
      return null;
    }
  }

  /// Validate if a string is a valid formatted currency
  static bool isValidFormat(String formattedString) {
    return parse(formattedString) != null;
  }
}
