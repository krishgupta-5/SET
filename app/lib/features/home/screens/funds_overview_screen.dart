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
import '../../../widgets/rx_ui.dart';
import '../../../widgets/rx_charts.dart';
import '../../../widgets/rx_motion.dart';
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
  FinancialSnapshot? _snapshot;

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

      final user = FirebaseAuth.instance.currentUser;
      if (fundingAmount != null && user != null) {
        // Shared calculation, so balance/runway match the dashboard.
        final s = await FinancialCalculator.load(user.uid);
        if (mounted) {
          setState(() {
            _snapshot = s;
            _totalExpensesAmount = s.totalSpent;
            _availableAmount = s.availableFunds;
            lastUpdated = 'Today';
            _dataLoaded = true;
          });
        }
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

    final s = _snapshot;
    if (s == null || s.monthlyBurn <= 0) return 'NO DATA';
    final runway = s.runwayMonths;
    // Same thresholds as the dashboard and runway screen.
    if (runway <= 3) return 'CRITICAL';
    if (runway <= 6) return 'WARNING';
    return 'SAFE';
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

  // --- UI RENDERING (presentation only) ---

  String _money(num amount) => CurrencyFormatter.formatByCountryCompact(
    amount.toDouble(),
    _userCountryCode,
  );

  ({String label, Color fg, Color bg}) _statusStyle() {
    final rx = context.rx;
    switch (_getHealthStatus()) {
      case "SAFE":
        return (label: 'Healthy', fg: rx.positive, bg: rx.positiveSoft);
      case "WARNING":
        return (label: 'Watch', fg: rx.warning, bg: rx.warningSoft);
      case "CRITICAL":
        return (label: 'Critical', fg: rx.negative, bg: rx.negativeSoft);
      default:
        return (
          label: isLoading ? 'Updating' : 'No data',
          fg: rx.textSecondary,
          bg: rx.surfaceMuted,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: rx.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              RxTopBar(
                title: 'Funds',
                trailing: RxCircleButton(
                  icon: HugeIcons.strokeRoundedRefresh,
                  semanticLabel: 'Refresh',
                  onTap: isLoading ? null : _loadAllData,
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadAllData,
                  color: rx.textPrimary,
                  backgroundColor: rx.surface,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      MediaQuery.paddingOf(context).bottom + 32,
                    ),
                    children: [
                      RxReveal(
                        key: ValueKey('hero-$isLoading'),
                        child: _buildHero(),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _buildErrorBanner(errorMessage!),
                      ],
                      // Sections with nothing to show are left out.
                      ..._section(
                        1,
                        'Funding history',
                        _buildFundingHistoryCard,
                      ),
                      ..._section(
                        2,
                        'Recent expenses',
                        _buildRecentExpensesCard,
                      ),
                      ..._section(3, 'Spend by category', _buildCashFlowCard),
                      ..._section(4, 'Payment methods', _buildBankAccountsCard),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Header + card, revealed when data lands. Nothing when the card is empty.
  List<Widget> _section(int index, String title, Widget? Function() build) {
    final card = build();
    if (card == null) return const [];
    return [
      const SizedBox(height: 28),
      RxReveal(
        key: ValueKey('$title-$isLoading'),
        delay: Duration(milliseconds: 60 * index),
        child: Column(
          children: [
            RxSectionHeader(title: title),
            card,
          ],
        ),
      ),
    ];
  }

  // --- HERO ---
  // Same pattern as Home: the number on the page, details in one split card.
  Widget _buildHero() {
    final rx = context.rx;
    final status = _statusStyle();

    Widget half(String label, String value) => Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: RxText.label(context)),
            const SizedBox(height: 8),
            if (isLoading)
              const RxSkeleton(width: 90, height: 24)
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: RxText.value(context, size: 20)),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Available funds', style: RxText.label(context)),
            const SizedBox(width: 8),
            RxPill(
              label: status.label,
              dot: true,
              foreground: status.fg,
              background: status.bg,
            ),
            const Spacer(),
            if (lastUpdated != null)
              Text(
                'Updated ${lastUpdated!.toLowerCase()}',
                style: RxText.micro(context),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            isLoading ? '--' : _money(_availableAmount),
            style: RxText.hero(context, size: 52),
          ),
        ),
        const SizedBox(height: 24),
        RxCard(
          padding: EdgeInsets.zero,
          child: IntrinsicHeight(
            child: Row(
              children: [
                half('Total raised', _money(fundingAmount ?? 0)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(width: 1, color: rx.hairline),
                ),
                half('Spent to date', _money(_totalExpensesAmount)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String text) {
    final rx = context.rx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: rx.warningSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedAlert02,
            color: rx.warning,
            size: 18,
            strokeWidth: 1.8,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: RxText.caption(context, color: rx.warning),
            ),
          ),
        ],
      ),
    );
  }

  // --- LIST HELPERS ---

  Widget _skeletonRows(int n) => RxCard(
    child: Column(
      children: [
        for (var i = 0; i < n; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                RxSkeleton(width: 36, height: 36, radius: 11),
                SizedBox(width: 12),
                Expanded(child: RxSkeleton(height: 14)),
                SizedBox(width: 40),
                RxSkeleton(width: 64, height: 14),
              ],
            ),
          ),
      ],
    ),
  );

  /// Row used by every list on this screen: tile, title + subtitle, amount.
  Widget _row({
    required List<List<dynamic>> icon,
    required Color tint,
    required Color tintSoft,
    required String title,
    required String subtitle,
    required String amount,
    Color? amountColor,
    String? amountNote,
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          RxIconTile(
            icon: icon,
            size: 38,
            iconSize: 18,
            background: tintSoft,
            foreground: tint,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RxText.body(context),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RxText.caption(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount, style: RxText.amount(context, color: amountColor)),
              if (amountNote != null) ...[
                const SizedBox(height: 2),
                Text(amountNote, style: RxText.micro(context)),
              ],
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return RxPressable(onTap: onTap, scale: 0.98, child: content);
  }

  Widget _listCard(List<Widget> rows) => RxCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const RxDivider(indent: 50),
          rows[i],
        ],
      ],
    ),
  );

  // --- FUNDING HISTORY ---
  Widget? _buildFundingHistoryCard() {
    final rx = context.rx;
    if (isLoading) return _skeletonRows(2);
    if (fundingHistory.isEmpty) return null;
    return _listCard([
      for (final item in fundingHistory)
        _row(
          icon: HugeIcons.strokeRoundedMoneyReceive01,
          tint: rx.positive,
          tintSoft: rx.positiveSoft,
          title: item['round'] as String,
          subtitle: item['date'] as String,
          amount: '+${_money((item['amount'] as num?)?.toInt() ?? 0)}',
          amountColor: rx.positive,
        ),
    ]);
  }

  // --- RECENT EXPENSES ---
  Widget? _buildRecentExpensesCard() {
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

    if (isLoading) return _skeletonRows(3);
    if (expenseTransactions.isEmpty) return null;

    return _listCard([
      for (final t in expenseTransactions)
        Builder(
          builder: (context) {
            final category = t['category']?.toString() ?? 'Other';
            final amount = (t['amount'] as num?)?.toInt() ?? 0;
            return _row(
              icon: RxCategory.icon(category),
              tint: RxCategory.color(context, category),
              tintSoft: RxCategory.soft(context, category),
              title: t['round']?.toString() ?? 'Expense',
              subtitle: '${_capitalize(category)} · ${t['date']}',
              amount: '-${_money(amount.abs())}',
              onTap: () => _navigateToExpenseDetails(t),
            );
          },
        ),
    ]);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // --- SPEND BY CATEGORY ---
  Widget? _buildCashFlowCard() {
    final rx = context.rx;
    final totalOutflow = cashFlowBreakdown
        .where((item) => item['amount'] < 0)
        .fold<int>(0, (total, item) => total + (item['amount'] as int));

    if (isLoading) return _skeletonRows(3);
    final total = totalOutflow.abs();
    if (cashFlowBreakdown.isEmpty || total <= 0) return null;
    final sorted = [...cashFlowBreakdown]
      ..sort(
        (a, b) =>
            (b['amount'] as int).abs().compareTo((a['amount'] as int).abs()),
      );

    return RxCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Column(
        children: [
          // Lifetime spend as a donut; sweeps in on open.
          Center(
            child: RxDonut(
              key: ValueKey('funds-donut-$isLoading'),
              size: 168,
              thickness: 16,
              segments: [
                for (final item in sorted)
                  RxDonutSegment(
                    value: (item['amount'] as int).abs().toDouble(),
                    color: RxCategory.color(
                      context,
                      item['category'] as String,
                    ),
                  ),
              ],
              trackColor: rx.textPrimary.withValues(alpha: 0.06),
              semanticLabel: 'Lifetime spend by category',
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Lifetime', style: RxText.caption(context)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _money(total),
                      style: RxText.value(context, size: 20),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${sorted.length} ${sorted.length == 1 ? 'category' : 'categories'}',
                    style: RxText.micro(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) const RxDivider(indent: 22),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: RxCategory.color(
                        context,
                        sorted[i]['category'] as String,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sorted[i]['category'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RxText.body(context),
                    ),
                  ),
                  if (total > 0)
                    Text(
                      '${(((sorted[i]['amount'] as int).abs() / total) * 100).round()}%',
                      style: RxText.label(context, color: rx.textTertiary),
                    ),
                  const SizedBox(width: 14),
                  Text(
                    _money((sorted[i]['amount'] as int).abs()),
                    style: RxText.amount(context),
                  ),
                ],
              ),
            ),
          ],
          const RxDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total spent',
                    style: RxText.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '-${_money(total)}',
                  style: RxText.amount(context, color: rx.negative),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- PAYMENT METHODS ---
  Widget? _buildBankAccountsCard() {
    final rx = context.rx;
    if (isLoading) return _skeletonRows(2);

    final addButton = RxPressable(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddBankAccountScreen()),
        );
        if (result != null) {
          _loadAllData();
        }
      },
      semanticLabel: 'Add bank account',
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: rx.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAdd01,
              color: rx.textPrimary,
              size: 18,
              strokeWidth: 2,
            ),
            const SizedBox(width: 8),
            Text(
              'Add bank account',
              style: RxText.body(context).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );

    if (bankAccounts.isEmpty) {
      return RxCard(
        child: Column(
          children: [
            const RxEmptyState(
              icon: HugeIcons.strokeRoundedCreditCard,
              title: 'No accounts yet',
              message: 'Add a bank account or cash wallet to tag spending',
              padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
            ),
            addButton,
          ],
        ),
      );
    }

    return RxCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          for (var i = 0; i < bankAccounts.length; i++) ...[
            if (i > 0) const RxDivider(indent: 50),
            Builder(
              builder: (context) {
                final account = bankAccounts[i];
                final totalSpent =
                    (account['totalSpent'] as num?)?.toDouble() ?? 0.0;
                final isCash = account['isCash'] == true;
                final bankName =
                    account['name']?.toString() ??
                    account['bankName']?.toString() ??
                    account['bank_name']?.toString() ??
                    'Unknown Bank';
                final tint = isCash
                    ? RxCategory.color(context, 'meals')
                    : RxCategory.color(context, 'servers');
                final tintSoft = isCash
                    ? RxCategory.soft(context, 'meals')
                    : RxCategory.soft(context, 'servers');
                return _row(
                  icon: isCash
                      ? HugeIcons.strokeRoundedCoins01
                      : HugeIcons.strokeRoundedBank,
                  tint: tint,
                  tintSoft: tintSoft,
                  title: bankName,
                  subtitle: account['maskedNumber']?.toString() ?? '****',
                  amount: totalSpent > 0 ? '-${_money(totalSpent)}' : _money(0),
                  amountColor: totalSpent > 0 ? null : rx.textSecondary,
                  amountNote: 'spent',
                );
              },
            ),
          ],
          const SizedBox(height: 8),
          addButton,
        ],
      ),
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
