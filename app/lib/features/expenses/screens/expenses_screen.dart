import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'add_expense_screen.dart';
import 'search_expense_screen.dart';
import 'expense_details_screen.dart';
import 'scan_expense_screen.dart';
import 'report_expense_screen.dart';
import '../../../utils/data_helpers.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../services/financial_calculator.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/currency_formatter.dart';
import '../../../theme/app_theme.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  // State variables for metrics
  double _totalFunding = 0.0;
  double _totalExpenses = 0.0;
  double _avgDaily = 0.0;
  bool _isLoading = true;
  String _userCountryCode = '+1'; // Default to USD
  bool _isLoadingCountry = true;

  String _formatCurrency(double amount) {
    if (_isLoadingCountry) {
      return CurrencyFormatter.formatCompact(amount, countryCode: '+91');
    }
    return CurrencyFormatter.formatByCountryCompact(amount, _userCountryCode);
  }

  StreamSubscription? _companySubscription;
  StreamSubscription? _expensesSubscription;

  late AnimationController _shimmerController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shimmerController.repeat();

    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadMetricsData();
    _loadUserCountryCode();
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _companySubscription?.cancel();
    _expensesSubscription?.cancel();
    _shimmerController.dispose();
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

  Future<void> _loadUserCountryCode() async {
    final currencyCode =
        await CurrencyPreferenceService.getCurrencyPreference();
    if (mounted) {
      setState(() {
        _userCountryCode = currencyCode;
        _isLoadingCountry = false;
      });
    }
  }

  Future<void> _loadMetricsData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await _companySubscription?.cancel();
      await _expensesSubscription?.cancel();

      _companySubscription = FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .snapshots()
          .listen((companyDoc) {
            if (companyDoc.exists && mounted) {
              final companyData = companyDoc.data() as Map<String, dynamic>;
              setState(() {
                _totalFunding = DataHelpers.safeParseDouble(
                  companyData['Funding'],
                );
              });
            }
          });

      _expensesSubscription = FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .snapshots()
          .listen((expensesSnapshot) {
            if (mounted) {
              final rawList = expensesSnapshot.docs.map((doc) {
                final data = doc.data();
                return {...data, 'id': doc.id};
              }).toList();

              final expanded = ExpenseExpansionHelper.expandExpenses(
                rawList,
                maxDate: DateTime.now(),
              );

              double totalRealSpent = 0.0;
              List<Map<String, dynamic>> expenses = [];
              for (final data in expanded) {
                if (data['isFunding'] != true) {
                  final amt = DataHelpers.safeParseDouble(
                    data['Amount'] ?? data['amount'],
                  );
                  totalRealSpent += amt;
                  expenses.add({
                    ...data,
                    'amount': amt,
                    'date': data['Date'] ?? data['date'],
                    'type': data['Type'] ?? data['type'] ?? 'one_time',
                  });
                }
              }

              final rollingMonthlyBurn =
                  FinancialCalculator.rollingAverageMonthlyBurn(expenses);
              setState(() {
                _totalExpenses = totalRealSpent;
                _avgDaily = rollingMonthlyBurn / 30;
                _isLoading = false;
              });
            }
          });
    } catch (e) {
      debugPrint('Error loading metrics: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PREMIUM SECTION LABEL HELPER ---
  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: context.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  // --- CATEGORY ICON HELPER ---
  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'marketing':
        return Icons.campaign_outlined;
      case 'infrastructure':
        return Icons.dns_outlined;
      case 'office':
        return Icons.business_outlined;
      case 'software':
        return Icons.code_outlined;
      case 'hardware':
        return Icons.computer_outlined;
      case 'transport':
        return Icons.directions_car_outlined;
      case 'design':
        return Icons.palette_outlined;
      case 'travel':
        return Icons.flight_outlined;
      case 'meals':
        return Icons.restaurant_outlined;
      case 'contractors':
        return Icons.build_outlined;
      case 'legal':
        return Icons.gavel_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isDarkMode
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // 1. Hero Section (Matches Team Screen)
              _buildMinimalHeader(),

              const SizedBox(height: 28),

              // 2. Metrics (Flat Cards)
              SizedBox(
                height: 130,
                child: _isLoading
                    ? ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        clipBehavior: Clip.none,
                        children: [
                          _buildSkeletonMetricCard(),
                          const SizedBox(width: 12),
                          _buildSkeletonMetricCard(),
                          const SizedBox(width: 12),
                          _buildSkeletonMetricCard(),
                        ],
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        clipBehavior: Clip.none,
                        children: [
                          _buildFlatMetric(
                            "Budget Left",
                            _formatCurrency(
                              _totalFunding > 0
                                  ? (_totalFunding - _totalExpenses)
                                  : 0,
                            ),
                            "${_totalFunding > 0 ? ((_totalFunding - _totalExpenses) / _totalFunding * 100).toStringAsFixed(0) : '0'}%",
                            const Color(0xFF30D158),
                          ),
                          const SizedBox(width: 12),
                          _buildFlatMetric(
                            "Spent",
                            _formatCurrency(_totalExpenses),
                            "${_totalFunding > 0 ? (_totalExpenses / _totalFunding * 100).toStringAsFixed(1) : '0'}% used",
                            context.textPrimary,
                          ),
                          const SizedBox(width: 12),
                          _buildFlatMetric(
                            "Avg. Daily",
                            _formatCurrency(_avgDaily),
                            "30-day rolling avg",
                            context.textSecondary,
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 32),

              // 3. Quick Actions Card
              _buildQuickActionsCard(context),

              const SizedBox(height: 32),

              // 4. Transactions Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildSectionLabel("RECENT TRANSACTIONS"),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SearchExpenseScreen(),
                        ),
                      ).then((_) => _loadMetricsData());
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.textPrimary,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        children: [
                          Text(
                            "View All",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.appBackground,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward,
                            color: context.appBackground,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Firebase Transactions Stream
              _buildFlatTransactionList(),

              const SizedBox(height: 100), // Bottom padding for navbar
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DataHelpers.formatDate(DateTime.now(), format: 'MMMM yyyy'),
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Expenses",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFlatMetric(
    String label,
    String value,
    String badge,
    Color accent,
  ) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDarkMode
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.0,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  badge,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDarkMode
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "QUICK ACTIONS",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildFlatActionButton("Add", Icons.add_rounded, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddExpenseScreen(),
                  ),
                ).then((_) => _loadMetricsData());
              }),
              _buildFlatActionButton("Search", Icons.search_rounded, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SearchExpenseScreen(),
                  ),
                );
              }),
              _buildFlatActionButton("Scan", Icons.qr_code_rounded, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ScanExpenseScreen(),
                  ),
                ).then((_) => _loadMetricsData());
              }),
              _buildFlatActionButton(
                "Report",
                Icons.insert_chart_outlined_rounded,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ReportExpenseScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlatActionButton(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: context.textPrimary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlatTransactionList() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          "User not logged in.",
          style: TextStyle(fontFamily: 'Satoshi', color: context.textSecondary),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              _buildSkeletonTransaction(),
              _buildSkeletonTransaction(),
              _buildSkeletonTransaction(),
              _buildSkeletonTransaction(),
            ],
          );
        }

        if (snapshot.hasError) {
          debugPrint("🚨 FIRESTORE ERROR: ${snapshot.error}");
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              "Error loading transactions. Check console for Index Link.",
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.redAccent),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyTransactionsState();
        }

        final mappedExpenses = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {...data, 'id': doc.id};
        }).toList();

        final expandedExpenses = ExpenseExpansionHelper.expandExpenses(
          mappedExpenses,
          maxDate: DateTime.now(),
        );

        expandedExpenses.sort((a, b) {
          final aDateVal = a['Date'] ?? a['date'];
          final bDateVal = b['Date'] ?? b['date'];
          DateTime? aDt;
          if (aDateVal is Timestamp) {
            aDt = aDateVal.toDate();
          } else if (aDateVal is DateTime) {
            aDt = aDateVal;
          }
          DateTime? bDt;
          if (bDateVal is Timestamp) {
            bDt = bDateVal.toDate();
          } else if (bDateVal is DateTime) {
            bDt = bDateVal;
          }

          if (aDt == null && bDt == null) return 0;
          if (aDt == null) return 1;
          if (bDt == null) return -1;
          return bDt.compareTo(aDt);
        });

        final top5Expenses = expandedExpenses.take(5).toList();

        if (top5Expenses.isEmpty) {
          return _buildEmptyTransactionsState();
        }

        return Column(
          children: top5Expenses.map((data) {
            final expenseId = data['id'] as String;
            return _buildTransactionItem(data, expenseId, context);
          }).toList(),
        );
      },
    );
  }

  Widget _buildTransactionItem(
    Map<String, dynamic> tx,
    String expenseId,
    BuildContext context,
  ) {
    final title = DataHelpers.safeParseString(tx['Title']);
    final amount = DataHelpers.safeParseDouble(tx['Amount']);
    final isFunding = tx['isFunding'] == true;
    final formattedAmount = "${isFunding ? '+' : ''}${_formatCurrency(amount)}";
    final String rawCategory = DataHelpers.safeParseString(tx['Category']);
    final category = rawCategory.isNotEmpty
        ? '${rawCategory[0].toUpperCase()}${rawCategory.substring(1)}'
        : 'General';

    String dateStr = '';
    if (tx['Date'] is Timestamp) {
      final d = (tx['Date'] as Timestamp).toDate();
      dateStr = '${d.day}/${d.month}/${d.year}';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ExpenseDetailsScreen(expenseId: expenseId, expenseData: tx),
          ),
        ).then((_) => _loadMetricsData());
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
          boxShadow: context.isDarkMode
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.isDarkMode
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getCategoryIcon(rawCategory),
                color: context.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

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
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        category,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (dateStr.isNotEmpty) ...[
                        Text(
                          ' · $dateStr',
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                formattedAmount,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: isFunding
                      ? const Color(0xFF30D158)
                      : context.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerEffect(
    double width,
    double height, {
    double borderRadius = 8,
  }) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final value = _shimmerController.value;
        final baseAlpha = context.isDarkMode ? 0.03 : 0.04;
        final midAlpha = context.isDarkMode ? 0.10 : 0.12;

        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment(value - 1, 0),
              end: Alignment(value, 0),
              colors: [
                context.textPrimary.withValues(alpha: baseAlpha),
                context.textPrimary.withValues(alpha: baseAlpha * 2),
                context.textPrimary.withValues(alpha: midAlpha),
                context.textPrimary.withValues(alpha: baseAlpha * 2),
                context.textPrimary.withValues(alpha: baseAlpha),
              ],
              stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonMetricCard() {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildShimmerEffect(70, 12, borderRadius: 4),
              _buildShimmerEffect(8, 8, borderRadius: 4),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShimmerEffect(90, 24, borderRadius: 6),
              const SizedBox(height: 8),
              _buildShimmerEffect(40, 12, borderRadius: 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonTransaction() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          _buildShimmerEffect(44, 44, borderRadius: 12),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerEffect(140, 16, borderRadius: 4),
                const SizedBox(height: 8),
                _buildShimmerEffect(80, 12, borderRadius: 4),
              ],
            ),
          ),
          _buildShimmerEffect(60, 16, borderRadius: 4),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactionsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDarkMode
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            color: context.textTertiary,
            size: 40,
          ),
          const SizedBox(height: 16),
          Text(
            "No transactions yet",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Add your first expense to get started",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
