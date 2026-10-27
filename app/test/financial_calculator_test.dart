import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startup_expense_tracker/services/financial_calculator.dart';
import 'package:startup_expense_tracker/utils/expense_expansion_helper.dart';

Timestamp _ts(int y, int m, int d) => Timestamp.fromDate(DateTime(y, m, d));

void main() {
  // Fixed "today" so results don't depend on when the suite runs.
  final now = DateTime(2026, 10, 15, 12);

  group('FinancialCalculator.compute', () {
    test('ignores funding rows and future-dated one-time expenses', () {
      final s = FinancialCalculator.compute(
        now: now,
        funding: 100000,
        rawExpenses: [
          {'id': 'a', 'Amount': 1000, 'Date': _ts(2026, 10, 1), 'Category': 'software'},
          {'id': 'f', 'Amount': 50000, 'Date': _ts(2026, 10, 2), 'isFunding': true},
          {'id': 'b', 'Amount': 500, 'Date': _ts(2026, 9, 10), 'Category': 'office'},
        ],
      );
      expect(s.totalSpent, 1500);
      expect(s.availableFunds, 98500);
      expect(s.monthlyBurn, 1000);
      expect(s.isBurnEstimated, isFalse);
    });

    test('recurring charge later this month counts in burn, not in spent', () {
      final s = FinancialCalculator.compute(
        now: now,
        funding: 10000,
        rawExpenses: [
          // Monthly, started Aug 25 → occurrences Aug 25, Sep 25, Oct 25.
          {
            'id': 'r',
            'Amount': 300,
            'Date': _ts(2026, 8, 25),
            'Type': 'recurring',
            'recurrenceFrequency': 'monthly',
          },
        ],
      );
      expect(s.totalSpent, 600); // Aug + Sep only; Oct 25 hasn't happened yet
      expect(s.monthlyBurn, 300); // Oct occurrence is committed this month
    });

    test('unpaid active salaries are added to burn; paid ones are not doubled', () {
      final s = FinancialCalculator.compute(
        now: now,
        funding: 100000,
        rawExpenses: [
          {
            'id': 'p1',
            'Amount': 4000,
            'Date': _ts(2026, 10, 5),
            'Category': 'salary',
            'memberId': 'm1',
          },
        ],
        members: [
          {'id': 'm1', 'monthlyCost': 4000, 'status': 'Active'},
          {'id': 'm2', 'monthlyCost': 3000, 'status': 'Active'},
          {'id': 'm3', 'monthlyCost': 9999, 'status': 'Paused'},
        ],
      );
      expect(s.unpaidPayroll, 3000);
      expect(s.monthlyBurn, 7000);
      expect(s.categoryBreakdown['salary'], 7000);
    });

    test('net burn subtracts this month revenue and drives runway', () {
      final s = FinancialCalculator.compute(
        now: now,
        funding: 50000,
        rawExpenses: [
          {'id': 'a', 'Amount': 10000, 'Date': _ts(2026, 10, 1)},
        ],
        revenue: [
          {'Amount': 4000, 'Date': _ts(2026, 10, 3)},
          {'Amount': 99999, 'Date': _ts(2026, 9, 3)}, // other month ignored
        ],
      );
      expect(s.monthlyRevenue, 4000);
      expect(s.netBurn, 6000);
      expect(s.availableFunds, 40000);
      expect(s.runwayMonths, closeTo(40000 / 6000, 1e-9));
    });

    test('profitable company gets the sentinel runway', () {
      final s = FinancialCalculator.compute(
        now: now,
        funding: 50000,
        rawExpenses: [
          {'id': 'a', 'Amount': 1000, 'Date': _ts(2026, 10, 1)},
        ],
        revenue: [
          {'Amount': 5000, 'Date': _ts(2026, 10, 2)},
        ],
      );
      expect(s.isProfitable, isTrue);
      expect(s.runwayMonths, kProfitableRunwayMonths);
    });

    test('falls back to last-3-month average when this month is empty', () {
      final s = FinancialCalculator.compute(
        now: now,
        funding: 100000,
        rawExpenses: [
          {'id': 'a', 'Amount': 3000, 'Date': _ts(2026, 9, 1)},
          {'id': 'b', 'Amount': 6000, 'Date': _ts(2026, 8, 1)},
          {'id': 'c', 'Amount': 9000, 'Date': _ts(2026, 7, 1)},
          {'id': 'd', 'Amount': 100000, 'Date': _ts(2026, 1, 1)}, // too old
        ],
      );
      expect(s.isBurnEstimated, isTrue);
      expect(s.monthlyBurn, 6000);
    });

    test('no funding left or no data gives zero runway', () {
      final empty = FinancialCalculator.compute(
        now: now,
        funding: 1000,
        rawExpenses: const [],
      );
      expect(empty.runwayMonths, 0);

      final depleted = FinancialCalculator.compute(
        now: now,
        funding: 100,
        rawExpenses: [
          {'id': 'a', 'Amount': 500, 'Date': _ts(2026, 10, 1)},
        ],
      );
      expect(depleted.availableFunds, -400);
      expect(depleted.runwayMonths, 0);
    });
  });

  group('ExpenseExpansionHelper', () {
    Map<String, dynamic> monthly({
      int? tenure,
      List<int>? skipped,
    }) => {
      'id': 'r',
      'Amount': 100,
      'Date': _ts(2026, 7, 1),
      'Type': 'recurring',
      'recurrenceFrequency': 'monthly',
      'recurringTenureMonths': ?tenure,
      'skippedOccurrences': ?skipped,
    };

    test('tenure yields exactly that many occurrences', () {
      final out = ExpenseExpansionHelper.expandExpenses(
        [monthly(tenure: 3)],
        maxDate: DateTime(2027, 1, 1),
        allowFuture: true,
        now: now,
      );
      expect(out.length, 3);
      expect(out.map((e) => e['virtualIndex']), [0, 1, 2]);
    });

    test('skipped occurrences are removed but indices stay stable', () {
      final out = ExpenseExpansionHelper.expandExpenses(
        [monthly(skipped: [1])],
        maxDate: now,
        now: now,
      );
      // Jul, Aug, Sep, Oct (Oct 1 <= Oct 15) minus Aug.
      expect(out.map((e) => e['virtualIndex']), [0, 2, 3]);
      expect(out.map((e) => e['id']), ['r_0', 'r_2', 'r_3']);
    });

    test('legacy EMI rows use loanTenureMonths as the tenure', () {
      final out = ExpenseExpansionHelper.expandExpenses(
        [
          {
            'id': 'emi',
            'Amount': 50,
            'Date': _ts(2026, 9, 1),
            'Type': 'recurring',
            'loanTenureMonths': 2,
          },
        ],
        maxDate: DateTime(2027, 12, 1),
        allowFuture: true,
        now: now,
      );
      expect(out.length, 2);
    });

    test('monthly series on the 31st clamps instead of skipping months', () {
      final out = ExpenseExpansionHelper.expandExpenses(
        [
          {
            'id': 'r31',
            'Amount': 1,
            'Date': _ts(2026, 1, 31),
            'Type': 'recurring',
            'recurrenceFrequency': 'monthly',
          },
        ],
        maxDate: DateTime(2026, 5, 1),
        now: DateTime(2026, 5, 1),
      );
      final dates = out.map((e) => (e['Date'] as Timestamp).toDate()).toList();
      expect(dates, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });
  });

  group('salary payments', () {
    // Exactly what ExpenseService.recordSalaryPayment writes.
    Map<String, dynamic> payment(String id, int month) => {
      'id': id,
      'Amount': 50000,
      'Category': 'salary',
      'Type': 'recurring',
      'ExpenseType': 'member',
      'memberId': 'm1',
      'Date': _ts(2026, month, 5),
    };

    test('each payment counts once, not every month after', () {
      final s = FinancialCalculator.compute(
        now: now,
        funding: 1000000,
        rawExpenses: [payment('p8', 8), payment('p9', 9), payment('p10', 10)],
        members: [
          {'id': 'm1', 'monthlyCost': 50000, 'status': 'Active'},
        ],
      );
      expect(s.totalSpent, 150000);
      expect(s.monthlyBurn, 50000);
      expect(s.unpaidPayroll, 0);
    });

    test('a salary schedule with a frequency still repeats', () {
      final out = ExpenseExpansionHelper.expandExpenses(
        [
          {...payment('s', 8), 'recurrenceFrequency': 'monthly'},
        ],
        now: now,
      );
      expect(out.length, 3);
    });
  });
}
