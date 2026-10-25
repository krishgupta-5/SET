import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
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

class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const HomeScreen({super.key, this.onNavigateToTab});

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
      final docRef = FirebaseFirestore.instance.collection("companies").doc(user.uid);
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

  Widget _buildSectionLabel(String text, bool isDark) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: isDark ? Colors.white54 : Colors.black54,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildProfileAvatar(String? profileImageFileId, bool isDark) {
    if (profileImageFileId != null && profileImageFileId.isNotEmpty) {
      return FutureBuilder<String>(
        future: getTelegramImageUrl(profileImageFileId),
        builder: (context, snapshot) {
          return Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
                width: 1.0,
              ),
            ),
            child: ClipOval(
              child: snapshot.hasData
                  ? Image.network(
                      snapshot.data!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildDefaultAvatar(isDark),
                    )
                  : _buildDefaultAvatar(isDark),
            ),
          );
        },
      );
    }
    return _buildDefaultAvatar(isDark);
  }

  Widget _buildDefaultAvatar(bool isDark) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
          width: 1.0,
        ),
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF3F4F6),
      ),
      child: Icon(
        Icons.person,
        size: 24,
        color: isDark ? Colors.white : Colors.black,
      ),
    );
  }

  Widget _buildEmptyState(String text, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _getRunwayString(String runwayValue) {
    final runway = double.tryParse(runwayValue) ?? 0;
    if (runway <= 0) return "--";
    if (runway >= kProfitableRunwayMonths) return "Profitable";

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

  // --- HIGH CONTRAST, DISTINCT COLOR PALETTE (CRED/SLICE VIBE) ---
  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'salaries':
      case 'salary':
        return const Color(0xFF10B981); // Emerald Green
      case 'servers':
      case 'infrastructure':
      case 'servers & infrastructure':
        return const Color(0xFF3B82F6); // Bright Blue
      case 'marketing':
      case 'ads':
        return const Color(0xFFBF5AF2); // Neon Purple
      case 'office':
      case 'operations':
      case 'office & operations':
        return const Color(0xFF00BFA5); // Teal
      case 'software':
      case 'tools':
        return const Color(0xFFFF375F); // Vibrant Pink
      case 'legal':
        return const Color(0xFFFFD60A); // Vivid Yellow
      case 'meals':
      case 'food':
        return const Color(0xFFF59E0B); // Bold Orange
      case 'travel':
      case 'transport':
        return const Color(0xFF32ADE6); // Cyan
      default:
        // Expanded fallback to ensure colors never collide
        final colors = [
          const Color(0xFF3B82F6),
          const Color(0xFF10B981),
          const Color(0xFFBF5AF2),
          const Color(0xFFFF375F),
          const Color(0xFFF59E0B),
          const Color(0xFF32ADE6),
        ];
        return colors[category.hashCode % colors.length];
    }
  }

  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    HealthStatus currentHealth = _calculateHealthStatus();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium Solid Color Palette
    final bgColor = isDark ? const Color(0xFF09090B) : const Color(0xFFF9FAFB);
    // Use slightly lighter surface for cards to contrast against true black bg
    final cardColor = isDark
        ? const Color(0xFF1A1A1C)
        : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    final shadowColor = isDark
        ? Colors.transparent
        : Colors.black.withValues(alpha: 0.04);

    final textPrimary = isDark ? Colors.white : const Color(0xFF09090B);
    final textSecondary = isDark ? Colors.white54 : const Color(0xFF71717A);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bgColor,
        floatingActionButton: FloatingActionButton(
          backgroundColor: textPrimary,
          elevation: 2,
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedMessage02,
            color: bgColor,
            size: 24,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatbotScreen()),
            );
          },
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderAndHero(isDark, textPrimary, textSecondary),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // RUNWAY AND BURN PILLS
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const RunwayEstimationScreen(),
                                ),
                              ),
                              child: _buildRunwayPill(
                                currentHealth,
                                cardColor,
                                borderColor,
                                shadowColor,
                                textPrimary,
                                textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MonthlyBurnScreen(),
                                ),
                              ),
                              child: _buildBurnPill(
                                cardColor,
                                borderColor,
                                shadowColor,
                                textPrimary,
                                textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // BURN TREND
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSectionLabel("BURN TREND", isDark),
                          _buildViewAllButton(
                            context,
                            isDark,
                            textPrimary,
                            borderColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MonthlyBurnScreen(),
                          ),
                        ),
                        child: _buildTrendChart(
                          cardColor,
                          borderColor,
                          shadowColor,
                          textPrimary,
                          textSecondary,
                          isDark,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // EXPENSE BREAKDOWN
                      _buildSectionLabel("EXPENSE BREAKDOWN", isDark),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MonthlyBurnScreen(),
                          ),
                        ),
                        child: _buildDonutChartBreakdown(
                          cardColor,
                          borderColor,
                          shadowColor,
                          textPrimary,
                          textSecondary,
                          isDark,
                        ),
                      ),
                      const SizedBox(
                        height: 80,
                      ), // Reduced bottom padding, just enough for nav bar
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

  // Integrates the Header and the "Available Funds"
  Widget _buildHeaderAndHero(
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    final fundsText = _isFundsLoading ? "--" : _formatCurrency(_availableFunds);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Overview",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
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
                    return GestureDetector(
                      onTap: () => widget.onNavigateToTab?.call(4),
                      child: _buildProfileAvatar(profileImageFileId, isDark),
                    );
                  },
                )
              else
                GestureDetector(
                  onTap: () => widget.onNavigateToTab?.call(4),
                  child: _buildDefaultAvatar(isDark),
                ),
            ],
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FundsOverviewScreen()),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    fundsText,
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: textPrimary,
                      fontSize:
                          40, // Scaled down from 64 to fix "FONT SIZE IS TOO BIG"
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Pill-shaped Runway widget
  Widget _buildRunwayPill(
    HealthStatus status,
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
  ) {
    Color statusColor;
    String statusText;
    switch (status) {
      case HealthStatus.safe:
        statusColor = const Color(0xFF10B981);
        statusText = "SAFE";
        break;
      case HealthStatus.warning:
        statusColor = const Color(0xFFF59E0B);
        statusText = "WARN";
        break;
      case HealthStatus.critical:
        statusColor = const Color(0xFFEF4444);
        statusText = "CRIT";
        break;
      case HealthStatus.unknown:
        statusColor = textSecondary;
        statusText = "N/A";
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
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
              Icon(
                Icons.flight_takeoff_rounded,
                color: textSecondary,
                size: 20,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            isLoading ? "--" : _getRunwayString(runwayValue ?? "0"),
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "EST. RUNWAY",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // Pill-shaped Burn widget
  Widget _buildBurnPill(
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
  ) {
    final value = _isMonthlyBurnLoading || _currentMonthBurn <= 0
        ? '--'
        : _formatCurrency(_currentMonthBurn);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
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
              Icon(
                Icons.local_fire_department_rounded,
                color: const Color(0xFFF59E0B),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 24),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value == '--' && !_isMonthlyBurnLoading
                  ? (_isLoadingCountry
                        ? "₹0"
                        : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0")
                  : value,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "MONTHLY BURN",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
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
      child: _isTrendLoading
          ? SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textSecondary,
                ),
              ),
            )
          : _trendData.isEmpty
          ? SizedBox(
              height: 160,
              child: _buildEmptyState(
                "Not enough data for trend analysis",
                isDark,
              ),
            )
          : SizedBox(
              height: 160,
              child: Builder(
                builder: (context) {
                  List<Map<String, dynamic>> display = _trendData;
                  if (display.isNotEmpty) {
                    bool isNewestFirst =
                        display.first['isCurrentMonth'] == true;
                    if (isNewestFirst) {
                      display = display.take(6).toList().reversed.toList();
                    } else {
                      if (display.length > 6) {
                        display = display.sublist(display.length - 6);
                      }
                    }
                  }

                  final maxAmount = display.isEmpty
                      ? 1.0
                      : display
                            .map((d) => _toDouble(d['amount']))
                            .reduce((a, b) => a > b ? a : b);

                  return Row(
                    mainAxisAlignment: display.length <= 3
                        ? MainAxisAlignment.spaceEvenly
                        : MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: display.map((data) {
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
                  );
                },
              ),
            ),
    );
  }

  // Elegant capsule bars
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
    // Subtle background for inactive bars
    final inactiveBarColor = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.04);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            _formatCurrency(amount),
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
        const SizedBox(height: 8),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: safePct,
              child: Container(
                width: 32,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF3B82F6) : inactiveBarColor,
                  borderRadius: BorderRadius.circular(
                    8,
                  ), // Modern rounded rectangle
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: isActive ? textPrimary : textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // --- CRED-STYLE DONUT CHART ---
  Widget _buildDonutChartBreakdown(
    Color cardColor,
    Color borderColor,
    Color shadowColor,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    if (_isPieChartLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: textSecondary,
          ),
        ),
      );
    }

    final categoryBreakdown = _realtimeCategoryBreakdown;
    final totalExpenses = _currentMonthBurn;

    if (categoryBreakdown.isEmpty || totalExpenses == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: borderColor),
        ),
        child: _buildEmptyState("No expense data available", isDark),
      );
    }

    final categories = categoryBreakdown.map(
      (key, value) =>
          MapEntry(key, {'amount': value, 'color': _getCategoryColor(key)}),
    );

    final expenseData = categories.entries.map((entry) {
      final amount = _toDouble(entry.value['amount']);
      final percentage = FinancialCalculator.calculatePercentage(
        amount: amount,
        total: totalExpenses,
      );
      return {
        'category': _capitalizeFirstLetter(entry.key),
        'amount': amount,
        'percentage': percentage,
        'color': entry.value['color'] as Color,
      };
    }).toList();

    expenseData.sort(
      (a, b) => ((b['percentage'] as num?)?.toInt() ?? 0).compareTo(
        (a['percentage'] as num?)?.toInt() ?? 0,
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
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
        children: [
          SizedBox(
            height: 200, // Slightly reduced to make it look tighter
            child: PieChart(
              PieChartData(
                sectionsSpace: 2, // Very tight gaps like CRED
                centerSpaceRadius: 75, // Massive hollow center
                startDegreeOffset: -90, // Start from the top
                sections: expenseData.map((data) {
                  return PieChartSectionData(
                    color: data['color'] as Color,
                    value: _toDouble(data['percentage']),
                    title: '',
                    radius: 16, // Thin modern ring
                    showTitle: false,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Horizontal Legend Below Chart
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 16,
            children: expenseData.map((data) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: data['color'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    data['category'] as String,
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildViewAllButton(
    BuildContext context,
    bool isDark,
    Color textPrimary,
    Color borderColor,
  ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MonthlyBurnScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ), // Much tighter padding
        decoration: BoxDecoration(
          color:
              Colors.transparent, // Removed background color for cleaner look
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Text(
              "VIEW ALL",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: textPrimary,
                fontSize: 9, // Smaller font
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward,
              color: textPrimary,
              size: 10,
            ), // Smaller icon
          ],
        ),
      ),
    );
  }
}

enum HealthStatus { safe, warning, critical, unknown }
