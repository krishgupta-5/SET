import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'user_country_service.dart';

/// Service to manage user's currency preference
/// Handles storing, retrieving, and updating currency selection
class CurrencyPreferenceService {
  // Private constructor to prevent instantiation
  CurrencyPreferenceService._();

  static final ValueNotifier<String> _currencyNotifier = ValueNotifier('+1');

  /// Stream of currency changes for UI updates
  static ValueNotifier<String> get currencyNotifier => _currencyNotifier;

  /// Get the current user's preferred currency code
  /// Falls back to country code if no preference is set
  static Future<String> getCurrencyPreference() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('CurrencyPreference: No user logged in, returning +1');
        }
        return '+1';
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final userData = doc.data();
        final preferredCurrency = userData?['preferredCurrency'] as String?;

        if (kDebugMode) {
          print(
            'CurrencyPreference: Found preferredCurrency: $preferredCurrency',
          );
        }

        if (preferredCurrency != null && preferredCurrency.isNotEmpty) {
          if (kDebugMode) {
            print(
              'CurrencyPreference: Returning preferred currency: $preferredCurrency',
            );
          }
          return preferredCurrency;
        }
      }

      // Fallback to country code
      final countryCode = await UserCountryService.getUserCountryCode();
      if (kDebugMode) {
        print('CurrencyPreference: Falling back to country code: $countryCode');
      }
      return countryCode;
    } catch (e) {
      if (kDebugMode) print('CurrencyPreference: Error getting preference: $e');
      return '+1';
    }
  }

  /// Get currency preference synchronously (returns cached value)
  static String getCurrencyPreferenceSync() {
    return _currencyNotifier.value;
  }

  /// Initialize the currency preference cache
  static Future<void> initialize() async {
    if (kDebugMode) {
      print(
        'CurrencyPreference: Initializing cache, current value: ${_currencyNotifier.value}',
      );
    }

    // Only initialize if the current value is the default (+1)
    if (_currencyNotifier.value == '+1') {
      if (kDebugMode) {
        print(
          'CurrencyPreference: Loading from Firestore (current is default)',
        );
      }
      final currency = await getCurrencyPreference();
      _currencyNotifier.value = currency;
      if (kDebugMode) {
        print('CurrencyPreference: Cache initialized to: $currency');
      }
    } else {
      if (kDebugMode) {
        print(
          'CurrencyPreference: Skipping initialization, already has value: ${_currencyNotifier.value}',
        );
      }
    }
  }

  /// Update user's currency preference
  static Future<bool> updateCurrencyPreference(String countryCode) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) print('No user logged in');
        return false;
      }

      if (kDebugMode) print('Updating currency preference to: $countryCode');

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'preferredCurrency': countryCode,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Update the notifier to trigger UI updates
      _currencyNotifier.value = countryCode;

      if (kDebugMode) {
        print('Currency preference updated successfully to: $countryCode');
      }
      if (kDebugMode) print('Notifier value now: ${_currencyNotifier.value}');

      return true;
    } catch (e) {
      if (kDebugMode) print('Error updating currency preference: $e');
      return false;
    }
  }

  /// Get available currencies for selection
  static List<Map<String, String>> getAvailableCurrencies() {
    return [
      {'code': '+1', 'name': 'USD - US Dollar', 'symbol': '\$'},
      {'code': '+91', 'name': 'INR - Indian Rupee', 'symbol': '₹'},
      {'code': '+44', 'name': 'GBP - British Pound', 'symbol': '£'},
      {'code': '+61', 'name': 'AUD - Australian Dollar', 'symbol': 'A\$'},
      {'code': '+81', 'name': 'JPY - Japanese Yen', 'symbol': '¥'},
      {'code': '+49', 'name': 'EUR - Euro (Germany)', 'symbol': '€'},
      {'code': '+33', 'name': 'EUR - Euro (France)', 'symbol': '€'},
      {'code': '+971', 'name': 'AED - UAE Dirham', 'symbol': 'د.إ'},
      {'code': '+65', 'name': 'SGD - Singapore Dollar', 'symbol': 'S\$'},
    ];
  }

  /// Get currency display name from code
  static String getCurrencyDisplayName(String countryCode) {
    final currencies = getAvailableCurrencies();
    final currency = currencies.firstWhere(
      (c) => c['code'] == countryCode,
      orElse: () => {'code': '+1', 'name': 'USD - US Dollar', 'symbol': '\$'},
    );
    return currency['name']!;
  }

  /// Get currency symbol from code
  static String getCurrencySymbol(String countryCode) {
    final currencies = getAvailableCurrencies();
    final currency = currencies.firstWhere(
      (c) => c['code'] == countryCode,
      orElse: () => {'code': '+1', 'name': 'USD - US Dollar', 'symbol': '\$'},
    );
    return currency['symbol']!;
  }
}
