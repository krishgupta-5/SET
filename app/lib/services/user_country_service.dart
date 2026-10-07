import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service to get user's country code from their profile
/// Used to determine appropriate currency formatting
class UserCountryService {
  // Private constructor to prevent instantiation
  UserCountryService._();

  // Static cache for immediate access
  static String? _cachedCountryCode;

  /// Get the current user's country code synchronously if cached, async otherwise
  ///
  /// Returns the country code (e.g., '+91', '+1') immediately if cached,
  /// or fetches it asynchronously and returns '+91' as default (better than USD for most users)
  static String getUserCountryCodeSync() {
    // Return cached code immediately if available
    if (_cachedCountryCode != null) {
      return _cachedCountryCode!;
    }

    // Start async fetch but return default immediately for UI
    getUserCountryCode().then((code) {
      _cachedCountryCode = code;
    });

    // Return INR as default (better than showing $ briefly for most users)
    return '+91';
  }

  /// Get the current user's country code from their profile
  ///
  /// Returns the country code (e.g., '+91', '+1') or '+91' as default
  static Future<String> getUserCountryCode() async {
    // Return cached code if available
    if (_cachedCountryCode != null) {
      return _cachedCountryCode!;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _cachedCountryCode = '+91';
        return '+91'; // Default to INR
      }

      // Try to get from companies collection first (company setup data)
      final companySnapshot = await FirebaseFirestore.instance
          .collection('companies')
          .doc(uid)
          .get();

      if (companySnapshot.exists) {
        final companyData = companySnapshot.data()!;
        String fullMobileNumber = companyData["Mobile Number"] ?? '';

        if (fullMobileNumber.isNotEmpty) {
          // Extract country code from mobile number
          int spaceIndex = fullMobileNumber.indexOf(' ');
          if (spaceIndex != -1) {
            String countryCode = fullMobileNumber.substring(0, spaceIndex);
            _cachedCountryCode = countryCode;
            return countryCode;
          }
        }
      }

      // Fallback to users collection
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.data()!;
        String phone = userData['phone'] ?? '';

        if (phone.isNotEmpty) {
          // Try to extract country code if it's in international format
          if (phone.startsWith('+')) {
            // Find the first space or extract first 2-4 digits after +
            int spaceIndex = phone.indexOf(' ');
            if (spaceIndex != -1) {
              String countryCode = phone.substring(0, spaceIndex);
              _cachedCountryCode = countryCode;
              return countryCode;
            } else {
              // Extract the country code (usually 2-4 digits after +)
              if (phone.length >= 3) {
                String potentialCode = phone.substring(0, 3);
                // Check if it's a valid country code
                if (_isValidCountryCode(potentialCode)) {
                  _cachedCountryCode = potentialCode;
                  return potentialCode;
                }
                // Try 4 digits
                if (phone.length >= 4) {
                  potentialCode = phone.substring(0, 4);
                  if (_isValidCountryCode(potentialCode)) {
                    _cachedCountryCode = potentialCode;
                    return potentialCode;
                  }
                }
              }
            }
          }
        }
      }

      // Default to INR if no country code was found
      _cachedCountryCode = '+91';
      return '+91';
    } catch (e) {
      // Default to INR on any error
      _cachedCountryCode = '+91';
      return '+91';
    }
  }

  /// Check if a country code is in our supported list
  static bool _isValidCountryCode(String code) {
    const supportedCodes = [
      '+1',
      '+91',
      '+44',
      '+61',
      '+81',
      '+49',
      '+33',
      '+971',
      '+65',
    ];
    return supportedCodes.contains(code);
  }

  /// Get cached country code (for immediate UI updates)
  /// Returns the cached code or USD default synchronously
  static String getCachedCountryCode() {
    return getUserCountryCodeSync();
  }

  /// Initialize the country code cache (call this early in app startup)
  static Future<void> initializeCache() async {
    if (_cachedCountryCode == null) {
      await getUserCountryCode();
    }
  }
}
