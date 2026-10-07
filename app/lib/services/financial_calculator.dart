/// Centralized financial calculations for the startup expense tracker.
///
/// This service contains all core financial math operations that should
/// never be duplicated in UI components. All financial calculations
/// must go through this class to ensure consistency and audit safety.
library;

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

class FinancialCalculator {
  // Private constructor to prevent instantiation
  FinancialCalculator._();

  /// Calculate available funds from total funding and total spent
  ///
  /// [funding] - Total funding amount raised
  /// [totalSpent] - Total expenses already spent
  /// Returns available cash runway
  static double availableFunds({
    required double funding,
    required double totalSpent,
  }) {
    return funding - totalSpent;
  }

  /// Calculate runway in months based on available funds and monthly burn
  ///
  /// [availableFunds] - Available cash (funding - spent)
  /// [monthlyBurn] - Monthly burn rate (must be positive)
  /// Returns number of months of runway, 0 if burn is <= 0
  static double runwayMonths({
    required double availableFunds,
    required double monthlyBurn,
  }) {
    if (monthlyBurn <= 0) return 0;
    return availableFunds / monthlyBurn;
  }

  /// Calculate monthly burn from expense data
  ///
  /// [expenses] - List of expense maps with 'Amount' field
  /// [salaries] - Optional total salary cost for the month
  /// Returns total monthly burn (expenses + salaries)
  static double monthlyBurnFromExpenses(
    List<Map<String, dynamic>> expenses, {
    double salaries = 0.0,
  }) {
    double totalExpenses = 0.0;

    for (var expense in expenses) {
      final amount =
          double.tryParse(expense['Amount']?.toString() ?? '0') ?? 0.0;
      totalExpenses += amount;
    }

    return totalExpenses + salaries;
  }

  /// Calculate gross burn (expenses + salaries)
  ///
  /// [totalExpenses] - Total expenses for the period
  /// [salariesTotal] - Total salary costs for the period
  /// Returns gross burn amount
  static double grossBurn({
    required double totalExpenses,
    required double salariesTotal,
  }) {
    return totalExpenses + salariesTotal;
  }

  /// Calculate net burn (gross burn - revenue)
  ///
  /// [grossBurn] - Gross burn amount
  /// [revenue] - Revenue for the period
  /// Returns net burn amount
  static double netBurn({required double grossBurn, required double revenue}) {
    return grossBurn - revenue;
  }

  /// Calculate burn rate percentage relative to budget
  ///
  /// [actualBurn] - Actual burn amount
  /// [budgetedBurn] - Budgeted burn amount
  /// Returns burn rate as percentage (0-1), capped at 1.0
  static double burnRatePercentage({
    required double actualBurn,
    required double budgetedBurn,
  }) {
    if (budgetedBurn <= 0) return 0.0;
    final rate = actualBurn / budgetedBurn;
    return rate > 1.0 ? 1.0 : rate;
  }

  /// Calculate runway health status based on months remaining
  ///
  /// [runwayMonths] - Number of months of runway
  /// Returns health status string
  static String runwayHealthStatus(double runwayMonths) {
    if (runwayMonths >= 12) return 'Excellent';
    if (runwayMonths >= 9) return 'Good';
    if (runwayMonths >= 6) return 'Fair';
    if (runwayMonths >= 3) return 'Concerning';
    return 'Critical';
  }

  /// Calculate variance from budget
  ///
  /// [actual] - Actual amount spent
  /// [budgeted] - Budgeted amount
  /// Returns variance amount (positive = over budget, negative = under budget)
  static double budgetVariance({
    required double actual,
    required double budgeted,
  }) {
    return actual - budgeted;
  }

  /// Calculate variance percentage from budget
  ///
  /// [actual] - Actual amount spent
  /// [budgeted] - Budgeted amount
  /// Returns variance as percentage (positive = over budget)
  static double budgetVariancePercentage({
    required double actual,
    required double budgeted,
  }) {
    if (budgeted <= 0) return 0.0;
    return ((actual - budgeted) / budgeted) * 100;
  }

  /// Calculate current month burn with proper recurring expense handling
  ///
  /// [expenses] - List of expense maps with 'amount', 'date', 'type' fields
  /// Returns current month burn including recurring expenses that started before now
  static double currentMonthBurn(List<Map<String, dynamic>> expenses) {
    if (expenses.isEmpty) return 0;

    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;

    double total = 0;

    for (var expense in expenses) {
      final type = expense['type'] ?? 'one_time';
      final amount = expense['amount'] as double? ?? 0.0;
      final Timestamp? ts = expense['date'];

      if (type == 'recurring' || type == 'subscription') {
        final startDate = ts?.toDate();
        final frequency =
            expense['recurrenceFrequency'] as String? ?? 'monthly';
        final tenureMonths = expense['recurringTenureMonths'] as int?;

        if (startDate != null &&
            (startDate.isBefore(now) || startDate.isAtSameMomentAs(now))) {
          if (tenureMonths != null) {
            final endDate = DateTime(
              startDate.year,
              startDate.month + tenureMonths,
              startDate.day,
            );
            if (now.isAfter(endDate)) {
              continue;
            }
          }

          double monthlyAmount = amount;
          if (frequency == 'weekly') {
            monthlyAmount = amount * 4.33;
          } else if (frequency == 'daily') {
            monthlyAmount = amount * 30.44;
          } else if (frequency == 'yearly') {
            monthlyAmount = amount / 12.0;
          }
          total += monthlyAmount;
        }
      } else {
        final dt = ts?.toDate();
        if (dt != null && dt.month == currentMonth && dt.year == currentYear) {
          total += amount;
        }
      }
    }

    return total;
  }

  /// Calculate rolling average monthly burn (last 3 months)
  ///
  /// [expenses] - List of expense maps with 'amount', 'date', 'type' fields
  /// Returns average burn over last 3 months, or 0 if no data
  static double rollingAverageMonthlyBurn(List<Map<String, dynamic>> expenses) {
    if (expenses.isEmpty) return 0;

    Map<String, double> monthlyTotals = {};

    for (var expense in expenses) {
      final expenseDate = expense['date'] as Timestamp?;
      if (expenseDate != null) {
        final expenseDateTime = expenseDate.toDate();
        final monthKey =
            "${expenseDateTime.year}-${expenseDateTime.month.toString().padLeft(2, '0')}";

        if (!monthlyTotals.containsKey(monthKey)) {
          monthlyTotals[monthKey] = 0;
        }

        // Add both one-time and recurring expenses
        monthlyTotals[monthKey] =
            monthlyTotals[monthKey]! + (expense['amount'] as double? ?? 0.0);
      }
    }

    if (monthlyTotals.isEmpty) return 0;

    // Sort months newest first and take last 3 months only
    final sortedKeys = monthlyTotals.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final recentKeys = sortedKeys.take(3);

    if (recentKeys.isEmpty) return 0;

    double total = 0;
    for (var key in recentKeys) {
      total += monthlyTotals[key]!;
    }

    return total / recentKeys.length;
  }

  /// Get real monthly burn with fallback strategy
  ///
  /// [expenses] - List of expense maps
  /// Returns current month burn, or rolling average if current is 0
  static double getRealMonthlyBurn(List<Map<String, dynamic>> expenses) {
    double burn = currentMonthBurn(expenses);
    if (burn == 0) {
      burn = rollingAverageMonthlyBurn(expenses);
    }
    return burn;
  }

  /// Calculate percentage of amount relative to total
  ///
  /// [amount] - The amount to calculate percentage for
  /// [total] - The total amount to calculate percentage against
  /// Returns percentage as integer (0-100), rounded to nearest whole number
  static int calculatePercentage({
    required double amount,
    required double total,
  }) {
    if (total <= 0) return 0;
    return ((amount / total) * 100).round();
  }

  /// Calculate EMI for a Flat (Fixed) interest rate loan
  ///
  /// [principal] - Loan amount
  /// [annualRatePercent] - Annual interest rate in percent (e.g., 12.0 for 12%)
  /// [tenureMonths] - Number of months to repay the loan
  static double calculateFlatRateEmi(
    double principal,
    double annualRatePercent,
    int tenureMonths,
  ) {
    if (tenureMonths <= 0 || principal <= 0) return 0.0;
    final totalInterest =
        principal * (annualRatePercent / 100) * (tenureMonths / 12);
    return (principal + totalInterest) / tenureMonths;
  }

  /// Calculate EMI for a Reducing interest rate loan
  ///
  /// [principal] - Loan amount
  /// [annualRatePercent] - Annual interest rate in percent (e.g., 12.0 for 12%)
  /// [tenureMonths] - Number of months to repay the loan
  static double calculateReducingRateEmi(
    double principal,
    double annualRatePercent,
    int tenureMonths,
  ) {
    if (tenureMonths <= 0 || principal <= 0) return 0.0;
    if (annualRatePercent <= 0) return principal / tenureMonths;

    final monthlyRate = (annualRatePercent / 12) / 100;
    final powFactor = math.pow(1 + monthlyRate, tenureMonths);

    return (principal * monthlyRate * powFactor) / (powFactor - 1);
  }
}
