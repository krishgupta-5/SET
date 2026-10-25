import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:developer';
import 'package:hugeicons/hugeicons.dart';

import 'runway_estimation_screen.dart';
import 'funds_overview_screen.dart';
import 'monthly_burn_screen.dart';
import 'chatbot_screen.dart';
import '../../../services/ai_context_manager.dart';
import '../../../services/financial_data_service.dart';
import '../../../services/financial_calculator.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/team_member_service.dart';
import '../../../services/telegram_service.dart';
import '../../../widgets/custom_bottom_nav.dart' show RxTabBar;
import '../../../widgets/rx_ui.dart';
import '../../../widgets/rx_charts.dart';
import '../../../widgets/rx_motion.dart';

class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  /// Changes each time the Home tab is opened (null while hidden), so the
  /// charts replay their entrance.
  final int? visit;

  const HomeScreen({super.key, this.onNavigateToTab, this.visit});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? runwayValue;
  bool isLoading = true;
  String? errorMessage;

  // Storing raw numbers ensures real-time calculation and instant currency updates
  double _fundingAmount = 0.0;
  double _absoluteTotalExpenses = 0.0;
  double _currentMonthBurn = 0.0;
  double get _availableFunds => _fundingAmount - _absoluteTotalExpenses;

  // Real-time calculated Pie Chart data
  Map<String, double> _realtimeCategoryBreakdown = {};

  List<Map<String, dynamic>> allExpenses = [];

  // Raw Firestore data; all derived numbers come from FinancialCalculator.
  List<Map<String, dynamic>> _rawExpenses = [];
  List<Map<String, dynamic>> _rawMembers = [];
  List<Map<String, dynamic>> _rawRevenue = [];
  bool _expensesLoaded = false;

  bool _isPieChartLoading = true;
  bool _isMonthlyBurnLoading = true;
  bool _isFundsLoading = true;

  List<Map<String, dynamic>> _trendData = [];
  bool _isTrendLoading = true;

  String _userCountryCode = '+1'; // Default to USD
  final bool _isLoadingCountry = false;

  // Real-time stream subscriptions
  StreamSubscription<DocumentSnapshot>? _companySubscription;
  StreamSubscription<QuerySnapshot>? _expensesSubscription;
  StreamSubscription<QuerySnapshot>? _teamMembersSubscription;
  StreamSubscription<QuerySnapshot>? _revenueSubscription;
  StreamSubscription<QuerySnapshot>? _teamsSubscription;
  Timer? _realtimeDebounceTimer;

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadUserCountryCode();

    // Initiate Real-Time Listeners
    _setupRealtimeListeners();
    _createAIData();
  }

  // Keys the charts; bumping it replays their grow/sweep entrance.
  int _chartEpoch = 0;

  // Bar picked in the burn chart (null = current month) and slice picked
  // in the breakdown donut (null = whole month).
  int? _selectedBar;
  String? _selectedCategory;

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visit != null && widget.visit != oldWidget.visit) {
      _chartEpoch++;
      _selectedBar = null;
      _selectedCategory = null;
    }
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _companySubscription?.cancel();
    _expensesSubscription?.cancel();
    _teamMembersSubscription?.cancel();
    _revenueSubscription?.cancel();
    _teamsSubscription?.cancel();
    _realtimeDebounceTimer?.cancel();
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

  String _formatCurrency(double amount) {
    if (_isLoadingCountry) {
      return CurrencyFormatter.formatCompact(amount, countryCode: '+91');
    }
    return CurrencyFormatter.formatByCountryCompact(amount, _userCountryCode);
  }

  Future<String> getTelegramImageUrl(String fileId) =>
      TelegramService.getImageUrl(fileId);

  Future<void> _loadUserCountryCode() async {
    final currencyCode =
        await CurrencyPreferenceService.getCurrencyPreference();
    if (mounted && currencyCode != _userCountryCode) {
      setState(() {
        _userCountryCode = currencyCode;
      });
    }
  }

  Future<void> _createAIData() async {
    // Handled in auth layer
  }

  // --- REAL-TIME LISTENER SETUP ---
  void _handleRealtimeUpdate() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      FinancialDataService.clearAllCache();
      _loadFinancialDataForPieChart();
      _syncCalculatedDataToFirestore();
    });
  }

  /// Persists the computed runway so the AI backend sees the same number.
  /// `totalExpenses` is intentionally not written here: it is maintained
  /// atomically by [ExpenseService] and overwriting it from a snapshot races
  /// with concurrent writes.
  Future<void> _syncCalculatedDataToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !_expensesLoaded || runwayValue == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection("companies")
          .doc(user.uid);
      final snapshot = await docRef.get();
      if (!snapshot.exists) return;
      final currentRunway = (snapshot.data()!['Runway'] ?? '').toString();
      final runwayString = "$runwayValue months";
      if (currentRunway != runwayString) {
        await docRef.update({'Runway': runwayString});
      }
    } catch (e) {
      log("Error syncing calculated data to Firestore: $e");
    }
  }

  void _setupRealtimeListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        errorMessage = "User not authenticated";
        isLoading = false;
        _isFundsLoading = false;
        _isMonthlyBurnLoading = false;
      });
      return;
    }

    TeamMemberService.checkAndApplyFutureSalaries();

    // 1. Listen to Company Document
    _companySubscription = FirebaseFirestore.instance
        .collection("companies")
        .doc(user.uid)
        .snapshots()
        .listen(
          (docSnapshot) {
            if (docSnapshot.exists && docSnapshot.data() != null) {
              final data = docSnapshot.data()!;
              final funding =
                  data["Funding"] ?? data["funding"] ?? data["FUNDING"];

              // Funding, budgets, company details → refresh AI context.
              // Excludes fields this screen writes itself to avoid a loop.
              final aiRelevant = Map<String, dynamic>.from(data)
                ..remove('Runway')
                ..remove('totalExpenses')
                ..remove('updatedAt');
              AiContextManager().reportDataChanged(
                'company',
                _fingerprint(aiRelevant),
              );

              if (mounted) {
                setState(() {
                  _fundingAmount = _toDouble(funding);
                  _updateRunwayValue();
                  isLoading = false;
                  _isFundsLoading = false;
                });
                _handleRealtimeUpdate();
              }
            } else {
              if (mounted) {
                setState(() {
                  errorMessage = "No company data found";
                  isLoading = false;
                  _isFundsLoading = false;
                });
              }
            }
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                errorMessage = "Failed to load company data";
                isLoading = false;
                _isFundsLoading = false;
              });
            }
          },
        );

    // 2. Listen to Expenses Collection
    _expensesSubscription = FirebaseFirestore.instance
        .collection('expenses')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              _reportCollectionChange('expenses', snapshot);
              setState(() {
                _rawExpenses = FinancialCalculator.docsToMaps(snapshot.docs);
                _expensesLoaded = true;
                _updateRunwayValue();
                _isMonthlyBurnLoading = false;
                _isPieChartLoading = false;
              });

              _handleRealtimeUpdate();
            }
          },
          onError: (e) {
            log("Error fetching expenses: $e");
            if (mounted) setState(() => _isMonthlyBurnLoading = false);
          },
        );

    // 3. Listen to Team Members Collection
    _teamMembersSubscription = FirebaseFirestore.instance
        .collection('members')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            _reportCollectionChange('members', snapshot);
            setState(() {
              _rawMembers = FinancialCalculator.docsToMaps(snapshot.docs);
              _updateRunwayValue();
            });
            _handleRealtimeUpdate();
          }
        });

    // 4. Revenue (optional — net burn falls back to gross burn without it)
    _revenueSubscription = FirebaseFirestore.instance
        .collection('revenue')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              _reportCollectionChange('revenue', snapshot);
              setState(() {
                _rawRevenue = FinancialCalculator.docsToMaps(snapshot.docs);
                _updateRunwayValue();
              });
            }
          },
          onError: (e) => log("Revenue listener error: $e"),
        );

    // 5. Teams (budgets, names) only feed the AI context.
    _teamsSubscription = FirebaseFirestore.instance
        .collection('teams')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen(
          (snapshot) => _reportCollectionChange('teams', snapshot),
          onError: (e) => log("Teams listener error: $e"),
        );
  }

  /// Tells the AI layer when financial data really changed, from any screen
  /// (funding, members, teams, revenue, budgets — not just expense edits).
  void _reportCollectionChange(
    String source,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    // Skip our own pending local writes; the server echo will follow.
    if (snapshot.metadata.hasPendingWrites) return;
    final parts = snapshot.docs.map((d) => '${d.id}:${_fingerprint(d.data())}');
    AiContextManager().reportDataChanged(source, parts.join('|'));
  }

  static String _fingerprint(Map<String, dynamic> data) {
    final keys = data.keys.toList()..sort();
    return keys.map((k) => '$k=${data[k]}').join(';').hashCode.toString();
  }

  Future<void> _loadFinancialDataForPieChart() async {
    try {
      final financialData = await FinancialDataService.getMonthlyBurnData();
      if (mounted) {
        setState(() {
          final rawTrend = financialData['trendData'] as List? ?? [];
          _trendData = List<Map<String, dynamic>>.from(rawTrend);
          _isTrendLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isTrendLoading = false);
    }
  }

  /// Recomputes every dashboard number from the latest raw data using the
  /// shared [FinancialCalculator.compute], so home, runway, funds and
  /// expenses screens always agree.
  void _updateRunwayValue() {
    final s = FinancialCalculator.compute(
      funding: _fundingAmount,
      rawExpenses: _rawExpenses,
      members: _rawMembers,
      revenue: _rawRevenue,
    );
    allExpenses = s.expenses;
    _absoluteTotalExpenses = s.totalSpent;
    _currentMonthBurn = s.monthlyBurn;
    _realtimeCategoryBreakdown = s.categoryBreakdown;
    runwayValue = s.runwayMonths.toStringAsFixed(2);
  }

  // --- UI HELPERS ---
  // Everything below is presentation only. Data comes from the state above.

  /// "Good morning, Sahil" (first name when we have one).
  String _greeting() {
    final h = DateTime.now().hour;
    final part = h < 12
        ? 'Good morning'
        : h < 17
        ? 'Good afternoon'
        : 'Good evening';
    final name = (FirebaseAuth.instance.currentUser?.displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .first;
    return name.isEmpty ? part : '$part, $name';
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildProfileAvatar(String? profileImageFileId, bool isDark) {
    if (profileImageFileId != null && profileImageFileId.isNotEmpty) {
      return FutureBuilder<String>(
        future: getTelegramImageUrl(profileImageFileId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _buildDefaultAvatar(isDark);
          return Container(
            width: 48,
            height: 48,
            // Pure black/white 10% outline so the photo edge never tints.
            foregroundDecoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
              ),
            ),
            child: ClipOval(
              child: Image.network(
                snapshot.data!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildDefaultAvatar(isDark),
              ),
            ),
          );
        },
      );
    }
    return _buildDefaultAvatar(isDark);
  }

  /// Plain default avatar: a soft circle with a person glyph.
  Widget _buildDefaultAvatar(bool isDark) {
    final rx = context.rx;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: rx.surface,
        border: Border.all(color: isDark ? rx.hairline : Colors.transparent),
        boxShadow: rx.cardShadow,
      ),
      alignment: Alignment.center,
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedUser,
        size: 22,
        color: rx.textSecondary,
        strokeWidth: 1.7,
      ),
    );
  }

  String _getRunwayString(String runwayValue) {
    final runway = double.tryParse(runwayValue) ?? 0;
    if (runway <= 0) return "--";

    if (runway > 120) {
      return ">10Y";
    }

    if (runway >= 12) {
      final years = (runway / 12).floor();
      final months = (runway % 12).floor();
      if (months == 0) {
        return "${years}Y";
      } else {
        return "${years}Y ${months}M";
      }
    }

    final wholeMonths = runway.floor();
    final remainingDays = ((runway - wholeMonths) * 30).round();

    if (wholeMonths == 0) {
      return "${remainingDays}D";
    }

    if (remainingDays == 0 || remainingDays >= 30) {
      return "${wholeMonths}M";
    }

    return "${wholeMonths}M ${remainingDays}D";
  }

  HealthStatus _calculateHealthStatus() {
    if (isLoading) return HealthStatus.unknown;
    if (runwayValue == null || errorMessage != null) {
      return HealthStatus.unknown;
    }

    final runway = double.tryParse(runwayValue!) ?? 0;
    if (runway <= 0) return HealthStatus.unknown;
    if (runway <= 3) return HealthStatus.critical;
    if (runway <= 6) return HealthStatus.warning;
    return HealthStatus.safe;
  }

  /// Display split of the runway for the hero: big value + small unit,
  /// plus a phrase for the sentence below. Formatting only; the runway
  /// value itself comes from [_updateRunwayValue].
  ({String value, String? unit, String? phrase}) _runwayParts() {
    if (isLoading) return (value: '--', unit: null, phrase: null);
    final m = double.tryParse(runwayValue ?? '') ?? 0;
    if (m <= 0) return (value: '--', unit: null, phrase: null);
    if (m > 120) {
      return (value: '10+', unit: 'years', phrase: 'over 10 years');
    }
    if (m >= 12) {
      final y = m / 12;
      final v = y.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
      final unit = v == '1' ? 'year' : 'years';
      return (value: v, unit: unit, phrase: 'about $v $unit');
    }
    if (m >= 1) {
      final v = m.toStringAsFixed(1);
      return (value: v, unit: 'months', phrase: '$v months');
    }
    final d = (m * 30).round().clamp(1, 30);
    return (value: '$d', unit: d == 1 ? 'day' : 'days', phrase: '$d days');
  }

  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  String get _burnText {
    if (_isMonthlyBurnLoading) return '--';
    if (_currentMonthBurn <= 0) {
      return _isLoadingCountry
          ? "₹0"
          : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0";
    }
    return _formatCurrency(_currentMonthBurn);
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: rx.background,
        body: SafeArea(
          // Content runs under the floating tab bar to the screen edge;
          // the bottom padding (RxTabBar.reservedHeight) clears the bar.
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
                RxReveal.index(0, child: _buildHeader(isDark)),
                const SizedBox(height: 28),
                RxReveal.index(1, child: _buildRunwayHero()),
                const SizedBox(height: 24),
                RxReveal.index(2, child: _buildStatsCard()),
                const SizedBox(height: 10),
                RxReveal.index(3, child: _buildAskAiCard()),
                const SizedBox(height: 28),
                RxReveal.index(
                  4,
                  child: Column(
                    children: [
                      RxSectionHeader(
                        title: 'Monthly burn',
                        actionLabel: 'Details',
                        onAction: () => _push(const MonthlyBurnScreen()),
                      ),
                      _buildTrendCard(),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                RxReveal.index(
                  5,
                  child: Column(
                    children: [
                      RxSectionHeader(
                        title: 'Where it goes',
                        actionLabel: 'Breakdown',
                        onAction: () => _push(const MonthlyBurnScreen()),
                      ),
                      _buildBreakdownCard(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- HEADER ---

  Widget _buildHeader(bool isDark) {
    final user = FirebaseAuth.instance.currentUser;

    Widget avatar(Widget child) => RxPressable(
      onTap: () => widget.onNavigateToTab?.call(4),
      semanticLabel: 'Profile and settings',
      // 52px hit area around the 48px avatar.
      child: SizedBox(width: 52, height: 52, child: Center(child: child)),
    );

    return RxTabHeader(
      label: _greeting(),
      title: 'Overview',
      actions: [
        if (user != null)
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection("users")
                .doc(user.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              String? profileImageFileId;
              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData =
                    userSnapshot.data!.data() as Map<String, dynamic>;
                profileImageFileId = userData['profileImageFileId'];
              }
              return avatar(_buildProfileAvatar(profileImageFileId, isDark));
            },
          )
        else
          avatar(_buildDefaultAvatar(isDark)),
      ],
    );
  }

  // --- RUNWAY HERO ---
  // Flat on the page, no card: one big number is the whole story.

  Widget _buildRunwayHero() {
    final rx = context.rx;
    final health = _calculateHealthStatus();

    late final String statusLabel;
    late final Color statusFg;
    late final Color statusBg;
    late String note;
    switch (health) {
      case HealthStatus.safe:
        statusLabel = 'Healthy';
        statusFg = rx.positive;
        statusBg = rx.positiveSoft;
        note = 'More than 6 months of cash at your current burn';
        break;
      case HealthStatus.warning:
        statusLabel = 'Watch';
        statusFg = rx.warning;
        statusBg = rx.warningSoft;
        note = 'Under 6 months left. A good time to plan the next raise';
        break;
      case HealthStatus.critical:
        statusLabel = 'Critical';
        statusFg = rx.negative;
        statusBg = rx.negativeSoft;
        note = 'Under 3 months of cash left at your current burn';
        break;
      case HealthStatus.unknown:
        statusLabel = isLoading ? 'Updating' : 'No data';
        statusFg = rx.textSecondary;
        statusBg = rx.surfaceMuted;
        note = isLoading
            ? 'Crunching your latest numbers'
            : 'Add funding and expenses to estimate your runway';
        break;
    }

    final runwayText = isLoading ? '--' : _getRunwayString(runwayValue ?? "0");
    final parts = _runwayParts();
    // Lead the note with the actual duration, so it never contradicts the
    // number (">10Y" next to "more than 6 months" read oddly).
    if (health == HealthStatus.safe && parts.phrase != null) {
      note = 'Cash lasts ${parts.phrase} at your current burn';
    }

    return RxPressable(
      onTap: () => _push(const RunwayEstimationScreen()),
      semanticLabel: 'Runway $runwayText, $statusLabel. Open runway details',
      scale: 0.98,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Runway', style: RxText.label(context)),
              const SizedBox(width: 8),
              RxPill(
                label: statusLabel,
                dot: true,
                foreground: statusFg,
                background: statusBg,
              ),
              const Spacer(),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                color: rx.textTertiary,
                size: 20,
                strokeWidth: 1.8,
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
          Text(note, style: RxText.label(context)),
        ],
      ),
    );
  }

  // --- CASH + BURN ---
  // One card split in two, so the pair reads as a single fact.

  Widget _buildStatsCard() {
    final rx = context.rx;
    final cashText = _isFundsLoading ? '--' : _formatCurrency(_availableFunds);

    Widget half({
      required String label,
      required String value,
      required bool loading,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: RxPressable(
          onTap: onTap,
          semanticLabel: '$label $value',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: RxText.label(context)),
                const SizedBox(height: 8),
                if (loading)
                  const RxSkeleton(width: 96, height: 26)
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: RxText.value(context)),
                  ),
              ],
            ),
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
              label: 'Cash available',
              value: cashText,
              loading: _isFundsLoading,
              onTap: () => _push(const FundsOverviewScreen()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(width: 1, color: rx.hairline),
            ),
            half(
              label: 'Burn this month',
              value: _burnText,
              loading: _isMonthlyBurnLoading,
              onTap: () => _push(const MonthlyBurnScreen()),
            ),
          ],
        ),
      ),
    );
  }

  // --- ASK AI ---

  Widget _buildAskAiCard() {
    final rx = context.rx;
    return RxCard(
      onTap: () => _push(const ChatbotScreen()),
      semanticLabel: 'Ask your AI CFO',
      padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
      radius: 100,
      child: Row(
        children: [
          const RxAiBadge(size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ask about your numbers…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RxText.body(context, color: rx.textTertiary),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: rx.inverse,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowUp02,
              color: rx.onInverse,
              size: 18,
              strokeWidth: 2.2,
            ),
          ),
        ],
      ),
    );
  }

  // --- MONTHLY BURN BARS ---
  // Header shows the picked month (current by default) and how it compares
  // with the month before; bars grow up in a left-to-right cascade.

  Widget _buildTrendCard() {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const chartHeight = 120.0;
    const labelSpace = 26.0;

    if (_isTrendLoading) {
      return RxCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RxSkeleton(width: 80, height: 12),
            const SizedBox(height: 8),
            const RxSkeleton(width: 130, height: 26),
            const SizedBox(height: 20),
            SizedBox(
              height: chartHeight + labelSpace,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in const [0.45, 0.6, 0.5, 0.75, 0.65, 0.9])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 0, 7, labelSpace),
                        child: RxSkeleton(height: chartHeight * h, radius: 8),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_trendData.isEmpty) {
      return const RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedChartBarLine,
          title: 'No trend yet',
          message: 'Your monthly burn shows up here after the first expenses',
        ),
      );
    }

    // Same 6-month window as before, oldest on the left.
    List<Map<String, dynamic>> display = _trendData;
    final isNewestFirst = display.first['isCurrentMonth'] == true;
    if (isNewestFirst) {
      display = display.take(6).toList().reversed.toList();
    } else if (display.length > 6) {
      display = display.sublist(display.length - 6);
    }

    final amounts = [for (final d in display) _toDouble(d['amount'])];
    final maxAmount = amounts.fold<double>(0, (a, b) => a > b ? a : b);
    final currentIndex = display.indexWhere((d) => d['isCurrentMonth'] == true);
    final fallback = currentIndex >= 0 ? currentIndex : display.length - 1;
    final sel = (_selectedBar != null && _selectedBar! < display.length)
        ? _selectedBar!
        : fallback;

    final selAmount = amounts[sel];
    final prevAmount = sel > 0 ? amounts[sel - 1] : null;
    final selLabel = sel == currentIndex
        ? 'This month'
        : (display[sel]['month'] as String? ?? '');

    final activeColor = isDark ? rx.accent : rx.inverse;

    return RxCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
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
                    Text(selLabel, style: RxText.label(context)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatCurrency(selAmount),
                        style: RxText.value(context, size: 24),
                      ),
                    ),
                  ],
                ),
              ),
              if (prevAmount != null) _buildDeltaPill(selAmount, prevAmount),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: chartHeight + labelSpace,
            child: Stack(
              children: [
                // Quiet guides at 0, 1/3 and 2/3 of the scale.
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
                    for (var i = 0; i < display.length; i++)
                      Expanded(
                        child: _buildBar(
                          index: i,
                          label: display[i]['month'] as String? ?? '',
                          amount: amounts[i],
                          max: maxAmount,
                          selected: i == sel,
                          color: activeColor,
                          chartHeight: chartHeight,
                          labelSpace: labelSpace,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Change versus the previous month. Spending more reads as negative.
  Widget _buildDeltaPill(double current, double previous) {
    final rx = context.rx;
    if (previous <= 0) {
      if (current <= 0) return const SizedBox.shrink();
      return RxPill(
        label: 'New',
        foreground: rx.textSecondary,
        background: rx.surfaceMuted,
      );
    }
    final change = (current - previous) / previous * 100;
    final up = change > 0.5;
    final down = change < -0.5;
    final text = up || down
        ? '${up ? '↑' : '↓'} ${change.abs().toStringAsFixed(change.abs() >= 10 ? 0 : 1)}%'
        : 'No change';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RxPill(
        label: text,
        foreground: up
            ? rx.negative
            : down
            ? rx.positive
            : rx.textSecondary,
        background: up
            ? rx.negativeSoft
            : down
            ? rx.positiveSoft
            : rx.surfaceMuted,
      ),
    );
  }

  Widget _buildBar({
    required int index,
    required String label,
    required double amount,
    required double max,
    required bool selected,
    required Color color,
    required double chartHeight,
    required double labelSpace,
  }) {
    final rx = context.rx;
    final pct = max > 0 ? (amount / max).clamp(0.0, 1.0) : 0.0;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label ${_formatCurrency(amount)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedBar = index);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: chartHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                // Grows from the axis on open; cascades 70ms per bar.
                child: RxGrow(
                  key: ValueKey('bar-$_chartEpoch-$index'),
                  value: pct,
                  delay: Duration(milliseconds: 70 * index),
                  builder: (context, v) => Container(
                    width: 28,
                    // Empty months keep a short stub so the axis still reads.
                    height: (chartHeight * v).clamp(4.0, chartHeight),
                    decoration: BoxDecoration(
                      color: selected
                          ? color
                          : rx.textPrimary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: labelSpace,
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style:
                      RxText.micro(
                        context,
                        color: selected ? rx.textPrimary : rx.textTertiary,
                      ).copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WHERE IT GOES ---
  // Donut of this month's categories. Tapping a row lifts its slice and
  // shows it in the centre; tapping again returns to the month total.

  static const _otherKey = '__other__';

  Widget _buildBreakdownCard() {
    final rx = context.rx;

    if (_isPieChartLoading) {
      return RxCard(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
        child: Column(
          children: [
            const RxSkeleton(width: 176, height: 176, radius: 100),
            const SizedBox(height: 20),
            for (var i = 0; i < 3; i++)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    RxSkeleton(width: 10, height: 10, radius: 100),
                    SizedBox(width: 12),
                    Expanded(child: RxSkeleton(height: 14)),
                    SizedBox(width: 48),
                    RxSkeleton(width: 64, height: 14),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final categoryBreakdown = _realtimeCategoryBreakdown;
    final totalExpenses = _currentMonthBurn;

    if (categoryBreakdown.isEmpty || totalExpenses == 0) {
      return const RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedPieChart,
          title: 'Nothing spent this month',
          message: 'Categories appear here as you add expenses',
        ),
      );
    }

    double pctOf(double amount) => _toDouble(
      FinancialCalculator.calculatePercentage(
        amount: amount,
        total: totalExpenses,
      ),
    );

    final sorted =
        categoryBreakdown.entries
            .where((e) => _toDouble(e.value) > 0)
            .map((e) => (key: e.key, amount: _toDouble(e.value)))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    // Five slices at most: past that, the tail folds into "Other".
    const maxSlices = 5;
    final rows = <({String key, String name, double amount, Color color})>[];
    final head = sorted.length > maxSlices
        ? sorted.take(maxSlices - 1)
        : sorted;
    for (final r in head) {
      rows.add((
        key: r.key,
        name: _capitalizeFirstLetter(r.key),
        amount: r.amount,
        color: RxCategory.color(context, r.key),
      ));
    }
    final folded = sorted.length - head.length;
    if (folded > 0) {
      rows.add((
        key: _otherKey,
        name: 'Other ($folded)',
        amount: sorted
            .skip(head.length)
            .fold<double>(0, (a, r) => a + r.amount),
        color: rx.textTertiary,
      ));
    }

    final selIndex = rows.indexWhere((r) => r.key == _selectedCategory);
    final sel = selIndex >= 0 ? rows[selIndex] : null;

    final centerTitle = sel?.name ?? 'This month';
    final centerValue = _formatCurrency(sel?.amount ?? totalExpenses);
    final centerNote = sel != null
        ? '${pctOf(sel.amount).round()}% of spend'
        : '${sorted.length} ${sorted.length == 1 ? 'category' : 'categories'}';

    return RxCard(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Column(
        children: [
          RxDonut(
            key: ValueKey('donut-$_chartEpoch'),
            segments: [
              for (final r in rows)
                RxDonutSegment(value: r.amount, color: r.color),
            ],
            trackColor: rx.textPrimary.withValues(alpha: 0.06),
            selected: selIndex >= 0 ? selIndex : null,
            semanticLabel:
                'Spending by category this month: ${rows.map((r) => '${r.name} ${pctOf(r.amount).round()}%').join(', ')}',
            center: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Column(
                key: ValueKey(centerTitle),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    centerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: RxText.caption(context),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      centerValue,
                      style: RxText.value(context, size: 22),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    centerNote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RxText.micro(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < rows.length; i++)
            _buildLegendRow(
              name: rows[i].name,
              color: rows[i].color,
              pct: pctOf(rows[i].amount),
              amount: rows[i].amount,
              selected: i == selIndex,
              dimmed: selIndex >= 0 && i != selIndex,
              onTap: () => setState(() {
                _selectedCategory = _selectedCategory == rows[i].key
                    ? null
                    : rows[i].key;
              }),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildLegendRow({
    required String name,
    required Color color,
    required double pct,
    required double amount,
    required bool selected,
    required bool dimmed,
    required VoidCallback onTap,
  }) {
    final rx = context.rx;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name, ${pct.round()} percent, ${_formatCurrency(amount)}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? rx.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: dimmed ? 0.5 : 1,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RxText.body(context),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${pct.round()}%',
                    textAlign: TextAlign.right,
                    style: RxText.label(context, color: rx.textTertiary),
                  ),
                ),
                const SizedBox(width: 14),
                Text(_formatCurrency(amount), style: RxText.amount(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum HealthStatus { safe, warning, critical, unknown }
