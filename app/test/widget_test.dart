// Smoke test for the brand mark. The full app needs Firebase, so it is not
// pumped here; screens are covered by their own tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:startup_expense_tracker/theme/rx_colors.dart';
import 'package:startup_expense_tracker/widgets/rx_logo.dart';

void main() {
  testWidgets('RunwayX wordmark renders in light and dark', (tester) async {
    for (final ext in const [RxColors.light, RxColors.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [ext]),
          home: const Scaffold(body: Center(child: RxWordmark())),
        ),
      );
      expect(find.text('RunwayX'), findsOneWidget);
      expect(find.byType(RxLogo), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
