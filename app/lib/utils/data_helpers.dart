import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/currency_formatter.dart';

/// Helper functions for data parsing and validation
///
/// This class provides standardized methods for parsing common data types
/// throughout the application to ensure consistency and prevent crashes.
class DataHelpers {
  DataHelpers._();

  /// Safely parse dynamic values to double
  ///
  /// [value] - The dynamic value to parse (can be String, double, int, or null)
  /// Returns parsed double value, defaults to 0.0 if parsing fails
  static double safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return CurrencyFormatter.parse(value) ?? 0.0;
    }
    return 0.0;
  }

  /// Safely parse dynamic values to String
  ///
  /// [value] - The dynamic value to parse
  /// Returns string representation, defaults to empty string if null
  static String safeParseString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  /// Safely parse dynamic values to int
  ///
  /// [value] - The dynamic value to parse
  /// Returns parsed int value, defaults to 0 if parsing fails
  static int safeParseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final cleanValue = value.replaceAll(RegExp(r'[^\d]'), '');
      return int.tryParse(cleanValue) ?? 0;
    }
    return 0;
  }

  /// Safely parse date values from Firestore
  ///
  /// [value] - The date value to parse (can be Timestamp, DateTime, or null)
  /// Returns DateTime object, null if parsing fails
  static DateTime? safeParseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  /// Safely parse boolean values
  ///
  /// [value] - The dynamic value to parse
  /// Returns boolean value, defaults to false if parsing fails
  static bool safeParseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    if (value is int) {
      return value == 1;
    }
    return false;
  }

  /// Validate if a string is not empty after trimming
  ///
  /// [value] - The string to validate
  /// Returns true if string is not empty after trimming
  static bool isNotEmpty(String? value) {
    return value?.trim().isNotEmpty == true;
  }

  /// Validate email format
  ///
  /// [email] - The email string to validate
  /// Returns true if email format is valid
  static bool isValidEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  /// Format currency amount for display
  ///
  /// [amount] - The amount to format
  /// [countryCode] - Country code for currency symbol (defaults to +1 for USD)
  /// [decimalDigits] - Number of decimal places (defaults to 0)
  /// Returns formatted currency string
  static String formatCurrency(
    double amount, {
    String countryCode = '+1',
    int? decimalDigits,
  }) {
    return CurrencyFormatter.format(
      amount,
      countryCode: countryCode,
      decimalPlaces: decimalDigits,
    );
  }

  /// Format date for display
  ///
  /// [date] - The date to format
  /// [format] - Format pattern (defaults to 'dd/MM/yyyy')
  /// Returns formatted date string
  static String formatDate(DateTime? date, {String format = 'dd/MM/yyyy'}) {
    if (date == null) return 'N/A';

    switch (format.toLowerCase()) {
      case 'mmm yyyy':
        return '${_getMonthName(date.month)} ${date.year}';
      case 'mmmm':
        return _getMonthName(date.month);
      case 'dd/mm/yyyy':
      default:
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
  }

  /// Get month name from month number
  ///
  /// [month] - Month number (1-12)
  /// Returns month name
  static String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  /// Truncate text to specified length with ellipsis
  ///
  /// [text] - The text to truncate
  /// [maxLength] - Maximum length before truncation
  /// Returns truncated text with ellipsis if needed
  static String truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Generate error message for API responses
  ///
  /// [error] - The error object
  /// [fallbackMessage] - Default message if error is null
  /// Returns user-friendly error message
  static String getErrorMessage(dynamic error, String fallbackMessage) {
    if (error == null) return fallbackMessage;
    if (error is String) return error;
    if (error.toString().contains('permission-denied')) {
      return 'Permission denied. Please check your access rights.';
    }
    if (error.toString().contains('not-found')) {
      return 'Requested resource not found.';
    }
    if (error.toString().contains('timeout')) {
      return 'Request timed out. Please try again.';
    }
    return fallbackMessage;
  }
}
