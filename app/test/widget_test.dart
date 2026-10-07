// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:startup_expense_tracker/main.dart';

void main() {
  testWidgets('Financial Dashboard smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FinancialDashboardApp());

    // Verify that the dashboard loads with key elements
    expect(find.text('Financial Health'), findsOneWidget);
    expect(find.text('overview'), findsOneWidget);
    expect(find.text('Total Funds'), findsOneWidget);
    expect(find.text('Monthly Burn'), findsOneWidget);
    expect(find.text('AI INSIGHTS 🧁'), findsOneWidget);
    expect(find.text('KEY METRICS'), findsOneWidget);
    expect(find.text('QUICK ALERTS'), findsOneWidget);
    expect(find.text('QUICK ACCESS'), findsOneWidget);

    // Verify bottom navigation elements
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('CARDS'), findsOneWidget);
    expect(find.text('REWARDS'), findsOneWidget);
    expect(find.text('MORE'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
  });
}
