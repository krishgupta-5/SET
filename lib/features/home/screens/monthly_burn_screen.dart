import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/financial_data_service.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';

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

  // --- THEME / COLORS ---
  Color _getCategoryColor(String categoryKey) {
    switch (categoryKey.toLowerCase()) {
      case 'salaries':
      case 'salary':
        return const Color(0xFF10B981);
      case 'servers':
      case 'infrastructure':
        return const Color(0xFF3B82F6);
      case 'marketing':
      case 'ads':
        return const Color(0xFFBF5AF2);
      case 'office':
      case 'rent':
        return const Color(0xFF00BFA5);
      case 'software':
      case 'tools':
        return const Color(0xFFFF375F);
      case 'legal':
        return const Color(0xFFFFD60A);
      case 'meals':
      case 'food':
        return const Color(0xFFF59E0B);
      case 'travel':
      case 'transport':
        return const Color(0xFF32ADE6);
      default:
        final colors = [
          const Color(0xFF3B82F6),
          const Color(0xFF10B981),
          const Color(0xFFBF5AF2),
          const Color(0xFFFF375F),
          const Color(0xFFF59E0B),
          const Color(0xFF32ADE6),
        ];
        return colors[categoryKey.hashCode % colors.length];
    }
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

  // --- UI BUILDING ---

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            onRefresh: () async {
              _loadFinancialData();
            },
            color: textPrimary,
            backgroundColor: cardColor,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildHeader(context, textPrimary, textSecondary),
                      const SizedBox(height: 32),

                      _buildRangeSelector(
                        textPrimary,
                        textSecondary,
                        isDark,
                        borderColor,
                      ),
                      const SizedBox(height: 32),

                      _mainCardLoaded
                          ? _buildHeroCard(
                              textPrimary,
                              textSecondary,
                              cardColor,
                              borderColor,
                              shadowColor,
                            )
                          : _buildSkeletonCard(cardColor, borderColor),
                      const SizedBox(height: 32),

                      _trendLoaded
                          ? _buildBurnTrendCard(
                              textPrimary,
                              textSecondary,
                              textTertiary,
                              isDark,
                              cardColor,
                              borderColor,
                              shadowColor,
                            )
                          : _buildSkeletonCard(cardColor, borderColor),
                      const SizedBox(height: 32),

                      _categoriesLoaded
                          ? _buildExpenseCategoriesCard(
                              textPrimary,
                              textSecondary,
                              textTertiary,
                              cardColor,
                              borderColor,
                              shadowColor,
                            )
                          : _buildSkeletonCard(cardColor, borderColor),
                      const SizedBox(height: 32),

                      _teamsLoaded
                          ? _buildTeamCostCard(
                              textPrimary,
                              textSecondary,
                              textTertiary,
                              isDark,
                              cardColor,
                              borderColor,
                              shadowColor,
                            )
                          : _buildSkeletonCard(cardColor, borderColor),
                      const SizedBox(height: 32),

                      _forecastLoaded
                          ? _buildForecastComparisonCard(
                              textPrimary,
                              textSecondary,
                              textTertiary,
                              isDark,
                              cardColor,
                              borderColor,
                              shadowColor,
                            )
                          : _buildSkeletonCard(cardColor, borderColor),
                      const SizedBox(height: 80),
                    ]),
                  ),
                ),
              ],
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
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.arrow_back, color: textSecondary, size: 16),
                const SizedBox(width: 4),
                Text(
                  "Back",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          "BURN ANALYSIS",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
          ),
        ),
      ],
    );
  }

  Widget _buildRangeSelector(
    Color textPrimary,
    Color textSecondary,
    bool isDark,
    Color borderColor,
  ) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.transparent, // Floating Pill format
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: _ranges.map((range) {
          final isSelected = _selectedRange == range;
          return Expanded(
            child: GestureDetector(
              onTap: () => _onRangeChanged(range),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.05))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  range,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: isSelected ? textPrimary : textSecondary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- REUSABLE WRAPPER FOR CARDS ---
  Widget _buildSectionCard({
    required Widget child,
    required Color cardColor,
    required Color borderColor,
    required Color shadowColor,
  }) {
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
      child: child,
    );
  }

  // --- HERO BENTO CARD ---
  Widget _buildHeroCard(
    Color textPrimary,
    Color textSecondary,
    Color cardColor,
    Color borderColor,
    Color shadowColor,
  ) {
    if (_error != null) return _buildErrorState(textSecondary);

    final grossBurn = _toDouble(_financialData?['grossBurn']);
    final netBurn = _toDouble(_financialData?['netBurn']);
    final greenColor = const Color(0xFF10B981);
    final redColor = const Color(0xFFEF4444);

    final String grossString = grossBurn > 0
        ? (_isLoadingCountry
              ? CurrencyFormatter.formatCompact(grossBurn, countryCode: '+91')
              : CurrencyFormatter.formatByCountryCompact(
                  grossBurn,
                  _userCountryCode,
                ))
        : (_isLoadingCountry
              ? "₹0"
              : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0");

    final String netString = netBurn > 0
        ? (_isLoadingCountry
              ? CurrencyFormatter.formatCompact(netBurn, countryCode: '+91')
              : CurrencyFormatter.formatByCountryCompact(
                  netBurn,
                  _userCountryCode,
                ))
        : (_isLoadingCountry
              ? "₹0"
              : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0");

    return _buildSectionCard(
      cardColor: cardColor,
      borderColor: borderColor,
      shadowColor: shadowColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "GROSS BURN / MONTH",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              GestureDetector(
                onTap: _loadFinancialData,
                child: _isRefreshing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: textSecondary,
                        ),
                      )
                    : Icon(Icons.refresh, color: textSecondary, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              grossString,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textPrimary,
                fontSize: 64, // Massive unboxed text
                fontWeight: FontWeight.w700,
                letterSpacing: -2.5,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 24),
          DottedDivider(color: borderColor),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "NET BURN",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    netString,
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: redColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "IMPACT STATUS",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: greenColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "HEALTHY",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: greenColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- BURN TREND CARD ---
  Widget _buildBurnTrendCard(
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color shadowColor,
  ) {
    int count = _getMonthsCount();
    String title = _selectedRange == "YTD" || _selectedRange == "ALL"
        ? "$_selectedRange BURN TREND"
        : "$count-MONTH BURN TREND";

    if (_error != null) return _buildErrorState(textSecondary);

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

    final maxAmount = displayData.isEmpty
        ? 1.0
        : displayData
              .map((d) => _toDouble(d['amount']))
              .reduce((a, b) => a > b ? a : b);

    return AnimatedOpacity(
      opacity: _trendLoaded ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      child: _buildSectionCard(
        cardColor: cardColor,
        borderColor: borderColor,
        shadowColor: shadowColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel(title, textSecondary),
            const SizedBox(height: 24),
            displayData.isEmpty
                ? _buildEmptyState(
                    "Not enough data for trend analysis",
                    textTertiary,
                  )
                : SizedBox(
                    height: 120, // Compressed bar height
                    child: Row(
                      mainAxisAlignment: displayData.length <= 3
                          ? MainAxisAlignment.spaceEvenly
                          : MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: displayData.map((data) {
                        final amount = _toDouble(data['amount']);
                        final pct = maxAmount > 0 ? amount / maxAmount : 0.0;
                        return _buildCapsuleBar(
                          data['month'] as String,
                          pct,
                          amount,
                          textPrimary,
                          textSecondary,
                          isDark,
                          isActive: data['isCurrentMonth'] as bool? ?? false,
                        );
                      }).toList(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapsuleBar(
    String label,
    double pct,
    double amount,
    Color textPrimary,
    Color textSecondary,
    bool isDark, {
    bool isActive = false,
  }) {
    final safePct = pct == 0.0 ? 0.02 : pct.clamp(0.0, 1.0);
    final inactiveBarColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            _formatCurrencyForForecast(amount),
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: isActive ? textPrimary : textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: safePct,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 24, // Thinner bars
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF3B82F6) : inactiveBarColor,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: isActive ? textPrimary : textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // --- CATEGORY ANALYSIS CARD (CLASSIC LIST WITH DOTTED DIVIDERS) ---
  Widget _buildExpenseCategoriesCard(
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
    Color cardColor,
    Color borderColor,
    Color shadowColor,
  ) {
    if (_error != null) return _buildErrorState(textSecondary);

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

    return AnimatedOpacity(
      opacity: _categoriesLoaded ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      child: _buildSectionCard(
        cardColor: cardColor,
        borderColor: borderColor,
        shadowColor: shadowColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel("CATEGORY ANALYSIS", textSecondary),
            const SizedBox(height: 24),

            combinedData.isEmpty
                ? _buildEmptyState(
                    "No transaction data available",
                    textTertiary,
                  )
                : Column(
                    children: sortedEntries.map((entry) {
                      final categoryData = entry.value;
                      final budget = _toDouble(categoryData['budget']);
                      final actual = _toDouble(categoryData['actual']);
                      final variancePercentage = _toDouble(
                        categoryData['variancePercentage'],
                      );
                      final isOverBudget =
                          categoryData['isOverBudget'] as bool? ?? false;
                      final hasBudget =
                          categoryData['hasBudget'] as bool? ?? false;
                      final isLast = entry == sortedEntries.last;
                      final catName = _getCategoryDisplayName(entry.key);

                      final pctString = totalActual > 0
                          ? '${((actual / totalActual) * 100).toStringAsFixed(1)}%'
                          : '0%';
                      final varianceColor = isOverBudget
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981);
                      final varianceText = isOverBudget
                          ? '${variancePercentage.abs().toStringAsFixed(1)}% over'
                          : '${variancePercentage.abs().toStringAsFixed(1)}% under';

                      return Column(
                        children: [
                          _buildLedgerRow(
                            title: catName,
                            subtitle: hasBudget
                                ? "Budget: ${_formatCurrencyForForecast(budget)}"
                                : "No budget set",
                            amount: actual,
                            rightSubtitle: pctString,
                            varianceText: hasBudget ? varianceText : null,
                            varianceColor: hasBudget ? varianceColor : null,
                            dotColor: _getCategoryColor(entry.key),
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                          ),
                          if (!isLast)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: DottedDivider(color: borderColor),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  // --- TEAM COST CARD (DIFFERENT UI: PROGRESS TRACKS, NO DIVIDERS) ---
  Widget _buildTeamCostCard(
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color shadowColor,
  ) {
    if (_error != null) return _buildErrorState(textSecondary);

    final teamCosts =
        (_teamCostData?['teamCosts'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return AnimatedOpacity(
      opacity: _teamsLoaded ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      child: _buildSectionCard(
        cardColor: cardColor,
        borderColor: borderColor,
        shadowColor: shadowColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel("TEAM COST DISTRIBUTION", textSecondary),
            const SizedBox(height: 24),

            teamCosts.isEmpty
                ? _buildEmptyState("No team data available", textTertiary)
                : Column(
                    children: teamCosts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final team = entry.value;
                      final amount = _toDouble(team['cost']);
                      final pct = _toDouble(team['pct']);
                      final colors = [
                        const Color(0xFF3B82F6),
                        const Color(0xFF10B981),
                        const Color(0xFFF59E0B),
                        const Color(0xFF8B5CF6),
                        const Color(0xFFEC4899),
                        const Color(0xFF14B8A6),
                      ];
                      final dotColor = colors[index % colors.length];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: dotColor,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      team['name'] as String,
                                      style: TextStyle(
                                        fontFamily: 'Satoshi',
                                        color: textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  _formatCurrencyForForecast(amount),
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Stack(
                              children: [
                                Container(
                                  height: 4,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: textSecondary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: pct > 0 ? pct : 0.02,
                                  child: Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: dotColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "${(pct * 100).toStringAsFixed(1)}% of total",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  // --- FORECAST COMPARISON CARD (DIFFERENT UI: INNER DATA CARDS, NO DIVIDERS) ---
  Widget _buildForecastComparisonCard(
    Color textPrimary,
    Color textSecondary,
    Color textTertiary,
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color shadowColor,
  ) {
    if (_error != null) return _buildErrorState(textSecondary);

    final rawTeamsData = _rawTeamsData ?? [];

    if (rawTeamsData.isEmpty) {
      return _buildSectionCard(
        cardColor: cardColor,
        borderColor: borderColor,
        shadowColor: shadowColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel("BUDGET VS ACTUAL", textSecondary),
            const SizedBox(height: 24),
            _buildEmptyState("No team budget data available", textTertiary),
          ],
        ),
      );
    }

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

    return AnimatedOpacity(
      opacity: _forecastLoaded ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      child: _buildSectionCard(
        cardColor: cardColor,
        borderColor: borderColor,
        shadowColor: shadowColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel("BUDGET VS ACTUAL", textSecondary),
            const SizedBox(height: 24),
            ...comparisonData.map((data) {
              final isOver = data['isOver'] == true;
              final varianceColor = isOver
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981);
              final varianceText = isOver
                  ? "${_formatCurrencyForForecast(_toDouble(data['variance']).abs())} over"
                  : "${_formatCurrencyForForecast(_toDouble(data['variance']).abs())} under";

              final isLast = data == comparisonData.last;

              return Column(
                children: [
                  _buildLedgerRow(
                    title: data['team']?.toString() ?? 'Unknown',
                    subtitle:
                        "Budget: ${_formatCurrencyForForecast(_toDouble(data['budget']))}",
                    amount: _toDouble(data['actual']),
                    varianceText: varianceText,
                    varianceColor: varianceColor,
                    dotColor: textPrimary,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                  if (!isLast) const SizedBox(height: 16),
                ],
              );
            }),
            const SizedBox(height: 16),
            DottedDivider(color: borderColor),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "TOTAL BUDGET",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  _formatCurrencyForForecast(totalBudget),
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "TOTAL ACTUAL",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  _formatCurrencyForForecast(totalActual),
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- REUSABLE LIST ROW HELPER ---
  Widget _buildLedgerRow({
    required String title,
    String? subtitle,
    required double amount,
    String? rightSubtitle,
    String? varianceText,
    Color? varianceColor,
    Color? dotColor,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final formattedAmount = _formatCurrencyForForecast(amount);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: dotColor ?? textPrimary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formattedAmount,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (rightSubtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                rightSubtitle,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (varianceText != null && varianceColor != null) ...[
              const SizedBox(height: 2),
              Text(
                varianceText,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: varianceColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildErrorState(Color textSecondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Failed to load data.",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: const Color(0xFFEF4444),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _loadFinancialData,
          child: Text(
            "Tap to retry",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: textSecondary,
              fontSize: 13,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonCard(Color cardColor, Color borderColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: borderColor),
      ),
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          final value = _shimmerController.value;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final baseColor = isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05);
          final highlightColor = isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1);

          Widget shimmerBox(double width, double height) {
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment(value - 1, 0),
                  end: Alignment(value, 0),
                  colors: [baseColor, highlightColor, baseColor],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              shimmerBox(100, 24),
              const SizedBox(height: 32),
              shimmerBox(200, 48),
              const SizedBox(height: 32),
              DottedDivider(color: borderColor),
              const SizedBox(height: 24),
              shimmerBox(120, 24),
            ],
          );
        },
      ),
    );
  }
}
