import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/financial_data_service.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
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

class MonthlyBurnScreen extends StatefulWidget {
  const MonthlyBurnScreen({super.key});

  @override
  State<MonthlyBurnScreen> createState() => _MonthlyBurnScreenState();
}

class _MonthlyBurnScreenState extends State<MonthlyBurnScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  String _userCountryCode = '+1'; // Default to USD
  final bool _isLoadingCountry = false;

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shimmerController.repeat();
    _loadFinancialData();
    _setupRealtimeListeners();
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _expensesSubscription?.cancel();
    _teamMembersSubscription?.cancel();
    _companySubscription?.cancel();
    _debounceTimer?.cancel();
    _realtimeDebounceTimer?.cancel();
    _shimmerController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) {
      setState(() {
        _userCountryCode =
            CurrencyPreferenceService.getCurrencyPreferenceSync();
      });
      _loadFinancialData();
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

  String _selectedRange = "6M";
  final List<String> _ranges = ["1M", "3M", "6M", "YTD", "ALL"];

  Map<String, dynamic>? _financialData;
  Map<String, dynamic>? _teamCostData;
  List<Map<String, dynamic>>? _rawTeamsData;
  Map<String, double>? _actualSpendingPerTeam;
  Map<String, Map<String, dynamic>>? _budgetVarianceData;
  bool _isRefreshing = false;
  String? _error;

  bool _mainCardLoaded = false;
  bool _trendLoaded = false;
  bool _categoriesLoaded = false;
  bool _teamsLoaded = false;
  bool _forecastLoaded = false;

  Timer? _debounceTimer;
  Timer? _realtimeDebounceTimer;

  StreamSubscription? _expensesSubscription;
  StreamSubscription? _teamMembersSubscription;
  StreamSubscription? _companySubscription;

  Future<void> _loadFinancialData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isRefreshing = true;
        _error = null;
        _mainCardLoaded = false;
        _trendLoaded = false;
        _categoriesLoaded = false;
        _teamsLoaded = false;
        _forecastLoaded = false;
      });
    } else {
      if (mounted) {
        setState(() {
          _isRefreshing = true;
          _error = null;
        });
      }
    }

    try {
      final results = await Future.wait([
        FinancialDataService.getMonthlyBurnData().catchError(
          (e) => <String, dynamic>{},
        ),
        FinancialDataService.getUnifiedTeamCostData().catchError(
          (e) => <String, dynamic>{},
        ),
        FinancialDataService.getRawTeamsData().catchError(
          (e) => <Map<String, dynamic>>[],
        ),
        FinancialDataService.getActualSpendingPerTeam().catchError(
          (e) => <String, double>{},
        ),
        FinancialDataService.getBudgetVarianceAnalysis(
          FirebaseAuth.instance.currentUser!.uid,
        ).catchError((e) => <String, Map<String, dynamic>>{}),
      ]);

      if (mounted) {
        setState(() {
          _financialData = results[0] as Map<String, dynamic>?;
          _teamCostData = results[1] as Map<String, dynamic>?;
          _rawTeamsData = results[2] as List<Map<String, dynamic>>?;
          _actualSpendingPerTeam = results[3] as Map<String, double>?;
          _budgetVarianceData =
              results[4] as Map<String, Map<String, dynamic>>?;

          _mainCardLoaded = true;
          _trendLoaded = true;
          _categoriesLoaded = true;
          _teamsLoaded = true;
          _forecastLoaded = true;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Failed to load financial data: ${e.toString()}";
          _isRefreshing = false;
        });
      }
    }
  }

  void _setupRealtimeListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _expensesSubscription = FirebaseFirestore.instance
        .collection('expenses')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((_) => _handleRealtimeUpdate());

    _teamMembersSubscription = FirebaseFirestore.instance
        .collection('members')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((_) => _handleRealtimeUpdate());

    _companySubscription = FirebaseFirestore.instance
        .collection('companies')
        .doc(user.uid)
        .snapshots()
        .listen((_) => _handleRealtimeUpdate());
  }

  void _handleRealtimeUpdate() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      FinancialDataService.clearAllCache();
      _loadFinancialData(silent: true);
    });
  }

  void _onRangeChanged(String newRange) {
    if (_selectedRange == newRange || _isRefreshing) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      setState(() => _selectedRange = newRange);
      _loadFinancialData();
    });
  }

  int _getMonthsCount() {
    switch (_selectedRange) {
      case "1M":
        return 1;
      case "3M":
        return 3;
      case "6M":
        return 6;
      case "YTD":
        return DateTime.now().month;
      case "ALL":
        return 999;
      default:
        return 6;
    }
  }

  String _formatCurrencyForForecast(double amount) {
    return _isLoadingCountry
        ? CurrencyFormatter.formatCompact(amount, countryCode: '+91')
        : CurrencyFormatter.formatByCountryCompact(amount, _userCountryCode);
  }

  String _getCategoryDisplayName(String categoryKey) {
    switch (categoryKey.toLowerCase()) {
      case 'salaries':
        return 'Salary';
      case 'marketing':
        return 'Marketing';
      case 'infrastructure':
        return 'Infrastructure';
      case 'office':
        return 'Office Rent';
      case 'software':
        return 'Software';
      case 'hardware':
        return 'Hardware';
      case 'transport':
        return 'Transport';
      case 'design':
        return 'Design';
      case 'others':
        return 'Others';
      case 'travel':
        return 'Travel';
      case 'meals':
        return 'Meals';
      case 'contractors':
        return 'Contractors';
      case 'legal':
        return 'Legal';
      default:
        return _capitalizeFirstLetter(categoryKey);
    }
  }

  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  // --- UI BUILDING (presentation only) ---

  String get _zeroMoney => _isLoadingCountry
      ? "₹0"
      : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0";

  String _money(double amount) =>
      amount > 0 ? _formatCurrencyForForecast(amount) : _zeroMoney;

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
                title: 'Monthly burn',
                trailing: RxCircleButton(
                  icon: HugeIcons.strokeRoundedRefresh,
                  semanticLabel: 'Refresh',
                  onTap: _isRefreshing ? null : _loadFinancialData,
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _loadFinancialData();
                  },
                  color: rx.textPrimary,
                  backgroundColor: rx.surface,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      MediaQuery.paddingOf(context).bottom + 32,
                    ),
                    children: [
                      RxReveal.index(0, child: _buildRangeSelector()),
                      const SizedBox(height: 24),
                      RxReveal(
                        key: ValueKey('hero-$_mainCardLoaded'),
                        delay: const Duration(milliseconds: 60),
                        child: _mainCardLoaded
                            ? _buildHeroCard()
                            : _buildSkeletonCard(),
                      ),
                      // Sections with nothing to show are left out.
                      ..._section(
                        2,
                        _trendTitle(),
                        _trendLoaded,
                        _buildBurnTrendCard,
                      ),
                      ..._section(
                        3,
                        'By category',
                        _categoriesLoaded,
                        _buildExpenseCategoriesCard,
                      ),
                      ..._section(
                        4,
                        'By team',
                        _teamsLoaded,
                        _buildTeamCostCard,
                      ),
                      ..._section(
                        5,
                        'Budget vs actual',
                        _forecastLoaded,
                        _buildForecastComparisonCard,
                      ),
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

  /// Header + card, revealed when its data lands. Returns nothing when the
  /// card has no data, so empty boxes never show.
  List<Widget> _section(
    int index,
    String title,
    bool loaded,
    Widget? Function() build,
  ) {
    final card = loaded ? build() : _buildSkeletonCard();
    if (card == null) return const [];
    return [
      const SizedBox(height: 28),
      RxReveal(
        key: ValueKey('$title-$loaded'),
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

  String _trendTitle() {
    final count = _getMonthsCount();
    if (_selectedRange == "YTD") return 'Year to date';
    if (_selectedRange == "ALL") return 'All time';
    return count == 1 ? 'This month' : 'Last $count months';
  }

  // Segmented control. Switches instantly: it is a frequent action.
  Widget _buildRangeSelector() {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const labels = {
      "1M": "1M",
      "3M": "3M",
      "6M": "6M",
      "YTD": "YTD",
      "ALL": "All",
    };

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: rx.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: _ranges.map((range) {
          final selected = _selectedRange == range;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: labels[range] ?? range,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onRangeChanged(range),
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // Inner radius = outer (14) - padding (3).
                    borderRadius: BorderRadius.circular(11),
                    color: selected ? rx.surface : Colors.transparent,
                    boxShadow: selected && !isDark
                        ? const [
                            BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[range] ?? range,
                    style:
                        RxText.label(
                          context,
                          color: selected ? rx.textPrimary : rx.textSecondary,
                        ).copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- HERO ---
  // Flat on the page like Home's runway: one big number, one supporting row.
  Widget _buildHeroCard() {
    if (_error != null) return _buildErrorState();
    final rx = context.rx;

    final grossBurn = _toDouble(_financialData?['grossBurn']);
    final netBurn = _toDouble(_financialData?['netBurn']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gross burn per month', style: RxText.label(context)),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_money(grossBurn), style: RxText.hero(context, size: 52)),
        ),
        const SizedBox(height: 18),
        RxCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(
            children: [
              Expanded(child: Text('Net burn', style: RxText.label(context))),
              Text(
                _money(netBurn),
                style: RxText.amount(
                  context,
                  color: netBurn > 0 ? rx.negative : rx.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TREND ---
  Widget? _buildBurnTrendCard() {
    if (_error != null) return _buildErrorState();
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = _getMonthsCount();

    List<Map<String, dynamic>> trendData = List<Map<String, dynamic>>.from(
      _financialData?['trendData'] ?? [],
    );
    List<Map<String, dynamic>> displayData = [];

    if (trendData.isNotEmpty) {
      bool isNewestFirst = trendData.first['isCurrentMonth'] == true;
      if (isNewestFirst) {
        displayData = trendData.take(count).toList().reversed.toList();
      } else {
        displayData = trendData.length > count
            ? trendData.sublist(trendData.length - count)
            : trendData;
      }
    }

    final maxAmount = displayData
        .map((d) => _toDouble(d['amount']))
        .fold<double>(0, (a, b) => a > b ? a : b);
    if (displayData.isEmpty || maxAmount <= 0) return null;
    const chartHeight = 120.0;
    // Many bars (YTD / All) get thinner gaps and drop the axis labels.
    final dense = displayData.length > 8;
    final labelSpace = dense ? 0.0 : 24.0;
    final activeColor = isDark ? rx.accent : rx.inverse;

    return RxCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: SizedBox(
        height: chartHeight + labelSpace,
        child: Stack(
          children: [
            for (final f in const [0.0, 1 / 3, 2 / 3])
              Positioned(
                left: 0,
                right: 0,
                bottom: labelSpace + chartHeight * f,
                child: Container(height: 1, color: rx.hairline),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < displayData.length; i++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final d = displayData[i];
                        final amount = _toDouble(d['amount']);
                        final isActive = d['isCurrentMonth'] as bool? ?? false;
                        final pct = maxAmount > 0
                            ? (amount / maxAmount).clamp(0.0, 1.0)
                            : 0.0;
                        // Spread the cascade over ~420ms however many bars.
                        final step = 420 ~/ displayData.length.clamp(6, 60);
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Center(
                              // Grows up from the axis; replays per range.
                              child: RxGrow(
                                key: ValueKey('bar-$_selectedRange-$i'),
                                value: pct,
                                delay: Duration(milliseconds: step * i),
                                builder: (context, v) => Container(
                                  width: dense ? null : 26,
                                  height: (chartHeight * v).clamp(
                                    dense ? 3.0 : 4.0,
                                    chartHeight,
                                  ),
                                  margin: EdgeInsets.symmetric(
                                    horizontal: dense ? 1.5 : 0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? activeColor
                                        : rx.textPrimary.withValues(
                                            alpha: 0.08,
                                          ),
                                    borderRadius: BorderRadius.circular(
                                      dense ? 3 : 7,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (!dense)
                              SizedBox(
                                height: labelSpace,
                                child: Center(
                                  child: Text(
                                    d['month']?.toString() ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: RxText.micro(
                                      context,
                                      color: isActive
                                          ? rx.textPrimary
                                          : rx.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- CATEGORIES ---
  Widget? _buildExpenseCategoriesCard() {
    if (_error != null) return _buildErrorState();
    final rx = context.rx;

    final rawCategories =
        _financialData?['categoryBreakdown'] as Map<String, dynamic>? ?? {};
    final Map<String, double> categoryBreakdown = {};
    rawCategories.forEach((k, v) => categoryBreakdown[k] = _toDouble(v));

    final budgetVariance = _budgetVarianceData ?? {};
    Map<String, dynamic> combinedData = {};

    for (var entry in categoryBreakdown.entries) {
      combinedData[entry.key] = {
        'actual': entry.value,
        'budget': 0.0,
        'variance': -entry.value,
        'variancePercentage': 0.0,
        'isOverBudget': true,
        'hasBudget': false,
      };
    }

    for (var entry in budgetVariance.entries) {
      combinedData[entry.key] = entry.value;
    }

    final sortedEntries = combinedData.entries
        .where((entry) => _toDouble(entry.value['actual']) > 0)
        .toList();
    sortedEntries.sort(
      (a, b) =>
          _toDouble(b.value['actual']).compareTo(_toDouble(a.value['actual'])),
    );

    final totalActual = sortedEntries.fold<double>(
      0.0,
      (acc, item) => acc + _toDouble(item.value['actual']),
    );

    if (combinedData.isEmpty || sortedEntries.isEmpty) return null;

    return RxCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 4),
      child: Column(
        children: [
          // Donut of the period's spend; sweeps in again per range.
          RxDonut(
            key: ValueKey('cat-donut-$_selectedRange'),
            size: 168,
            thickness: 16,
            segments: [
              for (final e in sortedEntries)
                RxDonutSegment(
                  value: _toDouble(e.value['actual']),
                  color: RxCategory.color(context, e.key),
                ),
            ],
            trackColor: rx.textPrimary.withValues(alpha: 0.06),
            semanticLabel: 'Spending by category',
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total', style: RxText.caption(context)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatCurrencyForForecast(totalActual),
                    style: RxText.value(context, size: 20),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${sortedEntries.length} ${sortedEntries.length == 1 ? 'category' : 'categories'}',
                  style: RxText.micro(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < sortedEntries.length; i++) ...[
            if (i > 0) const RxDivider(indent: 22),
            Builder(
              builder: (context) {
                final entry = sortedEntries[i];
                final categoryData = entry.value;
                final budget = _toDouble(categoryData['budget']);
                final actual = _toDouble(categoryData['actual']);
                final variancePercentage = _toDouble(
                  categoryData['variancePercentage'],
                );
                final isOverBudget =
                    categoryData['isOverBudget'] as bool? ?? false;
                final hasBudget = categoryData['hasBudget'] as bool? ?? false;
                final share = totalActual > 0 ? actual / totalActual : 0.0;

                return _buildRow(
                  dot: RxCategory.color(context, entry.key),
                  title: _getCategoryDisplayName(entry.key),
                  subtitle: hasBudget
                      ? 'Budget ${_formatCurrencyForForecast(budget)}'
                      : '${(share * 100).toStringAsFixed(1)}% of spend',
                  amount: _formatCurrencyForForecast(actual),
                  trailingNote: hasBudget
                      ? '${variancePercentage.abs().toStringAsFixed(1)}% ${isOverBudget ? 'over' : 'under'}'
                      : null,
                  trailingNoteColor: hasBudget
                      ? (isOverBudget ? rx.negative : rx.positive)
                      : null,
                  progress: hasBudget && budget > 0
                      ? (actual / budget).clamp(0.0, 1.0)
                      : null,
                  progressColor: isOverBudget ? rx.negative : rx.inverse,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // --- TEAMS ---
  Widget? _buildTeamCostCard() {
    if (_error != null) return _buildErrorState();

    final teamCosts =
        (_teamCostData?['teamCosts'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            // Teams with no cost in the period add nothing to the chart.
            .where((t) => _toDouble(t['cost']) > 0)
            .toList() ??
        [];

    if (teamCosts.isEmpty) return null;

    return RxCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < teamCosts.length; i++) ...[
            if (i > 0) const RxDivider(indent: 22),
            Builder(
              builder: (context) {
                final team = teamCosts[i];
                final name = team['name']?.toString() ?? 'Team';
                final amount = _toDouble(team['cost']);
                final pct = _toDouble(team['pct']);
                return _buildRow(
                  dot: RxCategory.color(context, name),
                  title: name,
                  subtitle: '${(pct * 100).toStringAsFixed(1)}% of total',
                  amount: _formatCurrencyForForecast(amount),
                  progress: pct.clamp(0.0, 1.0),
                  progressColor: RxCategory.color(context, name),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // --- BUDGET VS ACTUAL ---
  Widget? _buildForecastComparisonCard() {
    if (_error != null) return _buildErrorState();
    final rx = context.rx;

    final rawTeamsData = _rawTeamsData ?? [];

    if (rawTeamsData.isEmpty) return null;

    double totalBudget = 0;
    double totalActual = 0;
    List<Map<String, dynamic>> comparisonData = [];

    for (var team in rawTeamsData) {
      final teamName = team['teamName'] as String? ?? 'Unknown Team';
      dynamic budgetData = team['monthlyBudget'];
      double budget = 0.0;

      if (budgetData != null) {
        if (budgetData is double) {
          budget = budgetData;
        } else if (budgetData is int) {
          budget = budgetData.toDouble();
        } else if (budgetData is String) {
          String budgetStr = budgetData.replaceAll(RegExp(r'[^\d.]'), '');
          budget = double.tryParse(budgetStr) ?? 0.0;
        }
      }

      final actual = _toDouble(
        _actualSpendingPerTeam?[teamName],
        fallback: 0.0,
      );
      final variance = budget - actual;

      totalBudget += budget;
      totalActual += actual;

      comparisonData.add({
        'team': teamName,
        'budget': budget,
        'actual': actual,
        'variance': variance,
        'isOver': variance < 0,
      });
    }

    return RxCard(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: Column(
        children: [
          for (var i = 0; i < comparisonData.length; i++) ...[
            if (i > 0) const RxDivider(),
            Builder(
              builder: (context) {
                final data = comparisonData[i];
                final isOver = data['isOver'] == true;
                final budget = _toDouble(data['budget']);
                final actual = _toDouble(data['actual']);
                final diff = _formatCurrencyForForecast(
                  _toDouble(data['variance']).abs(),
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data['team']?.toString() ?? 'Unknown',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RxText.body(context),
                            ),
                          ),
                          RxPill(
                            label: '$diff ${isOver ? 'over' : 'under'}',
                            foreground: isOver ? rx.negative : rx.positive,
                            background: isOver
                                ? rx.negativeSoft
                                : rx.positiveSoft,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildTrack(
                        budget > 0 ? (actual / budget).clamp(0.0, 1.0) : 0.0,
                        isOver ? rx.negative : rx.inverse,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${_formatCurrencyForForecast(actual)} spent',
                            style: RxText.caption(
                              context,
                              color: rx.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'of ${_formatCurrencyForForecast(budget)}',
                            style: RxText.caption(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: rx.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total budget', style: RxText.caption(context)),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrencyForForecast(totalBudget),
                        style: RxText.amount(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total actual', style: RxText.caption(context)),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrencyForForecast(totalActual),
                        style: RxText.amount(
                          context,
                          color: totalActual > totalBudget && totalBudget > 0
                              ? rx.negative
                              : rx.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- SHARED ROW ---
  // Same dot + name + amount row as Home's "Where it goes".
  Widget _buildRow({
    required Color dot,
    required String title,
    required String subtitle,
    required String amount,
    String? trailingNote,
    Color? trailingNoteColor,
    double? progress,
    Color? progressColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RxText.body(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(amount, style: RxText.amount(context)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RxText.caption(context),
                      ),
                    ),
                    if (trailingNote != null)
                      Text(
                        trailingNote,
                        style: RxText.caption(
                          context,
                          color: trailingNoteColor,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 10),
                  _buildTrack(progress, progressColor ?? context.rx.inverse),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrack(double value, Color color) {
    final rx = context.rx;
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(color: rx.textPrimary.withValues(alpha: 0.07)),
            // Fills from the left on open and whenever the range changes.
            RxGrow(
              key: ValueKey('track-$_selectedRange'),
              // Keep a sliver visible for tiny values.
              value: value <= 0 ? 0.02 : value.clamp(0.0, 1.0),
              delay: const Duration(milliseconds: 120),
              builder: (context, v) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final rx = context.rx;
    return RxCard(
      child: Row(
        children: [
          RxIconTile(
            icon: HugeIcons.strokeRoundedAlert02,
            size: 36,
            iconSize: 18,
            background: rx.negativeSoft,
            foreground: rx.negative,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text("Couldn't load this data", style: RxText.body(context)),
          ),
          RxPressable(
            onTap: _loadFinancialData,
            semanticLabel: 'Retry',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'Retry',
                style: RxText.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Calm pulse instead of a sweeping shimmer; static under reduced motion.
  Widget _buildSkeletonCard() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget body = const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RxSkeleton(width: 110, height: 14),
        SizedBox(height: 14),
        RxSkeleton(width: 180, height: 30),
        SizedBox(height: 18),
        RxSkeleton(height: 12),
        SizedBox(height: 10),
        RxSkeleton(width: 140, height: 12),
      ],
    );
    if (!reduceMotion) {
      body = AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          final t = _shimmerController.value;
          // 1 -> 0.55 -> 1 over the controller's 1.5s loop.
          final opacity = 0.55 + 0.45 * (1 - (2 * t - 1).abs());
          return Opacity(opacity: opacity, child: child);
        },
        child: body,
      );
    }
    return RxCard(padding: const EdgeInsets.all(20), child: body);
  }
}
