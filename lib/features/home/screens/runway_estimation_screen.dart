import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../shared/widgets/custom_back_button.dart';
import 'package:hugeicons/hugeicons.dart';

class RunwayEstimationScreen extends StatefulWidget {
  const RunwayEstimationScreen({super.key});

  @override
  State<RunwayEstimationScreen> createState() => RunwayEstimationScreenState();
}

class RunwayEstimationScreenState extends State<RunwayEstimationScreen> {
  // Data variables
  double? runwayMonths;
  String? currentBalance;
  String? monthlyBurn;
  String? netBurn;
  String? zeroCashDate;
  bool isLoading = true;

  List<Map<String, dynamic>> monthlyProjections = [];
  List<Map<String, dynamic>> allExpenses = [];

  String _userCountryCode = '+1'; // Default to USD

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadUserCountryCode();
    _loadData();
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) {
      setState(() {
        _userCountryCode =
            CurrencyPreferenceService.getCurrencyPreferenceSync();
      });
    }
  }

  double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(RegExp(r'[^\d.-]'), '')) ??
          fallback;
    }
    return fallback;
  }

  Future<void> _loadUserCountryCode() async {
    final currencyCode =
        await CurrencyPreferenceService.getCurrencyPreference();
    if (mounted && currencyCode != _userCountryCode) {
      setState(() {
        _userCountryCode = currencyCode;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    await _fetchAllExpenses();
    await _fetchRunwayData();
  }

  String _formatCurrency(double amount) {
    return CurrencyFormatter.formatByCountryCompact(amount, _userCountryCode);
  }

  Future<void> _fetchRunwayData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _setEmptyState();
        return;
      }

      final docSnapshot = await FirebaseFirestore.instance
          .collection("companies")
          .doc(user.uid)
          .get();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        final data = docSnapshot.data()!;

        final runwayFromFirebase = data["Runway"]?.toString() ?? "0";
        final funding = data["Funding"] ?? data["funding"] ?? data["FUNDING"];
        final runwayAmount =
            double.tryParse(runwayFromFirebase.toString()) ?? 0;
        final fundingAmount = double.tryParse(funding?.toString() ?? "0") ?? 0;

        final now = DateTime.now();
        final realTotalExpenses = allExpenses.fold<double>(0.0, (t, e) {
          final dt = e['date'];
          if (dt is Timestamp && dt.toDate().isAfter(now)) {
            return t;
          } else if (dt is DateTime && dt.isAfter(now)) {
            return t;
          }
          return t + _toDouble(e['amount']);
        });

        final availableBalance = fundingAmount - realTotalExpenses;

        double currentMonthBurnAmount = 0.0;
        for (final e in allExpenses) {
          final rawDate = e['date'];
          DateTime? dt;
          if (rawDate is Timestamp) {
            dt = rawDate.toDate();
          } else if (rawDate is DateTime) {
            dt = rawDate;
          }
          if (dt != null && dt.month == now.month && dt.year == now.year) {
            currentMonthBurnAmount += _toDouble(e['amount']);
          }
        }

        double actualMonthlyBurn = currentMonthBurnAmount;

        if (actualMonthlyBurn == 0 && allExpenses.isNotEmpty) {
          actualMonthlyBurn = _calculateAverageMonthlyBurn();
        }

        if (actualMonthlyBurn == 0 || availableBalance <= 0) {
          setState(() {
            runwayMonths = availableBalance <= 0 ? 0.0 : runwayAmount;
            currentBalance = _formatCurrency(
              availableBalance < 0 ? 0 : availableBalance,
            );
            monthlyBurn =
                '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0';
            netBurn =
                '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0';
            zeroCashDate = availableBalance <= 0
                ? (fundingAmount == 0 ? 'Awaiting funding' : 'Funds depleted')
                : 'Add expenses to track';
            monthlyProjections = [];
            isLoading = false;
          });
          return;
        }

        final calculatedZeroCashDate = _calculateZeroCashDate(
          availableBalance / actualMonthlyBurn,
        );
        final projections = _generateMonthlyProjections(
          availableBalance,
          actualMonthlyBurn,
        );

        setState(() {
          runwayMonths = availableBalance / actualMonthlyBurn;
          currentBalance = _formatCurrency(availableBalance);
          monthlyBurn = _formatCurrency(actualMonthlyBurn);
          netBurn = _formatCurrency(realTotalExpenses);
          zeroCashDate = calculatedZeroCashDate;
          monthlyProjections = projections;
          isLoading = false;
        });
      } else {
        _setEmptyState();
      }
    } catch (e) {
      debugPrint("Error fetching runway: $e");
      _setEmptyState();
    }
  }

  void _setEmptyState() {
    final zeroStr = '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0';
    setState(() {
      runwayMonths = 0.0;
      currentBalance = zeroStr;
      monthlyBurn = zeroStr;
      netBurn = zeroStr;
      zeroCashDate = '--';
      monthlyProjections = [];
      isLoading = false;
    });
  }

  Future<void> _fetchAllExpenses() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final expensesSnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .get();

      final mappedExpenses = expensesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id};
      }).toList();

      final now = DateTime.now();
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      final expandedPast = ExpenseExpansionHelper.expandExpenses(
        mappedExpenses,
        maxDate: endOfMonth,
        allowFuture: true,
      );

      allExpenses = expandedPast.where((data) => data['isFunding'] != true).map(
        (data) {
          final amountVal = data['Amount'] ?? data['amount'];
          final amount = amountVal is num
              ? amountVal.toDouble()
              : double.tryParse(amountVal?.toString() ?? '0') ?? 0.0;
          return {
            'id': data['id'] ?? data['expenseId'] ?? '',
            'title': data['Title'] ?? 'Unnamed Expense',
            'amount': amount,
            'category': data['Category'] ?? 'General',
            'date': data['Date'] ?? data['date'],
            'description': data['Description'] ?? '',
            'type': data['Type'] ?? 'one_time',
            'recurrenceFrequency':
                data['recurrenceFrequency'] ??
                data['loanRateType'] ??
                'monthly',
            'recurringTenureMonths':
                data['recurringTenureMonths'] ?? data['loanTenureMonths'],
          };
        },
      ).toList();
    } catch (e) {
      debugPrint("Error fetching expenses: $e");
    }
  }

  double _calculateAverageMonthlyBurn() {
    if (allExpenses.isEmpty) return 0;
    Map<String, double> monthlyTotals = {};

    for (var expense in allExpenses) {
      final expenseDate = expense['date'] as Timestamp?;
      if (expenseDate != null) {
        final expenseDateTime = expenseDate.toDate();
        final monthKey =
            "${expenseDateTime.year}-${expenseDateTime.month.toString().padLeft(2, '0')}";
        monthlyTotals[monthKey] =
            (monthlyTotals[monthKey] ?? 0) + _toDouble(expense['amount']);
      }
    }

    if (monthlyTotals.isEmpty) return 0;
    double total = monthlyTotals.values.fold(0, (acc, item) => acc + item);
    return total / monthlyTotals.length;
  }

  String _calculateZeroCashDate(double calculatedRunwayMonths) {
    if (calculatedRunwayMonths <= 0) return "Funds depleted";
    if (calculatedRunwayMonths > 120) return "10+ Years";

    final now = DateTime.now();
    final zeroCashDateTime = now.add(
      Duration(days: (calculatedRunwayMonths * 30.44).round()),
    );
    final months = [
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
    return "${months[zeroCashDateTime.month - 1]} ${zeroCashDateTime.year}";
  }

  List<Map<String, dynamic>> _generateMonthlyProjections(
    double balance,
    double burn,
  ) {
    final projections = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final double runwayDays = (balance / burn) * 30.44;
    if (runwayDays <= 0) return projections;

    const int numIntermediate = 5;
    const int numTotal = 6;
    final double stepDays = runwayDays / numTotal;
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

    String formatDate(DateTime date) {
      return "${months[date.month - 1]} ${date.year}";
    }

    for (int i = 1; i <= numIntermediate; i++) {
      final double offsetDays = stepDays * i;
      final DateTime futureDate = now.add(Duration(days: offsetDays.round()));
      final double offsetMonths = offsetDays / 30.44;
      final double projectedBalance = balance - (burn * offsetMonths);

      if (projectedBalance <= 0) break;

      projections.add({
        'month': formatDate(futureDate),
        'balance': _formatCurrency(projectedBalance),
        'monthsLeft': (projectedBalance / burn).toStringAsFixed(1),
        'isCashOut': false,
      });
    }

    final DateTime cashOutDate = now.add(Duration(days: runwayDays.round()));
    projections.add({
      'month': formatDate(cashOutDate),
      'balance': '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0',
      'monthsLeft': '0.0',
      'isCashOut': true,
    });

    return projections;
  }

  String _getHealthStatus() {
    if (isLoading) return "CALCULATING";
    final zeroStr = '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0';
    if (monthlyBurn == zeroStr && currentBalance == zeroStr) return 'NO DATA';
    if (monthlyBurn == zeroStr) return 'NO EXPENSES';
    if (runwayMonths == null || runwayMonths! <= 0) return "DEPLETED";

    if (runwayMonths! <= 3) return "CRITICAL";
    if (runwayMonths! <= 6) return "WARNING";
    return "SAFE";
  }

  Color _getHealthStatusColor() {
    final status = _getHealthStatus();
    switch (status) {
      case "CRITICAL":
      case "DEPLETED":
        return const Color(0xFFEF4444); // Deep Red
      case "WARNING":
        return const Color(0xFFF59E0B); // Amber
      case "SAFE":
        return const Color(0xFF10B981); // Emerald
      default:
        return context.textSecondary;
    }
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: context.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _showProjectionHint() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedInformationCircle,
              color: context.textPrimary,
              size: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Formula: Fund Left ÷ Monthly Expense",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.cardBackground,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        duration: const Duration(seconds: 4),
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: context.textPrimary,
            backgroundColor: context.cardBackground,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 32),
                  _buildMainRunwayHero(isDark),
                  const SizedBox(height: 40),
                  _buildFinancialMetricsGrid(isDark),
                  const SizedBox(height: 40),
                  _buildMonthlyProjectionSection(isDark),
                  const SizedBox(height: 40),
                  _buildRiskFactorsSection(isDark),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CustomBackButton(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "Runway Analysis",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Projections",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainRunwayHero(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "ESTIMATED RUNWAY",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            Row(
              children: [
                Text(
                  "Updated Today",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _loadData,
                  child: isLoading
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.textSecondary,
                          ),
                        )
                      : HugeIcon(
                          icon: HugeIcons.strokeRoundedRefresh,
                          color: context.textSecondary,
                          size: 14,
                        ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  isLoading
                      ? "--"
                      : (runwayMonths?.toStringAsFixed(1) ?? "0.0"),
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 72, // Massive unboxed text
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -3.0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                "months",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "PROJECTED ZERO CASH",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isLoading ? "--" : (zeroCashDate ?? "--"),
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "RUNWAY HEALTH",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _getHealthStatusColor(),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getHealthStatus(),
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: _getHealthStatusColor(),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinancialMetricsGrid(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("FINANCIAL HEALTH"),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                "Current Balance",
                isLoading
                    ? '--'
                    : (currentBalance ??
                          '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0'),
                HugeIcons.strokeRoundedWallet01,
                const Color(0xFF10B981),
                isDark,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                "Monthly Burn",
                isLoading
                    ? '--'
                    : (monthlyBurn ??
                          '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0'),
                HugeIcons.strokeRoundedFire,
                const Color(0xFFF59E0B),
                isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    dynamic icon,
    Color iconColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: iconColor.withValues(alpha: 0.2)),
            ),
            child: HugeIcon(icon: icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyProjectionSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel("MONTHLY PROJECTION"),
            GestureDetector(
              onTap: _showProjectionHint,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.cardSecondaryBackground,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: context.borderColor),
                  boxShadow: context.cardShadow,
                ),
                child: Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedInformationCircle,
                      color: context.textPrimary,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "FORMULA",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          clipBehavior: Clip
              .antiAlias, // Ensures the zero cash background is clipped perfectly
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: context.borderColor),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: isLoading
              ? _buildEmptyState("Loading projections...")
              : monthlyProjections.isEmpty
              ? _buildEmptyState("Add expenses to see projections")
              : Column(
                  children: [
                    ...monthlyProjections.map((projection) {
                      final bool isCashOut = projection['isCashOut'] == true;
                      return Column(
                        children: [
                          _buildProjectionRow(
                            projection['month'],
                            projection['balance'],
                            projection['monthsLeft'],
                            isCashOut: isCashOut,
                          ),
                          if (projection != monthlyProjections.last)
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: context.borderColor,
                            ),
                        ],
                      );
                    }),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildProjectionRow(
    String month,
    String balance,
    String monthsLeft, {
    bool isCashOut = false,
  }) {
    const cashOutRed = Color(0xFFEF4444); // Standard Deep Red, not pink

    return Container(
      decoration: isCashOut
          ? BoxDecoration(color: cashOutRed.withValues(alpha: 0.05))
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  month,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: isCashOut ? cashOutRed : context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isCashOut) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cashOutRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ZERO CASH',
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: cashOutRed,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                balance,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: isCashOut ? cashOutRed : context.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  monthsLeft,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: isCashOut ? cashOutRed : context.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  "mo",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: isCashOut
                        ? cashOutRed.withValues(alpha: 0.6)
                        : context.textTertiary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskFactorsSection(bool isDark) {
    final List<Map<String, dynamic>> riskFactors = _calculateRiskFactors();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("RISK FACTORS"),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: context.borderColor),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: isLoading
              ? _buildEmptyState("Analyzing data...")
              : riskFactors.isEmpty
              ? _buildEmptyState("No critical risk factors identified")
              : Column(
                  children: riskFactors.asMap().entries.map((entry) {
                    final index = entry.key;
                    final risk = entry.value;
                    final isLast = index == riskFactors.length - 1;

                    return Column(
                      children: [
                        _buildRiskItem(
                          risk['title'],
                          risk['description'],
                          risk['color'],
                        ),
                        if (!isLast)
                          Divider(color: context.borderColor, height: 32),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _calculateRiskFactors() {
    final List<Map<String, dynamic>> risks = [];
    if (allExpenses.isEmpty || runwayMonths == null || runwayMonths! <= 0) {
      return risks;
    }

    final Map<String, double> categoryTotals = {};
    for (var expense in allExpenses) {
      final category = expense['category']?.toString() ?? 'Other';
      final amount = _toDouble(expense['amount']);
      categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
    }

    if ((categoryTotals['Marketing'] ?? 0) > 5000) {
      risks.add({
        'title': 'High Marketing Spend',
        'description':
            'Marketing costs are consuming a significant portion of capital.',
        'color': const Color(0xFFF59E0B),
      });
    }

    if (runwayMonths! < 6) {
      risks.add({
        'title': 'Critical Runway',
        'description':
            'Capital will deplete in less than 6 months at current burn rate.',
        'color': const Color(0xFFEF4444),
      });
    } else if (runwayMonths! >= 6 && runwayMonths! <= 12) {
      risks.add({
        'title': 'Moderate Runway',
        'description': 'Current capital offers 6 to 12 months of operation.',
        'color': const Color(0xFFF59E0B),
      });
    } else if (runwayMonths! > 12) {
      risks.add({
        'title': 'Healthy Runway',
        'description': 'Sufficient capital for over a year of operations.',
        'color': const Color(0xFF10B981),
      });
    }

    return risks;
  }

  Widget _buildRiskItem(String title, String description, Color riskColor) {
    // Dynamic icon based on healthy vs warning
    dynamic iconData = HugeIcons.strokeRoundedAlert01;
    if (riskColor == const Color(0xFF10B981)) {
      iconData = HugeIcons.strokeRoundedTick01;
    } else if (riskColor == const Color(0xFFEF4444)) {
      iconData = HugeIcons.strokeRoundedAlert01;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: riskColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: riskColor.withValues(alpha: 0.2)),
          ),
          child: HugeIcon(icon: iconData, color: riskColor, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
