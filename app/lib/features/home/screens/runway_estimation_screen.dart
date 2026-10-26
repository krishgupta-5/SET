import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/financial_calculator.dart';
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

  // Raw numbers behind the cash chart (0 when there is nothing to project).
  double _chartCash = 0;
  double _chartBurn = 0;

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

      // Same snapshot the dashboard uses, so runway matches everywhere.
      final s = await FinancialCalculator.load(user.uid);
      if (!mounted) return;
      allExpenses = s.expenses;
      final zeroStr =
          '${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0';

      if (s.monthlyBurn <= 0 || s.availableFunds <= 0) {
        setState(() {
          runwayMonths = 0.0;
          currentBalance = _formatCurrency(
            s.availableFunds < 0 ? 0 : s.availableFunds,
          );
          monthlyBurn = s.monthlyBurn > 0
              ? _formatCurrency(s.monthlyBurn)
              : zeroStr;
          netBurn = s.monthlyBurn > 0 ? _formatCurrency(s.netBurn) : zeroStr;
          zeroCashDate = s.availableFunds <= 0
              ? (s.funding == 0 ? 'Awaiting funding' : 'Funds depleted')
              : 'Add expenses to track';
          monthlyProjections = [];
          _chartCash = 0;
          _chartBurn = 0;
          isLoading = false;
        });
        return;
      }

      final profitable = s.netBurn <= 0;
      setState(() {
        runwayMonths = s.runwayMonths;
        currentBalance = _formatCurrency(s.availableFunds);
        monthlyBurn = _formatCurrency(s.monthlyBurn);
        // Net burn = this month's gross burn minus this month's revenue.
        netBurn = _formatCurrency(s.netBurn);
        zeroCashDate = profitable
            ? 'Profitable'
            : _calculateZeroCashDate(s.runwayMonths);
        monthlyProjections = profitable
            ? []
            : _generateMonthlyProjections(s.availableFunds, s.netBurn);
        _chartCash = profitable ? 0 : s.availableFunds;
        _chartBurn = profitable ? 0 : s.netBurn;
        isLoading = false;
      });
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
      _chartCash = 0;
      _chartBurn = 0;
      isLoading = false;
    });
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

  /// Chart x picked by touching or dragging (null = not touching). UI only.
  double? _touchX;

  static const _mon = [
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

  /// "26 Oct 2026"
  String _fullDate(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';

  /// Time left as a person would say it: days, then months, then years.
  String _timeLeft(double days) {
    if (days < 1) return 'Under a day left';
    if (days < 60) {
      final d = days.round();
      return '$d ${d == 1 ? 'day' : 'days'} left';
    }
    final m = days / 30.44;
    if (m < 24) return '${m.toStringAsFixed(1)} months left';
    return '${(m / 12).toStringAsFixed(1)} years left';
  }

  /// Short money for the value axis: ₹10K, ₹2.5L, $1.2M.
  String _axisMoney(double v) {
    final sym = CurrencyFormatter.getCurrencySymbol(_userCountryCode);
    if (v <= 0) return '${sym}0';
    String n(double x) => x >= 100
        ? x.toStringAsFixed(0)
        : x.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    final inr = _userCountryCode == '+91';
    if (inr) {
      if (v >= 1e7) return '$sym${n(v / 1e7)}Cr';
      if (v >= 1e5) return '$sym${n(v / 1e5)}L';
    } else {
      if (v >= 1e9) return '$sym${n(v / 1e9)}B';
      if (v >= 1e6) return '$sym${n(v / 1e6)}M';
    }
    if (v >= 1e3) return '$sym${n(v / 1e3)}K';
    return '$sym${v.round()}';
  }

  /// "832.5" months -> "69.4 years left"; short runways stay in months.
  String _leftLabel(String monthsLeft) {
    final m = double.tryParse(monthsLeft) ?? 0;
    if (m >= 24) return '${(m / 12).toStringAsFixed(1)} years left';
    return '${m.toStringAsFixed(1)} months left';
  }

  /// The date cash hits zero, taken from the same projection the chart
  /// draws, so the headline and the chart always agree.
  String get _cashOutLabel {
    if (isLoading) return '--';
    if (monthlyProjections.isNotEmpty) {
      return monthlyProjections.last['month'] as String;
    }
    return zeroCashDate ?? '--';
  }

  /// Cash run-down chart (fl_chart). Reads like a stock chart:
  /// - x is real time from today to the day cash hits zero, labelled with
  ///   evenly spaced dates that never repeat;
  /// - y is cash left, labelled in short money (₹10K, ₹5K, ₹0);
  /// - the line is coloured by the same thresholds as the status pill:
  ///   green with 6+ months left, amber for 3-6, red under 3;
  /// - touch and drag to read the cash left on any date in the header.
  Widget _buildChartCard() {
    final rx = context.rx;

    if (isLoading) {
      return const RxCard(
        padding: EdgeInsets.all(18),
        child: RxSkeleton(height: 250, radius: 12),
      );
    }
    if (monthlyProjections.isEmpty || _chartCash <= 0 || _chartBurn <= 0) {
      return const RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedChartLineData01,
          title: 'No projection yet',
          message: 'Add funding and expenses to see how cash runs down',
        ),
      );
    }

    final cash = _chartCash;
    final totalDays = cash / _chartBurn * 30.44;
    final totalMonths = totalDays / 30.44;
    final now = DateTime.now();

    // x runs 0..ticks with one date label per whole step, so labels are
    // evenly spaced in time. y is cash as a share of today's balance.
    final ticks = totalDays >= 4 ? 4 : (totalDays >= 2 ? 2 : 1);
    final maxX = ticks.toDouble();
    double daysAt(double x) => x / maxX * totalDays;
    DateTime dateAt(double x) =>
        now.add(Duration(minutes: (daysAt(x) * 1440).round()));
    final cashOut = dateAt(maxX);

    // Day labels for short runways, month labels for medium, years for
    // long ones. Steps are wide enough that two labels never match.
    String axisDate(DateTime d) {
      if (totalDays <= 150) return '${d.day} ${_mon[d.month - 1]}';
      if (totalDays <= 4 * 365) {
        final yy = (d.year % 100).toString().padLeft(2, '0');
        return "${_mon[d.month - 1]} '$yy";
      }
      return '${d.year}';
    }

    // Status colour for a point on the line, from the months left there.
    Color colorAt(double x) {
      final left = totalMonths * (1 - x / maxX);
      if (left > 6) return rx.positive;
      if (left > 3) return rx.warning;
      return rx.negative;
    }

    final zoned = totalMonths > 3;
    final f6 = (1 - 6 / totalMonths).clamp(0.0, 1.0);
    final f3 = (1 - 3 / totalMonths).clamp(0.0, 1.0);
    LinearGradient zones(double alpha) => LinearGradient(
      colors: [
        for (final c in [
          rx.positive,
          rx.positive,
          rx.warning,
          rx.warning,
          rx.negative,
          rx.negative,
        ])
          c.withValues(alpha: alpha),
      ],
      stops: [0, f6, f6, f3, f3, 1],
    );

    // Readout: today by default, the touched date while dragging.
    final sel = _touchX;
    final selCash = sel == null ? cash : cash * (1 - sel / maxX);
    final selIsEnd = sel != null && sel >= maxX - 1e-6;

    const steps = 48;
    List<FlSpot> spotsUpTo(double p) {
      final end = maxX * p;
      final out = <FlSpot>[];
      for (var i = 0; i <= steps; i++) {
        final x = maxX * i / steps;
        if (x > end + 1e-9) break;
        out.add(FlSpot(x, 1 - x / maxX));
      }
      if (out.last.x < end - 1e-9) out.add(FlSpot(end, 1 - end / maxX));
      return out;
    }

    FlDotPainter ringDot(Color c, {double r = 5}) => FlDotCirclePainter(
      radius: r,
      color: c,
      strokeWidth: 3,
      strokeColor: rx.surface,
    );

    LineChartData chartData(double p) {
      final done = p >= 1;
      return LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: 1.12,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 0.5,
          checkToShowHorizontalLine: (v) => v > 0,
          getDrawingHorizontalLine: (_) => FlLine(
            color: rx.hairline,
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: rx.hairline)),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: 0.5,
              maxIncluded: false,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                space: 8,
                child: Text(_axisMoney(cash * v), style: RxText.micro(context)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final isStart = v <= 1e-6;
                final isEnd = (v - maxX).abs() < 1e-6;
                final style = RxText.micro(
                  context,
                  color: isEnd ? rx.negative : null,
                );
                return SideTitleWidget(
                  meta: meta,
                  space: 8,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(
                    meta,
                    distanceFromEdge: 0,
                  ),
                  child: Text(
                    isStart ? 'Today' : axisDate(dateAt(v)),
                    style: isStart || isEnd
                        ? style.copyWith(fontWeight: FontWeight.w600)
                        : style,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spotsUpTo(p),
            barWidth: 3,
            isStrokeCapRound: true,
            color: zoned ? null : rx.negative,
            gradient: zoned ? zones(1) : null,
            gradientArea: LineChartGradientArea.wholeChart,
            belowBarData: BarAreaData(
              show: true,
              color: zoned ? null : rx.negative.withValues(alpha: 0.12),
              gradient: zoned ? zones(0.12) : null,
            ),
            dotData: FlDotData(
              checkToShowDot: (s, _) => s.x == 0 || (done && s.x == maxX),
              getDotPainter: (s, _, _, _) =>
                  ringDot(s.x == 0 ? colorAt(0) : rx.negative),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: done,
          touchSpotThreshold: 1000,
          touchCallback: (event, response) {
            final x = event.isInterestedForInteractions
                ? response?.lineBarSpots?.firstOrNull?.x
                : null;
            if (x == _touchX) return;
            if (x != null && _touchX == null) HapticFeedback.selectionClick();
            setState(() => _touchX = x);
          },
          getTouchedSpotIndicator: (bar, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(
                  color: rx.textTertiary,
                  strokeWidth: 1,
                  dashArray: const [3, 3],
                ),
                FlDotData(
                  getDotPainter: (s, _, _, _) => ringDot(colorAt(s.x), r: 6),
                ),
              ),
          ],
          // The header shows the reading, so no floating tooltip.
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            getTooltipItems: (spots) => [for (final _ in spots) null],
          ),
        ),
      );
    }

    Widget legendDot(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: RxText.micro(context, color: rx.textSecondary)),
      ],
    );

    return RxCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sel == null ? 'Cash today' : _fullDate(dateAt(sel)),
                      style: RxText.caption(context),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatCurrency(selCash < 0 ? 0 : selCash),
                        style: RxText.value(
                          context,
                          size: 20,
                          color: selIsEnd ? rx.negative : null,
                        ),
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
                    sel == null ? 'Runs out' : 'At this date',
                    style: RxText.caption(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sel == null
                        ? _fullDate(cashOut)
                        : selIsEnd
                        ? 'Cash runs out'
                        : _timeLeft(totalDays - daysAt(sel)),
                    style: RxText.body(
                      context,
                      color: sel == null || selIsEnd
                          ? rx.negative
                          : colorAt(sel),
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Semantics(
            label:
                'Cash projection: ${_formatCurrency(cash)} today, running out '
                'on ${_fullDate(cashOut)}. Touch and drag to read any date.',
            child: SizedBox(
              height: 210,
              // Line draws itself from today to cash-out on open.
              child: RxGrow(
                value: 1,
                duration: const Duration(milliseconds: 900),
                builder: (context, p) =>
                    LineChart(chartData(p), duration: Duration.zero),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    if (totalMonths > 6) legendDot(rx.positive, '6+ months'),
                    if (totalMonths > 3) legendDot(rx.warning, '3-6 months'),
                    legendDot(rx.negative, 'Under 3 months'),
                  ],
                ),
              ),
              Text(
                'Drag to explore',
                style: RxText.micro(context, color: rx.textTertiary),
              ),
            ],
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
