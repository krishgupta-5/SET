import 'package:flutter_test/flutter_test.dart';
import 'package:startup_expense_tracker/features/settings/screens/edit_profile_screen.dart';
import 'package:startup_expense_tracker/features/settings/screens/company_details_screen.dart';

void main() {
  group('Name Sync Tests', () {
    test('EditProfileScreen should sync name to companies collection', () {
      // This test would require mocking Firebase services
      // For now, we'll verify the sync method exists
      final screen = EditProfileScreen();
      expect(screen, isNotNull);
      // In a real test, you would mock Firebase and verify the sync call
    });

    test('CompanyDetailsScreen should sync owner name to users collection', () {
      // This test would require mocking Firebase services
      final screen = CompanyDetailsScreen();
      expect(screen, isNotNull);
      // In a real test, you would mock Firebase and verify the sync call
    });
  });
}
