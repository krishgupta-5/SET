import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../widgets/rx_ui.dart';
import '../../../widgets/rx_motion.dart';
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

  // --- UI (presentation only) ---

  /// Status pill colours for the value returned by [_getHealthStatus].
  ({String label, Color fg, Color bg}) _statusStyle() {
    final rx = context.rx;
    switch (_getHealthStatus()) {
      case "SAFE":
        return (label: 'Healthy', fg: rx.positive, bg: rx.positiveSoft);
      case "WARNING":
        return (label: 'Watch', fg: rx.warning, bg: rx.warningSoft);
      case "CRITICAL":
        return (label: 'Critical', fg: rx.negative, bg: rx.negativeSoft);
      case "DEPLETED":
        return (label: 'Depleted', fg: rx.negative, bg: rx.negativeSoft);
      case "NO EXPENSES":
        return (
          label: 'No expenses',
          fg: rx.textSecondary,
          bg: rx.surfaceMuted,
        );
      case "NO DATA":
        return (label: 'No data', fg: rx.textSecondary, bg: rx.surfaceMuted);
      default:
        return (label: 'Updating', fg: rx.textSecondary, bg: rx.surfaceMuted);
    }
  }

  String get _zeroMoney =>
      '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0';

  /// Big value + small unit for the hero, matching Home's readout.
  ({String value, String? unit}) _runwayParts() {
    if (isLoading) return (value: '--', unit: null);
    final m = runwayMonths ?? 0;
    if (m <= 0) return (value: '0', unit: 'months');
    if (m > 120) return (value: '10+', unit: 'years');
    if (m >= 12) {
      final v = (m / 12).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
      return (value: v, unit: v == '1' ? 'year' : 'years');
    }
    if (m >= 1) return (value: m.toStringAsFixed(1), unit: 'months');
    final d = (m * 30).round().clamp(1, 30);
    return (value: '$d', unit: d == 1 ? 'day' : 'days');
  }

  void _showProjectionHint() {
    final rx = context.rx;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Runway = cash left ÷ monthly burn. Assumes this month\'s burn stays flat.',
          style: RxText.body(context, color: rx.onInverse),
        ),
        backgroundColor: rx.inverse,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 4),
        elevation: 0,
      ),
    );
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
                title: 'Runway',
                trailing: RxCircleButton(
                  icon: HugeIcons.strokeRoundedRefresh,
                  semanticLabel: 'Refresh',
                  onTap: isLoading ? null : _loadData,
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadData,
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
                    // Sections rise in once their data lands; ones with
                    // nothing to show are left out entirely.
                    children: [
                      RxReveal(
                        key: ValueKey('hero-$isLoading'),
                        child: _buildHero(),
                      ),
                      if (isLoading || monthlyProjections.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        RxReveal(
                          key: ValueKey('chart-$isLoading'),
                          delay: const Duration(milliseconds: 60),
                          child: _buildChartCard(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      RxReveal(
                        key: ValueKey('stats-$isLoading'),
                        delay: const Duration(milliseconds: 120),
                        child: _buildStatsCard(),
                      ),
                      if (isLoading || monthlyProjections.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        RxReveal(
                          key: ValueKey('proj-$isLoading'),
                          delay: const Duration(milliseconds: 180),
                          child: Column(
                            children: [
                              RxSectionHeader(
                                title: 'Cash projection',
                                actionLabel: 'How it works',
                                onAction: _showProjectionHint,
                              ),
                              _buildProjectionCard(),
                            ],
                          ),
                        ),
                      ],
                      if (isLoading || _calculateRiskFactors().isNotEmpty) ...[
                        const SizedBox(height: 28),
                        RxReveal(
                          key: ValueKey('risk-$isLoading'),
                          delay: const Duration(milliseconds: 240),
                          child: Column(
                            children: [
                              const RxSectionHeader(title: 'Signals'),
                              _buildRiskCard(),
                            ],
                          ),
                        ),
                      ],
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

  // --- HERO ---
  Widget _buildHero() {
    final rx = context.rx;
    final status = _statusStyle();
    final parts = _runwayParts();
    final date = _cashOutLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Estimated runway', style: RxText.label(context)),
            const SizedBox(width: 8),
            RxPill(
              label: status.label,
              dot: true,
              foreground: status.fg,
              background: status.bg,
            ),
          ],
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(parts.value, style: RxText.hero(context, size: 60)),
              if (parts.unit != null) ...[
                const SizedBox(width: 8),
                Text(
                  parts.unit!,
                  style: RxText.value(
                    context,
                    size: 20,
                    color: rx.textSecondary,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: RxText.label(context),
            children: [
              const TextSpan(text: 'Cash runs out '),
              TextSpan(
                text: date,
                style: RxText.label(
                  context,
                  color: rx.textPrimary,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- CHART ---

  /// Checkpoint picked by tapping or dragging on the chart. 0 = today,
  /// k = monthlyProjections[k - 1]. UI state only.
  int? _scrubIndex;

  /// "832.5" months -> "69.4 years left"; short runways stay in months.
  String _leftLabel(String monthsLeft) {
    final m = double.tryParse(monthsLeft) ?? 0;
    if (m >= 24) return '${(m / 12).toStringAsFixed(1)} years left';
    return '${m.toStringAsFixed(1)} months left';
  }

  /// Axis-friendly money: drop a trailing ".00".
  String _axisMoney(String s) => s.replaceAll(RegExp(r'\.00$'), '');

  /// The date cash hits zero, taken from the same projection the chart
  /// draws, so the headline and the chart always agree.
  String get _cashOutLabel {
    if (isLoading) return '--';
    if (monthlyProjections.isNotEmpty) {
      return monthlyProjections.last['month'] as String;
    }
    return zeroCashDate ?? '--';
  }

  Widget _buildChartCard() {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isLoading) {
      return const RxCard(
        padding: EdgeInsets.all(18),
        child: RxSkeleton(height: 190, radius: 12),
      );
    }
    if (monthlyProjections.isEmpty) {
      return const RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedChartLineData01,
          title: 'No projection yet',
          message: 'Add funding and expenses to see how cash runs down',
        ),
      );
    }

    final n = monthlyProjections.length;
    final months = [
      'Now',
      for (final p in monthlyProjections) p['month'] as String,
    ];
    // Long horizons label the axis in years, short ones in months.
    final firstYear = int.tryParse(months[1].split(' ').last) ?? 0;
    final lastYear = int.tryParse(months.last.split(' ').last) ?? 0;
    final useYears = lastYear - firstYear >= 2;
    final xLabels = [
      'Now',
      for (var k = 1; k <= n; k++)
        useYears ? months[k].split(' ').last : months[k].split(' ').first,
    ];

    final start = currentBalance ?? _zeroMoney;
    // Checkpoint k sits at k/n of the runway, so the one at the halfway
    // mark holds exactly half the cash.
    final mid = n.isEven && n >= 2
        ? monthlyProjections[n ~/ 2 - 1]['balance'] as String
        : null;
    final yLabels = [
      _axisMoney(start),
      if (mid != null) _axisMoney(mid),
      _axisMoney(_zeroMoney),
    ];

    final sel = _scrubIndex;
    final String selValue;
    final String selWhen;
    final String selLeft;
    if (sel == null || sel == 0) {
      selValue = start;
      selWhen = 'Today';
      selLeft = runwayMonths != null
          ? _leftLabel(runwayMonths!.toStringAsFixed(1))
          : '';
    } else {
      final p = monthlyProjections[sel - 1];
      selValue = p['balance'] as String;
      selWhen = p['month'] as String;
      selLeft = p['isCashOut'] == true
          ? 'Cash runs out'
          : _leftLabel(p['monthsLeft'] as String);
    }
    final selIsCashOut = sel != null && sel == n;

    const gutter = 58.0;

    return RxCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Readout for the picked checkpoint (today by default).
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selWhen, style: RxText.caption(context)),
                    const SizedBox(height: 2),
                    Text(
                      selValue,
                      style: RxText.value(
                        context,
                        size: 20,
                        color: selIsCashOut ? rx.negative : null,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                selLeft,
                style: RxText.caption(
                  context,
                  color: selIsCashOut ? rx.negative : rx.textSecondary,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              int indexAt(double dx) {
                final plotW = width - gutter - 8;
                final t = ((dx - gutter) / plotW).clamp(0.0, 1.0);
                return (t * n).round().clamp(0, n);
              }

              void pick(double dx) {
                final k = indexAt(dx);
                if (k != _scrubIndex) {
                  HapticFeedback.selectionClick();
                  setState(() => _scrubIndex = k);
                }
              }

              return Semantics(
                label:
                    'Cash projection from $start today to zero in ${months.last}. Tap or drag to read a checkpoint.',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => pick(d.localPosition.dx),
                  onHorizontalDragStart: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: SizedBox(
                    height: 190,
                    width: width,
                    // Line draws itself from today to cash-out on open.
                    child: RxGrow(
                      value: 1,
                      duration: const Duration(milliseconds: 1000),
                      builder: (context, progress) => CustomPaint(
                        painter: _RunwayCurvePainter(
                          progress: progress,
                          line: rx.textPrimary,
                          grid: rx.hairline,
                          label: rx.textTertiary,
                          labelStrong: rx.textSecondary,
                          marker: isDark ? rx.accent : rx.inverse,
                          markerRing: rx.surface,
                          end: rx.negative,
                          points: n,
                          xLabels: xLabels,
                          yLabels: yLabels,
                          gutter: gutter,
                          selected: _scrubIndex,
                          fontFamily: RxText.family,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // --- CASH + BURN ---
  Widget _buildStatsCard() {
    final rx = context.rx;

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

    return RxCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            half('Cash available', currentBalance ?? _zeroMoney),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(width: 1, color: rx.hairline),
            ),
            half('Monthly burn', monthlyBurn ?? _zeroMoney),
          ],
        ),
      ),
    );
  }

  // --- PROJECTION TIMELINE ---
  Widget _buildProjectionCard() {
    if (isLoading) {
      return RxCard(
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    RxSkeleton(width: 10, height: 10, radius: 100),
                    SizedBox(width: 14),
                    Expanded(child: RxSkeleton(height: 14)),
                    SizedBox(width: 60),
                    RxSkeleton(width: 70, height: 14),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    if (monthlyProjections.isEmpty) {
      return const RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedCalendar03,
          title: 'Nothing to project',
          message: 'Checkpoints appear once there is a monthly burn',
        ),
      );
    }

    return RxCard(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        children: [
          for (var i = 0; i < monthlyProjections.length; i++)
            _buildProjectionRow(
              monthlyProjections[i]['month'] as String,
              monthlyProjections[i]['balance'] as String,
              monthlyProjections[i]['monthsLeft'] as String,
              isCashOut: monthlyProjections[i]['isCashOut'] == true,
              isFirst: i == 0,
              isLast: i == monthlyProjections.length - 1,
            ),
        ],
      ),
    );
  }

  /// One checkpoint on a vertical timeline: dot + connector, month, balance.
  Widget _buildProjectionRow(
    String month,
    String balance,
    String monthsLeft, {
    bool isCashOut = false,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final rx = context.rx;
    final dotColor = isCashOut ? rx.negative : rx.textPrimary;

    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isFirst ? Colors.transparent : rx.hairline,
                  ),
                ),
                Container(
                  width: isCashOut ? 12 : 9,
                  height: isCashOut ? 12 : 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCashOut ? rx.negative : rx.surface,
                    border: Border.all(color: dotColor, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isLast ? Colors.transparent : rx.hairline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          month,
                          style: RxText.body(
                            context,
                            color: isCashOut ? rx.negative : rx.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isCashOut ? 'Cash runs out' : _leftLabel(monthsLeft),
                          style: RxText.caption(
                            context,
                            color: isCashOut ? rx.negative : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    balance,
                    style: RxText.amount(
                      context,
                      color: isCashOut ? rx.negative : rx.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- SIGNALS ---
  Widget _buildRiskCard() {
    if (isLoading) {
      return const RxCard(
        child: Row(
          children: [
            RxSkeleton(width: 36, height: 36, radius: 11),
            SizedBox(width: 12),
            Expanded(child: RxSkeleton(height: 28)),
          ],
        ),
      );
    }

    final riskFactors = _calculateRiskFactors();
    if (riskFactors.isEmpty) {
      return const RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedTick02,
          title: 'No signals yet',
          message: 'We flag risks here once there is enough data',
        ),
      );
    }

    return RxCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < riskFactors.length; i++) ...[
            if (i > 0) const RxDivider(indent: 50),
            _buildRiskItem(
              riskFactors[i]['title'] as String,
              riskFactors[i]['description'] as String,
              riskFactors[i]['color'] as Color,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskItem(String title, String description, Color riskColor) {
    final rx = context.rx;
    // The logic tags each risk with a colour; map it to the theme palette.
    final List<List<dynamic>> icon;
    final Color fg;
    final Color bg;
    if (riskColor == const Color(0xFF10B981)) {
      icon = HugeIcons.strokeRoundedTick02;
      fg = rx.positive;
      bg = rx.positiveSoft;
    } else if (riskColor == const Color(0xFFEF4444)) {
      icon = HugeIcons.strokeRoundedAlert02;
      fg = rx.negative;
      bg = rx.negativeSoft;
    } else {
      icon = HugeIcons.strokeRoundedAlert02;
      fg = rx.warning;
      bg = rx.warningSoft;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RxIconTile(
            icon: icon,
            size: 38,
            iconSize: 18,
            background: bg,
            foreground: fg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: RxText.body(context)),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: RxText.caption(context).copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
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
}

/// Cash run-down chart: value axis on the left (start, halfway, zero),
/// date labels under each checkpoint, a straight line from today's cash to
/// zero (the projection assumes a flat monthly burn), and an optional
/// highlighted checkpoint with a vertical guide.
class _RunwayCurvePainter extends CustomPainter {
  _RunwayCurvePainter({
    this.progress = 1,
    required this.line,
    required this.grid,
    required this.label,
    required this.labelStrong,
    required this.marker,
    required this.markerRing,
    required this.end,
    required this.points,
    required this.xLabels,
    required this.yLabels,
    required this.gutter,
    required this.selected,
    required this.fontFamily,
  });

  /// 0..1: how much of the line is drawn (entrance animation).
  final double progress;
  final Color line;
  final Color grid;
  final Color label;
  final Color labelStrong;
  final Color marker;
  final Color markerRing;
  final Color end;
  final int points;
  final List<String> xLabels; // points + 1 entries, index 0 = today
  final List<String> yLabels; // top to bottom, evenly spaced
  final double gutter;
  final int? selected;
  final String fontFamily;

  static const _xAxisH = 22.0;
  static const _topPad = 8.0;
  static const _rightPad = 8.0;

  TextPainter _text(
    String s,
    Color c, {
    double maxWidth = 200,
    bool bold = false,
  }) {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 11,
          height: 1,
          color: c,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final left = gutter;
    final right = size.width - _rightPad;
    final top = _topPad;
    final bottom = size.height - _xAxisH;
    final w = right - left;
    final h = bottom - top;
    Offset at(double t) => Offset(left + w * t, top + h * t);

    // Y axis: dashed gridlines with right-aligned labels in the gutter.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < yLabels.length; i++) {
      final f = yLabels.length == 1 ? 0.0 : i / (yLabels.length - 1);
      final y = top + h * f;
      for (double x = left; x < right; x += 7) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + 3.5).clamp(left, right), y),
          gridPaint,
        );
      }
      final tp = _text(yLabels[i], label, maxWidth: gutter - 10);
      tp.paint(canvas, Offset(gutter - 10 - tp.width, y - tp.height / 2));
    }

    // Area + line, drawn up to [progress].
    final pr = progress.clamp(0.0, 1.0);
    final area = Path()
      ..moveTo(at(0).dx, at(0).dy)
      ..lineTo(at(pr).dx, at(pr).dy)
      ..lineTo(at(pr).dx, at(1).dy)
      ..lineTo(at(0).dx, at(1).dy)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.12), line.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(left, top, right, bottom)),
    );
    canvas.drawLine(
      at(0),
      at(pr),
      Paint()
        ..color = line
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Selection guide behind the dots.
    if (selected != null) {
      final p = at(selected! / points);
      canvas.drawLine(
        Offset(p.dx, top),
        Offset(p.dx, bottom),
        Paint()
          ..color = labelStrong.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }

    // Checkpoints pop in as the line reaches them.
    double pop(double t) => ((pr - t) / 0.08 + 1).clamp(0.0, 1.0);
    final ring = Paint()..color = markerRing;
    for (var k = 1; k < points; k++) {
      final s = pop(k / points);
      if (s <= 0) continue;
      final p = at(k / points);
      final isSel = selected == k;
      canvas.drawCircle(p, (isSel ? 7 : 4.5) * s, ring);
      canvas.drawCircle(p, (isSel ? 5 : 3) * s, Paint()..color = line);
    }
    final isEndSel = selected == points;
    final se = pop(1);
    if (se > 0) {
      canvas.drawCircle(at(1), (isEndSel ? 8 : 6.5) * se, ring);
      canvas.drawCircle(at(1), (isEndSel ? 6 : 5) * se, Paint()..color = end);
    }
    final isTodaySel = selected == 0;
    canvas.drawCircle(at(0), isTodaySel ? 8.5 : 7, ring);
    canvas.drawCircle(at(0), isTodaySel ? 7 : 5.5, Paint()..color = marker);

    // X axis labels under each checkpoint; edges stay inside the chart.
    final slot = w / points;
    for (var k = 0; k <= points && k < xLabels.length; k++) {
      final isSel = selected == k;
      final color = k == points ? end : (isSel ? labelStrong : label);
      final tp = _text(xLabels[k], color, maxWidth: slot + 6, bold: isSel);
      final cx = left + w * (k / points);
      final dx = (cx - tp.width / 2).clamp(left - 4, size.width - tp.width);
      tp.paint(canvas, Offset(dx, bottom + 8));
    }
  }

  @override
  bool shouldRepaint(covariant _RunwayCurvePainter old) =>
      old.progress != progress ||
      old.line != line ||
      old.grid != grid ||
      old.label != label ||
      old.marker != marker ||
      old.markerRing != markerRing ||
      old.end != end ||
      old.points != points ||
      old.selected != selected ||
      old.gutter != gutter ||
      old.xLabels.join() != xLabels.join() ||
      old.yLabels.join() != yLabels.join();
}
