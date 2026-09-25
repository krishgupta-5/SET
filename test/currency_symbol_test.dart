import 'package:flutter_test/flutter_test.dart';
import 'package:startup_expense_tracker/services/currency_formatter.dart';

void main() {
  group('Currency Symbol Tests', () {
    test(
      'should return correct currency symbols for all supported countries',
      () {
        // Test all supported country codes
        expect(CurrencyFormatter.getCurrencySymbol('+1'), equals('\$')); // USD
        expect(CurrencyFormatter.getCurrencySymbol('+91'), equals('₹')); // INR
        expect(CurrencyFormatter.getCurrencySymbol('+44'), equals('£')); // GBP
        expect(
          CurrencyFormatter.getCurrencySymbol('+61'),
          equals('A\$'),
        ); // AUD
        expect(CurrencyFormatter.getCurrencySymbol('+81'), equals('¥')); // JPY
        expect(CurrencyFormatter.getCurrencySymbol('+49'), equals('€')); // EUR
        expect(CurrencyFormatter.getCurrencySymbol('+33'), equals('€')); // EUR
        expect(
          CurrencyFormatter.getCurrencySymbol('+971'),
          equals('د.إ'),
        ); // AED
        expect(
          CurrencyFormatter.getCurrencySymbol('+65'),
          equals('S\$'),
        ); // SGD
      },
    );

    test('should default to USD for unknown country codes', () {
      expect(CurrencyFormatter.getCurrencySymbol('+999'), equals('\$'));
      expect(CurrencyFormatter.getCurrencySymbol(''), equals('\$'));
    });

    test('should format currency with correct symbols', () {
      final amount = 1000.00;

      expect(
        CurrencyFormatter.formatByCountry(amount, '+1'),
        equals('\$1,000.00'),
      ); // USD
      expect(
        CurrencyFormatter.formatByCountry(amount, '+91'),
        equals('₹1,000.00'),
      ); // INR
      expect(
        CurrencyFormatter.formatByCountry(amount, '+44'),
        equals('£1,000.00'),
      ); // GBP
      expect(
        CurrencyFormatter.formatByCountry(amount, '+61'),
        equals('A\$1,000.00'),
      ); // AUD
      expect(
        CurrencyFormatter.formatByCountry(amount, '+81'),
        equals('¥1,000'),
      ); // JPY (no decimals)
      expect(
        CurrencyFormatter.formatByCountry(amount, '+49'),
        equals('€1,000.00'),
      ); // EUR
      expect(
        CurrencyFormatter.formatByCountry(amount, '+33'),
        equals('€1,000.00'),
      ); // EUR
      expect(
        CurrencyFormatter.formatByCountry(amount, '+971'),
        equals('د.إ1,000.00'),
      ); // AED
      expect(
        CurrencyFormatter.formatByCountry(amount, '+65'),
        equals('S\$1,000.00'),
      ); // SGD
    });
  });
}
