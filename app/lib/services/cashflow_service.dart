import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/expense_expansion_helper.dart';
import 'currency_formatter.dart';

/// Service for period-based cash flow calculations
///
/// Provides production-grade cash flow analysis with proper time filtering,
/// category breakdowns, and trend analysis for investor reporting.
class CashflowService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get cash flow breakdown for a specific period
  ///
  /// [period] - 'current_month', 'last_month', 'last_quarter', 'last_6_months', 'last_year'
  /// Returns categorized cash flow data with inflows, outflows, and net flow
  static Future<Map<String, dynamic>> getCashFlowForPeriod(
    String period,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      final dateRange = _getDateRange(period);
      final expenses = await _getExpensesForDateRange(
        user.uid,
        dateRange['start']!,
        dateRange['end']!,
      );

      // Process expenses by category
      final Map<String, double> categoryTotals = {};
      double totalExpenses = 0;

      for (final data in expenses) {
        if (data['isFunding'] == true) continue;

        final amount = double.tryParse(data['Amount']?.toString() ?? '0') ?? 0;
        final category = data['Category']?.toString() ?? 'Other';

        categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
        totalExpenses += amount;
      }

      // Convert to list format for UI
      final cashFlowBreakdown = categoryTotals.entries.map((entry) {
        String category = entry.key;
        if (category.isNotEmpty) {
          category = category[0].toUpperCase() + category.substring(1);
        }
        return {
          'category': category,
          'amount': -entry.value.abs(), // Convert to negative for expenses
          'percentage': totalExpenses > 0
              ? (entry.value / totalExpenses) * 100
              : 0,
        };
      }).toList();

      // Sort by amount (highest first)
      cashFlowBreakdown.sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double),
      );

      return {
        'period': period,
        'dateRange': dateRange,
        'totalExpenses': totalExpenses,
        'categoryBreakdown': cashFlowBreakdown,
        'transactionCount': expenses.length,
        'averageTransaction': expenses.isNotEmpty
            ? totalExpenses / expenses.length
            : 0,
      };
    } catch (e) {
      throw Exception('Failed to get cash flow for period: $e');
    }
  }

  /// Get cash flow trend data for multiple periods
  ///
  /// [periods] - List of periods to include in trend analysis
  /// Returns comparative cash flow data across periods
  static Future<List<Map<String, dynamic>>> getCashFlowTrend(
    List<String> periods,
  ) async {
    final List<Map<String, dynamic>> trendData = [];

    for (String period in periods) {
      try {
        final periodData = await getCashFlowForPeriod(period);
        trendData.add(periodData);
      } catch (e) {
        // Add empty data for failed periods
        trendData.add({
          'period': period,
          'totalExpenses': 0.0,
          'categoryBreakdown': [],
          'transactionCount': 0,
          'error': e.toString(),
        });
      }
    }

    return trendData;
  }

  /// Get monthly cash flow for the last N months
  ///
  /// [months] - Number of months to include (default: 6)
  /// Returns monthly cash flow data with trend analysis
  static Future<List<Map<String, dynamic>>> getMonthlyCashFlowTrend({
    int months = 6,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final List<Map<String, dynamic>> monthlyData = [];
    final now = DateTime.now();

    for (int i = months - 1; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final endOfMonth = DateTime(now.year, now.month - i + 1, 0, 23, 59, 59);

      try {
        final expenses = await _getExpensesForDateRange(
          user.uid,
          month,
          endOfMonth,
        );

        double totalExpenses = 0;
        final Map<String, double> categoryTotals = {};

        for (final data in expenses) {
          if (data['isFunding'] == true) continue;

          final amount =
              double.tryParse(data['Amount']?.toString() ?? '0') ?? 0;
          final category = data['Category']?.toString() ?? 'Other';

          categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
          totalExpenses += amount;
        }

        monthlyData.add({
          'month': _getMonthAbbreviation(month.month),
          'year': month.year,
          'totalExpenses': totalExpenses,
          'categoryBreakdown': categoryTotals,
          'transactionCount': expenses.length,
          'isCurrentMonth': i == 0,
        });
      } catch (e) {
        monthlyData.add({
          'month': _getMonthAbbreviation(month.month),
          'year': month.year,
          'totalExpenses': 0.0,
          'categoryBreakdown': {},
          'transactionCount': 0,
          'error': e.toString(),
          'isCurrentMonth': i == 0,
        });
      }
    }

    return monthlyData;
  }

  /// Get cash flow comparison between current and previous period
  ///
  /// [period] - Period type for comparison ('month', 'quarter', 'year')
  /// Returns comparative analysis with variance calculations
  static Future<Map<String, dynamic>> getCashFlowComparison(
    String period,
  ) async {
    try {
      final currentPeriod = 'current_$period';
      final previousPeriod = 'previous_$period';

      final currentData = await getCashFlowForPeriod(currentPeriod);
      final previousData = await getCashFlowForPeriod(previousPeriod);

      final currentTotal = currentData['totalExpenses'] as double;
      final previousTotal = previousData['totalExpenses'] as double;

      final variance = currentTotal - previousTotal;
      final variancePercentage = previousTotal > 0
          ? (variance / previousTotal) * 100
          : 0;

      return {
        'currentPeriod': currentData,
        'previousPeriod': previousData,
        'variance': variance,
        'variancePercentage': variancePercentage,
        'trend': variance > 0
            ? 'increasing'
            : variance < 0
            ? 'decreasing'
            : 'stable',
      };
    } catch (e) {
      throw Exception('Failed to get cash flow comparison: $e');
    }
  }

  /// Get top spending categories for a period
  ///
  /// [period] - Period to analyze
  /// [limit] - Maximum number of categories to return (default: 10)
  /// Returns top categories by spending amount
  static Future<List<Map<String, dynamic>>> getTopCategories(
    String period, {
    int limit = 10,
  }) async {
    try {
      final periodData = await getCashFlowForPeriod(period);
      final breakdown =
          periodData['categoryBreakdown'] as List<Map<String, dynamic>>;

      // Sort by amount (highest first) and limit
      breakdown.sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double),
      );

      return breakdown
          .take(limit)
          .map(
            (category) => {
              ...category,
              'formattedAmount': CurrencyFormatter.formatRupees(
                -(category['amount'] as double),
              ),
            },
          )
          .toList();
    } catch (e) {
      throw Exception('Failed to get top categories: $e');
    }
  }

  /// Get expenses for a specific date range, expanding recurring expenses dynamically
  static Future<List<Map<String, dynamic>>> _getExpensesForDateRange(
    String uid,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final snapshot = await _firestore
        .collection('expenses')
        .where('uid', isEqualTo: uid)
        .get();

    final mappedExpenses = snapshot.docs.map((doc) {
      final data = doc.data();
      return {...data, 'id': doc.id};
    }).toList();

    final expanded = ExpenseExpansionHelper.expandExpenses(
      mappedExpenses,
      maxDate: endDate,
    );

    // Filter by the date range
    return expanded.where((expense) {
      final dateVal = expense['Date'] ?? expense['date'];
      DateTime? dt;
      if (dateVal is Timestamp) {
        dt = dateVal.toDate();
      } else if (dateVal is DateTime) {
        dt = dateVal;
      }
      if (dt == null) return false;
      return dt.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
          dt.isBefore(endDate.add(const Duration(seconds: 1)));
    }).toList();
  }

  /// Get date range for a given period
  static Map<String, DateTime> _getDateRange(String period) {
    final now = DateTime.now();

    switch (period) {
      case 'current_month':
        return {
          'start': DateTime(now.year, now.month, 1),
          'end': DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        };
      case 'previous_month':
        final prevMonth = DateTime(now.year, now.month - 1, 1);
        return {
          'start': prevMonth,
          'end': DateTime(now.year, now.month, 0, 23, 59, 59),
        };
      case 'current_quarter':
        final quarter = ((now.month - 1) ~/ 3) + 1;
        final quarterStart = DateTime(now.year, (quarter - 1) * 3 + 1, 1);
        final quarterEnd = DateTime(now.year, quarter * 3, 0, 23, 59, 59);
        return {'start': quarterStart, 'end': quarterEnd};
      case 'previous_quarter':
        final prevQuarter = ((now.month - 1) ~/ 3);
        final prevQuarterStart = DateTime(
          now.year,
          (prevQuarter - 1) * 3 + 1,
          1,
        );
        final prevQuarterEnd = DateTime(
          now.year,
          prevQuarter * 3,
          0,
          23,
          59,
          59,
        );
        return {'start': prevQuarterStart, 'end': prevQuarterEnd};
      case 'last_6_months':
        return {
          'start': DateTime(now.year, now.month - 6, 1),
          'end': DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        };
      case 'last_year':
        return {
          'start': DateTime(now.year - 1, now.month, now.day),
          'end': DateTime(now.year, now.month, now.day, 23, 59, 59),
        };
      default:
        throw ArgumentError('Unsupported period: $period');
    }
  }

  /// Get month abbreviation
  static String _getMonthAbbreviation(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
