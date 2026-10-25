/// Centralized financial calculations for the startup expense tracker.
///
/// This service contains all core financial math operations that should
/// never be duplicated in UI components. All financial calculations
/// must go through this class to ensure consistency and audit safety.
library;

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/expense_expansion_helper.dart';

/// Runway value used when the company is profitable (revenue >= burn).
/// UIs render anything above 120 months as "10+ years".
const double kProfitableRunwayMonths = 999;

/// One consistent view of the company's finances. Every screen that shows
/// burn, spend, balance or runway must read from this so the numbers match.
///
/// Definitions:
/// - [totalSpent]: actual outflow to date (occurrences dated <= now).
/// - [monthlyBurn]: gross burn for the current calendar month = expenses
///   dated this month (including recurring charges scheduled later this
///   month) + active members' salaries not yet paid this month. If that is 0,
///   falls back to the average of the last 3 months with spend
///   ([isBurnEstimated] = true).
/// - [netBurn]: [monthlyBurn] - this month's revenue.
/// - [runwayMonths]: [availableFunds] / [netBurn]. 0 when there is no cash or
///   no burn data, [kProfitableRunwayMonths] when net burn <= 0.
class FinancialSnapshot {
  const FinancialSnapshot({
    required this.funding,
    required this.totalSpent,
    required this.availableFunds,
    required this.currentMonthExpenses,
    required this.unpaidPayroll,
    required this.monthlyBurn,
    required this.monthlyRevenue,
    required this.netBurn,
    required this.runwayMonths,
    required this.isBurnEstimated,
    required this.last30DaysSpend,
    required this.categoryBreakdown,
    required this.expenses,
  });

  final double funding;
  final double totalSpent;
  final double availableFunds;
  final double currentMonthExpenses;
  final double unpaidPayroll;
  final double monthlyBurn;
  final double monthlyRevenue;
  final double netBurn;
  final double runwayMonths;
  final bool isBurnEstimated;
  final double last30DaysSpend;

  /// Current-month burn by lowercase category. Unpaid payroll is under
  /// 'salary'. Sums to [monthlyBurn] unless [isBurnEstimated].
  final Map<String, double> categoryBreakdown;

  /// Expanded, non-funding expense occurrences up to the end of this month.
  final List<Map<String, dynamic>> expenses;

  bool get isProfitable => monthlyBurn > 0 && netBurn <= 0;
}

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

  // ---------------------------------------------------------------------------
  // Single source of truth for burn / spend / runway
  // ---------------------------------------------------------------------------

  static double _num(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(RegExp(r'[^\d.-]'), '')) ?? 0.0;
    }
    return 0.0;
  }

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  /// Builds the [FinancialSnapshot] from raw Firestore data.
  ///
  /// [rawExpenses] - expense docs as maps (doc id under 'id'); funding rows
  ///   (`isFunding == true`) are ignored, recurring templates are expanded.
  /// [members] - member docs as maps (doc id under 'id'); active members'
  ///   `monthlyCost` counts toward burn until a salary payment for them is
  ///   recorded this month.
  /// [revenue] - revenue docs as maps with `Amount` and `Date`.
  static FinancialSnapshot compute({
    required double funding,
    required List<Map<String, dynamic>> rawExpenses,
    List<Map<String, dynamic>> members = const [],
    List<Map<String, dynamic>> revenue = const [],
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final endOfMonth = DateTime(ref.year, ref.month + 1, 0, 23, 59, 59);
    final thirtyDaysAgo = ref.subtract(const Duration(days: 30));

    final expanded = ExpenseExpansionHelper.expandExpenses(
      rawExpenses.where((e) => e['isFunding'] != true).toList(),
      maxDate: endOfMonth,
      allowFuture: true,
      now: ref,
    );

    double totalSpent = 0;
    double currentMonthExpenses = 0;
    double last30 = 0;
    final monthly = <String, double>{};
    final categories = <String, double>{};
    final paidMembersThisMonth = <String>{};
    final normalized = <Map<String, dynamic>>[];

    for (final e in expanded) {
      final amount = _num(e['Amount'] ?? e['amount']);
      final dt = _date(e['Date'] ?? e['date']);
      final category = (e['Category'] ?? e['category'] ?? 'others')
          .toString()
          .toLowerCase()
          .trim();

      normalized.add({
        ...e,
        'amount': amount,
        'date': dt != null ? Timestamp.fromDate(dt) : null,
        'category': category,
      });

      if (dt == null) continue;

      if (!dt.isAfter(ref)) {
        totalSpent += amount;
        if (dt.isAfter(thirtyDaysAgo)) last30 += amount;
        final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        monthly[key] = (monthly[key] ?? 0) + amount;
      }

      if (_sameMonth(dt, ref)) {
        currentMonthExpenses += amount;
        categories[category] = (categories[category] ?? 0) + amount;
        final memberId = (e['memberId'] ?? e['TeamMemberId'])?.toString();
        if (memberId != null &&
            memberId.isNotEmpty &&
            (category == 'salary' || category == 'salaries')) {
          paidMembersThisMonth.add(memberId);
        }
      }
    }

    // Payroll committed for this month but not yet recorded as paid.
    double unpaidPayroll = 0;
    for (final m in members) {
      final status = (m['status'] ?? 'Active').toString();
      if (status != 'Active') continue;
      final id = m['id']?.toString();
      if (id != null && paidMembersThisMonth.contains(id)) continue;
      final joining = _date(m['joiningDate']);
      if (joining != null && joining.isAfter(endOfMonth)) continue;
      unpaidPayroll += _num(m['monthlyCost'] ?? m['salary']);
    }
    if (unpaidPayroll > 0) {
      categories['salary'] = (categories['salary'] ?? 0) + unpaidPayroll;
    }

    double monthlyBurn = currentMonthExpenses + unpaidPayroll;
    bool estimated = false;
    if (monthlyBurn <= 0 && monthly.isNotEmpty) {
      final keys = monthly.keys.toList()..sort((a, b) => b.compareTo(a));
      final recent = keys.take(3).toList();
      monthlyBurn =
          recent.fold<double>(0, (s, k) => s + monthly[k]!) / recent.length;
      estimated = true;
    }

    double monthlyRevenue = 0;
    for (final r in revenue) {
      final dt = _date(r['Date'] ?? r['date']);
      if (dt != null && _sameMonth(dt, ref)) {
        monthlyRevenue += _num(r['Amount'] ?? r['amount']);
      }
    }

    final netBurn = monthlyBurn - monthlyRevenue;
    final available = funding - totalSpent;

    double runway;
    if (available <= 0 || monthlyBurn <= 0) {
      runway = 0;
    } else if (netBurn <= 0) {
      runway = kProfitableRunwayMonths;
    } else {
      runway = available / netBurn;
    }

    normalized.sort((a, b) {
      final ad = a['date'] as Timestamp?;
      final bd = b['date'] as Timestamp?;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    return FinancialSnapshot(
      funding: funding,
      totalSpent: totalSpent,
      availableFunds: available,
      currentMonthExpenses: currentMonthExpenses,
      unpaidPayroll: unpaidPayroll,
      monthlyBurn: monthlyBurn,
      monthlyRevenue: monthlyRevenue,
      netBurn: netBurn,
      runwayMonths: runway,
      isBurnEstimated: estimated,
      last30DaysSpend: last30,
      categoryBreakdown: categories,
      expenses: normalized,
    );
  }

  /// Fetches everything [compute] needs for [uid] and returns the snapshot.
  static Future<FinancialSnapshot> load(String uid) async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait<Object?>([
      db.collection('companies').doc(uid).get(),
      db.collection('expenses').where('uid', isEqualTo: uid).get(),
      db.collection('members').where('uid', isEqualTo: uid).get(),
      // Revenue is optional; a missing collection or rule must not break runway.
      db
          .collection('revenue')
          .where('uid', isEqualTo: uid)
          .get()
          .then<Object?>((s) => s, onError: (_) => null),
    ]);
    final company = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final expenses = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final members = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final revenue = results[3] as QuerySnapshot<Map<String, dynamic>>?;

    final data = company.data() ?? {};
    return compute(
      funding: _num(data['Funding'] ?? data['funding'] ?? data['FUNDING']),
      rawExpenses: docsToMaps(expenses.docs),
      members: docsToMaps(members.docs),
      revenue: revenue == null ? const [] : docsToMaps(revenue.docs),
    );
  }

  static List<Map<String, dynamic>> docsToMaps(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) => docs.map((d) => {...d.data(), 'id': d.id}).toList();

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
