import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer';
import 'add_bank_account_screen.dart';
import '../../expenses/screens/expense_details_screen.dart';
import '../../../services/financial_calculator.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/bank_account_service.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../shared/widgets/custom_back_button.dart';
import 'package:hugeicons/hugeicons.dart';

// --- CUSTOM DOTTED DIVIDER WIDGET ---
class DottedDivider extends StatelessWidget {
  final Color color;
  final double height;
  final double dashWidth;

  const DottedDivider({
    super.key,
    required this.color,
    this.height = 1.0,
    this.dashWidth = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: height,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            );
          }),
        );
      },
    );
  }
}

class FundsOverviewScreen extends StatefulWidget {
  const FundsOverviewScreen({super.key});

  @override
  State<FundsOverviewScreen> createState() => _FundsOverviewScreenState();
}

class _FundsOverviewScreenState extends State<FundsOverviewScreen> {
  // Raw financial data — always kept in sync via setState
  double _totalExpensesAmount = 0.0;
  double _availableAmount = 0.0;
  bool _dataLoaded = false;

  String? lastUpdated;
  bool isLoading = true;
  String? errorMessage;
  double? fundingAmount;

  List<Map<String, dynamic>> fundingHistory = [];
  List<Map<String, dynamic>> allExpenses = [];
  List<Map<String, dynamic>> bankAccounts = [];
  List<Map<String, dynamic>> cashFlowBreakdown = [];

  String _userCountryCode = '+1'; // Default to USD

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadUserCountryCode();
    _loadAllData();
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
      _loadAllData();
    }
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

  Future<void> _loadAllData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      await Future.wait([_fetchFundsData(), _fetchAllExpenses()]);

      if (fundingAmount != null) {
        final now = DateTime.now();
        final totalReal = allExpenses.fold<double>(0.0, (t, e) {
          final ts = e['timestamp'] as Timestamp?;
          if (ts != null && ts.toDate().isAfter(now)) {
            return t;
          }
          return t + (e['rawAmount'] as double? ?? 0.0);
        });
        setState(() {
          _totalExpensesAmount = totalReal;
          _availableAmount = fundingAmount! - totalReal;
          lastUpdated = 'Today';
          _dataLoaded = true;
        });
      }

      _calculateCashFlowBreakdown();

      await Future.wait([_fetchBankAccounts(), _fetchFundingHistory()]);
    } catch (e) {
      log('Error loading all data: $e');
      if (mounted) {
        setState(() {
          errorMessage = 'Failed to load some data. Pull down to refresh.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _fetchFundsData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final docSnapshot = await FirebaseFirestore.instance
          .collection("companies")
          .doc(user.uid)
          .get();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        final data = docSnapshot.data()!;
        final funding = data["Funding"] ?? data["funding"] ?? data["FUNDING"];
        if (mounted) {
          setState(() {
            if (funding != null) {
              if (funding is num) {
                fundingAmount = funding.toDouble();
              } else if (funding is String) {
                fundingAmount = double.tryParse(
                  funding.replaceAll(RegExp(r'[^\d.-]'), ''),
                );
              }
            }
          });
        }
      }
    } catch (e) {
      log("Error fetching funds data: $e");
    }
  }

  Future<void> _fetchBankAccounts() async {
    try {
      final accounts = await BankAccountService.getBankAccounts();
      if (mounted) {
        setState(() {
          bankAccounts = accounts;
        });
      }
    } catch (e) {
      log("Error fetching bank accounts: $e");
    }
  }

  Future<void> _fetchFundingHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final docSnapshot = await FirebaseFirestore.instance
          .collection("companies")
          .doc(user.uid)
          .get();

      fundingHistory.clear();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        final data = docSnapshot.data()!;
        final totalFunding =
            double.tryParse(
              (data["Funding"] ?? data["funding"] ?? data["FUNDING"] ?? 0)
                  .toString(),
            ) ??
            0;

        final createdAt = data['createdAt'] as Timestamp?;
        final companyDateStr = createdAt != null
            ? _formatDate(createdAt)
            : 'Date unknown';

        double additionalFundingTotal = 0;
        final List<Map<String, dynamic>> txnEntries = [];

        try {
          final txnSnapshot = await FirebaseFirestore.instance
              .collection('funding_transactions')
              .where('uid', isEqualTo: user.uid)
              .get();

          final sortedDocs = txnSnapshot.docs.toList()
            ..sort((a, b) {
              final aTime = a.data()['createdAt'] as Timestamp?;
              final bTime = b.data()['createdAt'] as Timestamp?;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return aTime.compareTo(bTime);
            });

          int roundNumber = 2;
          for (var doc in sortedDocs) {
            final txnData = doc.data();
            final amt = (txnData['amount'] as num?)?.toDouble() ?? 0;
            final source = txnData['source'] ?? 'Funding';
            final txnCreatedAt = txnData['createdAt'] as Timestamp?;
            final txnDateStr = txnCreatedAt != null
                ? _formatDate(txnCreatedAt)
                : 'Recent';

            additionalFundingTotal += amt;
            txnEntries.add({
              'round': 'Round $roundNumber · $source',
              'amount': amt.toInt(),
              'date': txnDateStr,
              'status': 'completed',
            });
            roundNumber++;
          }
        } catch (e) {
          log("Error fetching funding transactions: $e");
        }

        final initialFunding = totalFunding - additionalFundingTotal;

        if (initialFunding > 0) {
          fundingHistory.add({
            'round': 'Initial Funding',
            'amount': initialFunding.toInt(),
            'date': companyDateStr,
            'status': 'completed',
          });
        }

        fundingHistory.addAll(txnEntries);
      }
    } catch (e) {
      log("Error fetching funding history: $e");
    }
  }

  String _formatDate(Timestamp timestamp) {
    final dt = timestamp.toDate();
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
    return "${months[dt.month - 1]} ${dt.year}";
  }

  void _calculateCashFlowBreakdown() {
    final Map<String, double> categoryTotals = {};
    final now = DateTime.now();
    for (var expense in allExpenses) {
      final ts = expense['timestamp'] as Timestamp?;
      if (ts != null && ts.toDate().isAfter(now)) {
        continue;
      }
      final category = expense['category'] as String? ?? 'Other';
      final amount =
          (expense['rawAmount'] as num?)?.toDouble() ??
          (expense['amount'] as num?)?.toDouble() ??
          (expense['Amount'] as num?)?.toDouble() ??
          0.0;
      categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
    }

    cashFlowBreakdown = categoryTotals.entries.map((entry) {
      String category = entry.key;
      if (category.isNotEmpty) {
        category = category[0].toUpperCase() + category.substring(1);
      }
      return {
        'category': category,
        'amount': -entry.value.abs().toInt(),
        'percentage': 0,
      };
    }).toList();
  }

  String _getHealthStatus() {
    if (isLoading || !_dataLoaded || fundingAmount == null) {
      return 'NO DATA';
    }

    final runwayMonths = FinancialCalculator.runwayMonths(
      availableFunds: _availableAmount,
      monthlyBurn: _calculateCurrentMonthBurn(),
    );

    return FinancialCalculator.runwayHealthStatus(runwayMonths);
  }

  Color _getHealthStatusColor() {
    final status = _getHealthStatus();
    switch (status) {
      case "SAFE":
        return const Color(0xFF10B981); // Emerald Green
      case "WARNING":
        return const Color(0xFFF59E0B); // Amber
      case "CRITICAL":
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF71717A); // Gray
    }
  }

  double _calculateCurrentMonthBurn() {
    if (allExpenses.isEmpty) return 0.0;
    final now = DateTime.now();
    double currentMonthTotal = 0;
    for (var expense in allExpenses) {
      final ts = expense['timestamp'] as Timestamp?;
      if (ts != null) {
        final dt = ts.toDate();
        if (dt.month == now.month && dt.year == now.year) {
          currentMonthTotal += expense['rawAmount'] as double? ?? 0.0;
        }
      }
    }
    return currentMonthTotal;
  }

  Future<void> _fetchAllExpenses() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final expensesSnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .get();

      final rawExpenses = expensesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id};
      }).toList();

      final now = DateTime.now();
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      final expandedList = ExpenseExpansionHelper.expandExpenses(
        rawExpenses,
        maxDate: endOfMonth,
        allowFuture: true,
      );

      final List<Map<String, dynamic>> loadedExpenses = [];
      for (final data in expandedList) {
        if (data['isFunding'] == true) continue;

        final amountVal = data['Amount'] ?? data['amount'];
        double amt = 0.0;
        if (amountVal is num) {
          amt = amountVal.toDouble();
        } else if (amountVal is String) {
          amt =
              double.tryParse(amountVal.replaceAll(RegExp(r'[^\d.-]'), '')) ??
              0.0;
        }

        final title = data['Title'] ?? data['title'] ?? 'Expense';
        final category = data['Category'] ?? data['category'] ?? 'Other';
        final description = data['Description'] ?? data['description'] ?? '';
        final dateVal = data['Date'] ?? data['date'];

        Timestamp? ts;
        if (dateVal is Timestamp) {
          ts = dateVal;
        } else if (dateVal is DateTime) {
          ts = Timestamp.fromDate(dateVal);
        }

        String dateStr = 'Unknown date';
        if (ts != null) {
          final dt = ts.toDate();
          dateStr = '${dt.day}/${dt.month}/${dt.year}';
        }

        loadedExpenses.add({
          'id': data['id'] ?? data['expenseId'] ?? '',
          'title': title,
          'amount': amt.toInt(),
          'rawAmount': amt,
          'category': category,
          'description': description,
          'date': dateStr,
          'timestamp': ts,
        });
      }

      loadedExpenses.sort((a, b) {
        final aTime = a['timestamp'] as Timestamp?;
        final bTime = b['timestamp'] as Timestamp?;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          allExpenses = loadedExpenses;
        });
      }
    } catch (e) {
      log("Error fetching expenses: $e");
    }
  }

  // --- UI RENDERING ---

  Widget _buildSectionLabel(String text, Color textSecondary) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildEmptyState(String text, Color textTertiary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium Solid Color Palette
    final bgColor = isDark ? const Color(0xFF09090B) : const Color(0xFFF9FAFB);
    final cardColor = isDark
        ? const Color(0xFF141416)
        : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final shadowColor = isDark
        ? Colors.transparent
        : Colors.black.withValues(alpha: 0.04);

    final textPrimary = isDark ? Colors.white : const Color(0xFF09090B);
    final textSecondary = isDark ? Colors.white54 : const Color(0xFF71717A);
    final textTertiary = isDark ? Colors.white38 : const Color(0xFFA1A1AA);

    return Scaffold(
      backgroundColor: bgColor,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadAllData,
            color: textPrimary,
            backgroundColor: cardColor,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(
                    context,
                    textPrimary,
                    textSecondary,
                    cardColor,
                    borderColor,
                  ),
                  const SizedBox(height: 32),

                  // Unified Bento Hero Section
                  _buildHeroBento(
                    cardColor,
                    borderColor,
                    shadowColor,
                    textPrimary,
                    textSecondary,
                    isDark,
                  ),
                  const SizedBox(height: 32),

                  _buildFundingHistorySection(
                    cardColor,
                    borderColor,
                    shadowColor,
                    textPrimary,
                    textSecondary,
                    textTertiary,
                  ),
                  const SizedBox(height: 32),

                  _buildRecentExpensesSection(
                    cardColor,
                    borderColor,
                    shadowColor,
                    textPrimary,
                    textSecondary,
                    textTertiary,
                    isDark,
                  ),
                  const SizedBox(height: 32),

                  _buildCashFlowSection(
                    cardColor,
                    borderColor,
                    shadowColor,
                    textPrimary,
                    textSecondary,
                    textTertiary,
                  ),
                  const SizedBox(height: 32),

                  _buildBankAccountsSection(
                    cardColor,
                    borderColor,
                    shadowColor,
                    textPrimary,
                    textSecondary,
                    textTertiary,
                    isDark,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color cardColor,
    Color borderColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CustomBackButton(),
        Text(
          "Capital Analysis",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBento(
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: borderColor),
        boxShadow: shadowColor == Colors.transparent
            ? []
            : [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getHealthStatusColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: _getHealthStatusColor().withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  _getHealthStatus(),
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: _getHealthStatusColor(),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    "Updated: ${lastUpdated ?? '--'}",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _loadAllData,
                    child: isLoading
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: textSecondary,
                            ),
                          )
                        : HugeIcon(
                            icon: HugeIcons.strokeRoundedRefresh,
                            color: textSecondary,
                            size: 14,
                          ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            "AVAILABLE FUNDS",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              isLoading
                  ? '--'
                  : CurrencyFormatter.formatByCountryCompact(
                      _availableAmount,
                      _userCountryCode,
                    ),
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textPrimary,
                fontSize: 48,
                fontWeight: FontWeight.w700,
                letterSpacing: -2.0,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 32),
          DottedDivider(color: borderColor), // Subtle Divider
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "LIFETIME OUTFLOW",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isLoading
                          ? '--'
                          : CurrencyFormatter.formatByCountryCompact(
                              _totalExpensesAmount,
                              _userCountryCode,
                            ),
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: borderColor,
              ), // Vertical separator
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "TOTAL CAPITAL",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isLoading
                          ? '--'
                          : CurrencyFormatter.formatByCountryCompact(
                              fundingAmount ?? 0,
                              _userCountryCode,
                            ),
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFundingHistorySection(
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("FUNDING HISTORY", textSecondary),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor),
            boxShadow: shadowColor == Colors.transparent
                ? []
                : [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: isLoading
              ? _buildEmptyState("Loading history...", textTertiary)
              : fundingHistory.isEmpty
              ? _buildEmptyState("No funding rounds recorded", textTertiary)
              : Column(
                  children: fundingHistory.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final isLast = index == fundingHistory.length - 1;
                    return Column(
                      children: [
                        _buildFundingItem(item, textPrimary, textSecondary),
                        if (!isLast) Divider(color: borderColor, height: 32),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildFundingItem(
    Map<String, dynamic> item,
    Color textPrimary,
    Color textSecondary,
  ) {
    final amount = (item['amount'] as num?)?.toInt() ?? 0;
    final isActive =
        item['status'] == 'active' || item['status'] == 'completed';
    final greenColor = const Color(0xFF10B981); // Emerald
    final formattedAmount =
        '+${CurrencyFormatter.formatByCountryCompact(amount.toDouble(), _userCountryCode)}';

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: greenColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: greenColor.withValues(alpha: 0.2)),
          ),
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedBank,
            color: greenColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['round'] as String,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item['date'] as String,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formattedAmount,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: greenColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isActive)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: greenColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "COMPLETED",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: greenColor,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentExpensesSection(
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
    bool isDark,
  ) {
    final List<Map<String, dynamic>> expenseTransactions = allExpenses
        .take(5)
        .map(
          (expense) => {
            'id': expense['id'],
            'round': expense['title'],
            'amount': -(expense['amount'] as int),
            'date': expense['date'],
            'status': 'completed',
            'type': 'expense',
            'category': expense['category'],
            'description': expense['description'],
          },
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("RECENT EXPENSES", textSecondary),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor),
            boxShadow: shadowColor == Colors.transparent
                ? []
                : [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: isLoading
              ? _buildEmptyState("Loading expenses...", textTertiary)
              : expenseTransactions.isEmpty
              ? _buildEmptyState("No recent expenses", textTertiary)
              : Column(
                  children: expenseTransactions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final transaction = entry.value;
                    final isLast = index == expenseTransactions.length - 1;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _navigateToExpenseDetails(transaction),
                      child: Column(
                        children: [
                          _buildTransactionItem(
                            transaction,
                            textPrimary,
                            textSecondary,
                            borderColor,
                            isDark,
                          ),
                          if (!isLast) Divider(color: borderColor, height: 32),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildTransactionItem(
    Map<String, dynamic> transaction,
    Color textPrimary,
    Color textSecondary,
    Color borderColor,
    bool isDark,
  ) {
    final isExpense = transaction['type'] == 'expense';
    final isActive = transaction['status'] == 'active';
    final amount = (transaction['amount'] as num?)?.toInt() ?? 0;
    final isNegative = amount < 0;

    final redColor = const Color(0xFFEF4444);
    final greenColor = const Color(0xFF10B981);

    String formattedAmount;
    Color amountColor;

    final cleanAmount = CurrencyFormatter.formatByCountryCompact(
      amount.abs().toDouble(),
      _userCountryCode,
    );

    if (isNegative) {
      formattedAmount = '-$cleanAmount';
      amountColor = redColor;
    } else {
      formattedAmount = '+$cleanAmount';
      amountColor = isActive ? greenColor : textPrimary;
    }

    final iconBgColor = isExpense
        ? redColor.withValues(alpha: 0.1)
        : isActive
        ? greenColor.withValues(alpha: 0.1)
        : (isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05));

    final iconBorderColor = isExpense
        ? redColor.withValues(alpha: 0.2)
        : isActive
        ? greenColor.withValues(alpha: 0.2)
        : borderColor;

    final iconColor = isExpense
        ? redColor
        : (isActive ? greenColor : textSecondary);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: iconBorderColor),
          ),
          child: HugeIcon(
            icon: isExpense
                ? HugeIcons.strokeRoundedInvoice01
                : (isActive
                      ? HugeIcons.strokeRoundedArrowUpRight01
                      : HugeIcons.strokeRoundedBank),
            color: iconColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction['round'],
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                isExpense
                    ? '${transaction['category']} • ${transaction['date']}'
                    : transaction['date'],
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          formattedAmount,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: amountColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildCashFlowSection(
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
  ) {
    final totalOutflow = cashFlowBreakdown
        .where((item) => item['amount'] < 0)
        .fold<int>(0, (total, item) => total + (item['amount'] as int));

    final formattedOutflow = CurrencyFormatter.formatByCountryCompact(
      totalOutflow.abs().toDouble(),
      _userCountryCode,
    );
    final redColor = const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("CASH FLOW BREAKDOWN", textSecondary),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor),
            boxShadow: shadowColor == Colors.transparent
                ? []
                : [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: isLoading
              ? _buildEmptyState("Loading cash flow...", textTertiary)
              : cashFlowBreakdown.isEmpty
              ? _buildEmptyState("No cash flow data", textTertiary)
              : Column(
                  children: [
                    ...cashFlowBreakdown.map(
                      (item) => _buildCashFlowItem(
                        item,
                        textPrimary,
                        textSecondary,
                        redColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DottedDivider(color: borderColor),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Total Outflow",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '-$formattedOutflow',
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: redColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCashFlowItem(
    Map<String, dynamic> item,
    Color textPrimary,
    Color textSecondary,
    Color redColor,
  ) {
    final amount = item['amount'] as int;
    final isPositive = amount >= 0;
    final greenColor = const Color(0xFF10B981);

    final formattedAmount = CurrencyFormatter.formatByCountryCompact(
      amount.abs().toDouble(),
      _userCountryCode,
    );
    final displayAmount = isPositive
        ? '+$formattedAmount'
        : '-$formattedAmount';
    final dotColor = isPositive ? greenColor : redColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              item['category'],
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            displayAmount,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: dotColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankAccountsSection(
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("PAYMENT METHODS", textSecondary),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor),
            boxShadow: shadowColor == Colors.transparent
                ? []
                : [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: isLoading
              ? _buildEmptyState("Loading accounts...", textTertiary)
              : bankAccounts.isEmpty
              ? Column(
                  children: [
                    _buildEmptyState(
                      "No bank accounts connected",
                      textTertiary,
                    ),
                    const SizedBox(height: 16),
                    _buildAddAccountButton(textPrimary, isDark),
                  ],
                )
              : Column(
                  children: [
                    ...bankAccounts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final account = entry.value;
                      final isLast = index == bankAccounts.length - 1;
                      return Column(
                        children: [
                          _buildBankAccountItem(
                            account,
                            textPrimary,
                            textSecondary,
                          ),
                          if (!isLast) Divider(color: borderColor, height: 32),
                        ],
                      );
                    }),
                    const SizedBox(height: 16),
                    DottedDivider(color: borderColor),
                    const SizedBox(height: 24),
                    _buildAddAccountButton(textPrimary, isDark),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildAddAccountButton(Color textPrimary, bool isDark) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddBankAccountScreen()),
        );
        if (result != null) {
          _loadAllData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16), // Soft filled button
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAdd01,
              color: textPrimary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              "Add Bank Account",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankAccountItem(
    Map<String, dynamic> account,
    Color textPrimary,
    Color textSecondary,
  ) {
    final totalSpent = (account['totalSpent'] as num?)?.toDouble() ?? 0.0;
    final isCash = account['isCash'] == true;

    final bankName =
        account['name']?.toString() ??
        account['bankName']?.toString() ??
        account['bank_name']?.toString() ??
        'Unknown Bank';

    final accentColor = isCash
        ? const Color(0xFFF59E0B)
        : const Color(0xFF3B82F6); // Amber or Blue
    final redColor = const Color(0xFFEF4444);

    final cleanSpent = totalSpent
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
    final formattedAmount = totalSpent > 0
        ? '-${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}$cleanSpent'
        : '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0';

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: HugeIcon(
            icon: isCash
                ? HugeIcons.strokeRoundedCoins01
                : HugeIcons.strokeRoundedBank,
            color: accentColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bankName,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                account['maskedNumber']?.toString() ?? '****',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formattedAmount,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: totalSpent > 0 ? redColor : textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "total outflow",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _navigateToExpenseDetails(Map<String, dynamic> transaction) {
    if (transaction['id'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExpenseDetailsScreen(
            expenseId: transaction['id'],
            expenseData: transaction,
          ),
        ),
      );
    }
  }
}
