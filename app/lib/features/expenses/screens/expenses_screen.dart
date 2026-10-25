import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/widgets/rx_ui.dart';
import 'package:startup_expense_tracker/widgets/rx_charts.dart';
import 'package:startup_expense_tracker/widgets/rx_motion.dart';
import 'package:startup_expense_tracker/widgets/rx_pickers.dart'
    show rxFormatDate;
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
import '../../../widgets/custom_bottom_nav.dart' show RxTabBar;

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, this.visit});

  /// Changes each time the Expenses tab is opened (null while hidden), so
  /// the ring replays its sweep.
  final int? visit;

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

  // Keys the ring; bumping it replays the sweep.
  int _chartEpoch = 0;

  @override
  void didUpdateWidget(covariant ExpensesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visit != null && widget.visit != oldWidget.visit) {
      _chartEpoch++;
    }
  }

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

  // --- UI (presentation only) ---

  void _open(Widget screen, {bool reload = true}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    ).then((_) {
      if (reload) _loadMetricsData();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            RxTabBar.reservedHeight(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Sections rise in once, 60ms apart, on first open.
            children: [
              RxReveal.index(0, child: _buildMinimalHeader()),
              const SizedBox(height: 28),
              RxReveal.index(1, child: _buildHero()),
              const SizedBox(height: 24),
              RxReveal.index(2, child: _buildStatsCard()),
              const SizedBox(height: 12),
              RxReveal.index(3, child: _buildQuickActionsCard(context)),
              const SizedBox(height: 28),
              RxReveal.index(
                4,
                child: Column(
                  children: [
                    RxSectionHeader(
                      title: 'Recent',
                      actionLabel: 'View all',
                      onAction: () => _open(const SearchExpenseScreen()),
                    ),
                    _buildFlatTransactionList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalHeader() {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
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
    final now = DateTime.now();
    return RxTabHeader(
      label: '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}',
      title: 'Expenses',
      actions: [
        RxCircleButton(
          icon: HugeIcons.strokeRoundedSearch01,
          semanticLabel: 'Search expenses',
          onTap: () => _open(const SearchExpenseScreen()),
        ),
      ],
    );
  }

  // Spent to date as the headline; a ring shows how much funding it used.
  Widget _buildHero() {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFunding = _totalFunding > 0;
    final usedRatio = hasFunding ? _totalExpenses / _totalFunding : 0.0;
    final over = hasFunding && _totalExpenses > _totalFunding;
    final usedPct = usedRatio * 100;
    final pctText = usedPct >= 10 || usedPct == 0
        ? usedPct.toStringAsFixed(0)
        : usedPct.toStringAsFixed(1);
    final ringColor = over
        ? rx.negative
        : usedRatio >= 0.8
        ? rx.warning
        : (isDark ? rx.accent : rx.inverse);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spent to date', style: RxText.label(context)),
              const SizedBox(height: 10),
              if (_isLoading)
                const RxSkeleton(width: 180, height: 46, radius: 12)
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatCurrency(_totalExpenses),
                    style: RxText.hero(context, size: 46),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                _isLoading
                    ? ' '
                    : hasFunding
                    ? over
                          ? 'Over your ${_formatCurrency(_totalFunding)} funding'
                          : 'of ${_formatCurrency(_totalFunding)} funding'
                    : 'Add funding to track your budget',
                maxLines: 2,
                style: RxText.caption(
                  context,
                  color: over ? rx.negative : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (_isLoading)
          const RxSkeleton(width: 96, height: 96, radius: 100)
        else
          RxRing(
            key: ValueKey('used-ring-$_chartEpoch'),
            size: 96,
            thickness: 9,
            value: hasFunding ? usedRatio.clamp(0.0, 1.0) : 0,
            color: ringColor,
            trackColor: rx.textPrimary.withValues(alpha: 0.08),
            semanticLabel: hasFunding
                ? '$pctText percent of funding used'
                : 'No funding added',
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    hasFunding ? '$pctText%' : '--',
                    style: RxText.value(
                      context,
                      size: 18,
                      color: over ? rx.negative : null,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text('used', style: RxText.micro(context)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStatsCard() {
    final rx = context.rx;
    final left = _totalFunding > 0 ? (_totalFunding - _totalExpenses) : 0.0;

    Widget half(String label, String value, String note, {Color? noteColor}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: RxText.label(context)),
              const SizedBox(height: 8),
              if (_isLoading)
                const RxSkeleton(width: 90, height: 24)
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: RxText.value(context, size: 20)),
                ),
              const SizedBox(height: 4),
              Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RxText.caption(context, color: noteColor),
              ),
            ],
          ),
        ),
      );
    }

    return RxCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            half(
              'Budget left',
              _formatCurrency(left),
              _totalFunding > 0
                  ? '${(left / _totalFunding * 100).toStringAsFixed(0)}% remaining'
                  : 'No funding yet',
              noteColor: left < 0 ? rx.negative : rx.positive,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(width: 1, color: rx.hairline),
            ),
            half('Avg. per day', _formatCurrency(_avgDaily), '30-day average'),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(BuildContext context) {
    return RxCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          _buildFlatActionButton(
            "Add",
            HugeIcons.strokeRoundedAdd01,
            () => _open(const AddExpenseScreen()),
          ),
          _buildFlatActionButton(
            "Scan",
            HugeIcons.strokeRoundedCamera01,
            () => _open(const ScanExpenseScreen()),
          ),
          _buildFlatActionButton(
            "Search",
            HugeIcons.strokeRoundedSearch01,
            () => _open(const SearchExpenseScreen(), reload: false),
          ),
          _buildFlatActionButton(
            "Report",
            HugeIcons.strokeRoundedChartBarLine,
            () => _open(const ReportExpenseScreen(), reload: false),
          ),
        ],
      ),
    );
  }

  Widget _buildFlatActionButton(
    String label,
    List<List<dynamic>> icon,
    VoidCallback onTap,
  ) {
    final rx = context.rx;
    return Expanded(
      child: RxPressable(
        onTap: onTap,
        semanticLabel: label,
        child: Column(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: rx.surfaceMuted,
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: HugeIcon(
                icon: icon,
                color: rx.textPrimary,
                size: 21,
                strokeWidth: 1.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: RxText.caption(
                context,
                color: rx.textPrimary,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlatTransactionList() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedUser,
          title: 'Not signed in',
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
          return RxCard(
            child: Column(
              children: [
                for (var i = 0; i < 4; i++) _buildSkeletonTransaction(),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          debugPrint("🚨 FIRESTORE ERROR: ${snapshot.error}");
          return const RxCard(
            child: RxEmptyState(
              icon: HugeIcons.strokeRoundedAlert02,
              title: "Couldn't load transactions",
              message: 'Pull to refresh or try again later',
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

        return RxCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < top5Expenses.length; i++) ...[
                if (i > 0) const RxDivider(indent: 52),
                _buildTransactionItem(
                  top5Expenses[i],
                  top5Expenses[i]['id'] as String,
                  context,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionItem(
    Map<String, dynamic> tx,
    String expenseId,
    BuildContext context,
  ) {
    final rx = context.rx;
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
      dateStr = rxFormatDate((tx['Date'] as Timestamp).toDate());
    }

    return RxPressable(
      onTap: () =>
          _open(ExpenseDetailsScreen(expenseId: expenseId, expenseData: tx)),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            RxIconTile(
              icon: RxCategory.icon(rawCategory),
              size: 40,
              iconSize: 19,
              background: RxCategory.soft(context, rawCategory),
              foreground: RxCategory.color(context, rawCategory),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: RxText.body(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr.isNotEmpty ? '$category · $dateStr' : category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RxText.caption(context),
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
                style: RxText.amount(
                  context,
                  color: isFunding ? rx.positive : rx.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonTransaction() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          RxSkeleton(width: 40, height: 40, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RxSkeleton(width: 140, height: 14),
                SizedBox(height: 6),
                RxSkeleton(width: 90, height: 11),
              ],
            ),
          ),
          RxSkeleton(width: 60, height: 14),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactionsState() {
    return RxCard(
      child: RxEmptyState(
        icon: HugeIcons.strokeRoundedInvoice01,
        title: 'No expenses yet',
        message: 'Add your first expense or scan a receipt to get started',
        actionLabel: 'Add expense',
        onAction: () => _open(const AddExpenseScreen()),
      ),
    );
  }
}
