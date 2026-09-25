import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer';

import 'runway_estimation_screen.dart';
import 'funds_overview_screen.dart';
import 'monthly_burn_screen.dart';
import 'chatbot_screen.dart';
import '../../../services/financial_data_service.dart';
import '../../../services/financial_calculator.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/team_member_service.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Cache for Telegram photos to avoid repeated fetching
  static final Map<String, String> _telegramPhotoCache = {};

  String? runwayValue;
  bool isLoading = true;
  String? errorMessage;

  // Storing raw numbers ensures real-time calculation and instant currency updates
  double _fundingAmount = 0.0;
  double _absoluteTotalExpenses = 0.0;
  double _currentMonthBurn = 0.0;
  double get _availableFunds => _fundingAmount - _absoluteTotalExpenses;
  double _totalSalaries = 0.0;

  // Real-time calculated Pie Chart data
  Map<String, double> _realtimeCategoryBreakdown = {};

  List<Map<String, dynamic>> allExpenses = [];

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

  Future<String> getTelegramImageUrl(String fileId) async {
    if (_telegramPhotoCache.containsKey(fileId)) {
      return _telegramPhotoCache[fileId]!;
    }
    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];

      if (botToken == null) throw Exception('Telegram bot token not found');

      final res = await http.get(
        Uri.parse(
          "https://api.telegram.org/bot$botToken/getFile?file_id=$fileId",
        ),
      );
      final data = jsonDecode(res.body);
      final path = data['result']['file_path'];
      final imageUrl = "https://api.telegram.org/file/bot$botToken/$path";

      _telegramPhotoCache[fileId] = imageUrl;
      return imageUrl;
    } catch (e) {
      debugPrint('Error getting Telegram image URL: $e');
      rethrow;
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

  Future<void> _createAIData() async {
    // Handled in auth layer
  }

  // --- REAL-TIME LISTENER SETUP (Fixes Reload & Fetching Issues) ---
  void _handleRealtimeUpdate() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      FinancialDataService.clearAllCache();
      _loadFinancialDataForPieChart();
      _syncCalculatedDataToFirestore();
    });
  }

  Future<void> _syncCalculatedDataToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final docRef = FirebaseFirestore.instance.collection("companies").doc(user.uid);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data()!;
        final currentRunway = (data['Runway'] ?? '').toString();
        final currentTotalExpenses = _toDouble(data['totalExpenses'] ?? 0);
        
        final runwayString = "$runwayValue months";
        bool needsUpdate = false;
        Map<String, dynamic> updates = {};
        
        if (currentRunway != runwayString) {
          updates['Runway'] = runwayString;
          needsUpdate = true;
        }
        
        if ((currentTotalExpenses - _absoluteTotalExpenses).abs() > 0.01) {
          updates['totalExpenses'] = _absoluteTotalExpenses;
          needsUpdate = true;
        }
        
        if (needsUpdate) {
          await docRef.update(updates);
        }
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

    // Process any scheduled future salary updates (Lazy Cron pattern)
    TeamMemberService.checkAndApplyFutureSalaries();

    // 1. Listen to Company Document (For Runway & Total Funding)
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

    // 2. Listen to Expenses Collection (For Instant Burn, Funds & Pie Chart Updates)
    _expensesSubscription = FirebaseFirestore.instance
        .collection('expenses')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            final now = DateTime.now();
            double currentMonthTotal = 0.0;
            double absoluteTotal = 0.0;
            Map<String, double> localCategoryBreakdown = {};

            // Convert Firestore docs to maps first
            final rawExpenses = snapshot.docs.map((doc) {
              final data = doc.data();
              return {...data, 'id': doc.id};
            }).toList();

            // 1) currentMonthBurn = projected burn this month → expand to end of month.
            final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
            final expandedProjected = ExpenseExpansionHelper.expandExpenses(
              rawExpenses,
              maxDate: endOfMonth,
              allowFuture: true,
            );

            final expensesList = <Map<String, dynamic>>[];
            for (final data in expandedProjected) {
              if (data['isFunding'] == true) continue;

              final amount = _toDouble(data['Amount'] ?? data['amount']);
              final dateVal = data['Date'] ?? data['date'];
              DateTime? dt;
              if (dateVal is Timestamp) {
                dt = dateVal.toDate();
              } else if (dateVal is DateTime) {
                dt = dateVal;
              }
              final category = (data['Category'] ??
                      data['category'] ??
                      'others')
                  .toString()
                  .toLowerCase();

              if (dt != null && dt.month == now.month && dt.year == now.year) {
                currentMonthTotal += amount;
                localCategoryBreakdown[category] =
                    (localCategoryBreakdown[category] ?? 0.0) + amount;
              }

              expensesList.add({
                'id': data['id'] ?? data['expenseId'] ?? '',
                'amount': amount,
                'date': dateVal is Timestamp
                    ? dateVal
                    : (dt != null ? Timestamp.fromDate(dt) : null),
                'category': category,
                'type': data['Type'] ?? data['type'] ?? 'one_time',
                'recurrenceFrequency':
                    data['recurrenceFrequency'] ?? data['loanRateType'] ?? 'monthly',
                'recurringTenureMonths':
                    data['recurringTenureMonths'] ?? data['loanTenureMonths'],
              });
            }

            // --- Compute absoluteTotal from the expensesList by filtering future dates ---
            for (final e in expensesList) {
              final dt = e['date'];
              if (dt is Timestamp && dt.toDate().isAfter(now)) {
                continue;
              } else if (dt is DateTime && dt.isAfter(now)) {
                continue;
              }
              absoluteTotal += _toDouble(e['amount']);
            }

            // Sort in memory to keep newest first
            expensesList.sort((a, b) {
              final aDate = a['date'] as Timestamp?;
              final bDate = b['date'] as Timestamp?;
              if (aDate == null) return 1;
              if (bDate == null) return -1;
              return bDate.compareTo(aDate);
            });

            setState(() {
              allExpenses = expensesList;
              _absoluteTotalExpenses = absoluteTotal;
              _currentMonthBurn = currentMonthTotal;
              _realtimeCategoryBreakdown = localCategoryBreakdown;
              _updateRunwayValue();

              _isMonthlyBurnLoading = false;
              _isPieChartLoading = false;
            });

            _handleRealtimeUpdate();
          }
        }, onError: (e) {
          log("Error fetching expenses: $e");
          if (mounted) setState(() => _isMonthlyBurnLoading = false);
        });

    // 3. Listen to Team Members Collection (For Salary Burn Updates in Trend Chart)
    _teamMembersSubscription = FirebaseFirestore.instance
        .collection('members')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
          double salariesTotal = 0.0;
          for (var doc in snapshot.docs) {
            final data = doc.data();
            salariesTotal += _toDouble(data['salary'] ?? data['Salary']);
          }
          if (mounted) {
            setState(() {
              _totalSalaries = salariesTotal;
              _updateRunwayValue();
            });
            _handleRealtimeUpdate();
          }
        });
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

  void _updateRunwayValue() {
    if (_fundingAmount <= 0) {
      runwayValue = "0.0";
      return;
    }

    final availableBalance = _fundingAmount - _absoluteTotalExpenses;
    if (availableBalance <= 0) {
      runwayValue = "0.0";
      return;
    }

    final expensesForCalculation = allExpenses
        .map(
          (expense) => {
            'amount': _toDouble(expense['amount']),
            'date': expense['date'],
            'type': 'one_time',
            'recurrenceFrequency': expense['recurrenceFrequency'],
            'recurringTenureMonths': expense['recurringTenureMonths'],
          },
        )
        .toList();

    double actualMonthlyBurn = FinancialCalculator.currentMonthBurn(
      expensesForCalculation,
    );

    if (actualMonthlyBurn == 0 && allExpenses.isNotEmpty) {
      actualMonthlyBurn = _calculateAverageMonthlyBurn();
    }

    if (actualMonthlyBurn <= 0) {
      runwayValue = "0.0";
    } else {
      runwayValue = (availableBalance / actualMonthlyBurn).toStringAsFixed(2);
    }
  }

  double _calculateAverageMonthlyBurn() {
    if (allExpenses.isEmpty) return 0.0;
    Map<String, double> monthlyTotals = {};

    for (var expense in allExpenses) {
      final expenseDate = expense['date'] as Timestamp?;
      if (expenseDate != null) {
        final expenseDateTime = expenseDate.toDate();
        final monthKey =
            "${expenseDateTime.year}-${expenseDateTime.month.toString().padLeft(2, '0')}";

        monthlyTotals[monthKey] =
            (monthlyTotals[monthKey] ?? 0.0) + _toDouble(expense['amount']);
      }
    }

    if (monthlyTotals.isEmpty) return 0.0;
    double total = monthlyTotals.values.fold(0.0, (totalSum, item) => totalSum + item);
    return total / monthlyTotals.length;
  }

  // --- PREMIUM SECTION LABEL HELPER ---
  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        color: context.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  // --- PROFILE AVATAR METHODS ---
  Widget _buildProfileAvatar(String? profileImageFileId) {
    if (profileImageFileId != null && profileImageFileId.isNotEmpty) {
      return FutureBuilder<String>(
        future: getTelegramImageUrl(profileImageFileId),
        builder: (context, snapshot) {
          return Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.borderColor, width: 1),
            ),
            child: ClipOval(
              child: snapshot.hasData
                  ? Image.network(
                      snapshot.data!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildDefaultAvatar();
                      },
                    )
                  : _buildDefaultAvatar(),
            ),
          );
        },
      );
    }
    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.borderColor, width: 1),
        color: context.cardSecondaryBackground,
      ),
      child: Icon(Icons.person, size: 20, color: context.iconPrimary),
    );
  }

  Widget _buildEmptyState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: context.textTertiary,
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

  Widget _buildRunwayDisplay(String runwayValue) {
    final runway = double.tryParse(runwayValue) ?? 0;

    if (runway <= 0) {
      return Text(
        "--",
        style: GoogleFonts.inter(
          color: context.textPrimary,
          fontSize: 56,
          fontWeight: FontWeight.w600,
          height: 1.0,
          letterSpacing: -2,
        ),
      );
    }

    final wholeMonths = runway.floor();
    final remainingDays = ((runway - wholeMonths) * 30).round();

    if (remainingDays == 0) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: "$wholeMonths",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 56,
                fontWeight: FontWeight.w600,
                height: 1.0,
                letterSpacing: -2,
              ),
            ),
            TextSpan(
              text: " months",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w600,
                height: 1.0,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
      );
    } else {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: "$wholeMonths",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 56,
                fontWeight: FontWeight.w600,
                height: 1.0,
                letterSpacing: -2,
              ),
            ),
            TextSpan(
              text: " M ",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w600,
                height: 1.0,
                letterSpacing: -1,
              ),
            ),
            TextSpan(
              text: "$remainingDays",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 56,
                fontWeight: FontWeight.w600,
                height: 1.0,
                letterSpacing: -2,
              ),
            ),
            TextSpan(
              text: " D",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w600,
                height: 1.0,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
      );
    }
  }

  String _getRunwaySubtitle(String runwayValue) {
    if (double.tryParse(runwayValue) == 0 || runwayValue == "0") {
      return "Add expenses to calculate";
    }
    return "remaining";
  }

  double _calculateRunwayProgress() {
    if (runwayValue == null || errorMessage != null) return 0.0;
    final runway = double.tryParse(runwayValue!) ?? 0;
    if (runway == 0) return 0.0;

    const double criticalThreshold = 3;
    const double warningThreshold = 6;
    const double safeThreshold = 12;

    if (runway <= criticalThreshold) {
      return (runway / criticalThreshold) * 0.33;
    } else if (runway <= warningThreshold) {
      return 0.33 +
          ((runway - criticalThreshold) /
                  (warningThreshold - criticalThreshold)) *
              0.33;
    } else if (runway <= safeThreshold) {
      return 0.66 +
          ((runway - warningThreshold) / (safeThreshold - warningThreshold)) *
              0.34;
    } else {
      return 1.0;
    }
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

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'salaries':
      case 'salary':
        return const Color(0xFF30D158);
      case 'servers':
      case 'infrastructure':
      case 'servers & infrastructure':
        return const Color(0xFF3A4B8A);
      case 'marketing':
        return const Color(0xFFFF9F0A);
      case 'office':
      case 'operations':
      case 'office & operations':
        return const Color(0xFF00BFA5);
      default:
        // Expanded dynamic colors for unmapped categories
        final colors = [
          const Color(0xFF5E5CE6),
          const Color(0xFFFF375F),
          const Color(0xFFBF5AF2),
          const Color(0xFFFFD60A),
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isDarkMode
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
          backgroundColor: context.textPrimary,
          child: Icon(Icons.chat_bubble_outline, color: context.appBackground),
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMinimalHeader(context),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RunwayEstimationScreen(),
                  ),
                ),
                child: _buildFlatRunwayCard(currentHealth),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FundsOverviewScreen(),
                        ),
                      ),
                      child: _buildFlatMetricCard(
                        label: "Available Funds",
                        value: _isFundsLoading
                            ? null
                            : _formatCurrency(_availableFunds),
                        icon: Icons.account_balance_wallet_outlined,
                        isLoading: _isFundsLoading,
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
                      child: _buildFlatMetricCard(
                        label: "Monthly Burn",
                        value:
                            _isMonthlyBurnLoading || _currentMonthBurn <= 0
                                ? '--'
                                : _formatCurrency(_currentMonthBurn),
                        icon: Icons.local_fire_department_outlined,
                        isBurn: true,
                        isLoading: _isMonthlyBurnLoading,
                        emptyLabel: _isLoadingCountry
                            ? "₹0"
                            : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0",
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionLabel("BURN TREND"),
                  _buildViewAllButton(context),
                ],
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MonthlyBurnScreen()),
                ),
                child: _buildTrendChart(),
              ),
              const SizedBox(height: 40),
              _buildSectionLabel("EXPENSE BREAKDOWN"),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MonthlyBurnScreen()),
                ),
                child: _buildPieChartBreakdown(),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildMinimalHeader(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Overview",
                style: GoogleFonts.inter(
                  color: context.textTertiary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Startup Health",
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => widget.onNavigateToTab?.call(4),
            child: _buildDefaultAvatar(),
          ),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        String? profileImageFileId;
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final userData = userSnapshot.data!.data() as Map<String, dynamic>;
          profileImageFileId = userData['profileImageFileId'];
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Overview",
                  style: GoogleFonts.inter(
                    color: context.textTertiary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Startup Health",
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () => widget.onNavigateToTab?.call(4),
              child: _buildProfileAvatar(profileImageFileId),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFlatRunwayCard(HealthStatus status) {
    Color statusColor;
    String statusText;
    switch (status) {
      case HealthStatus.safe:
        statusColor = const Color(0xFF30D158);
        statusText = "SAFE";
        break;
      case HealthStatus.warning:
        statusColor = const Color(0xFFFF9F0A);
        statusText = "WARNING";
        break;
      case HealthStatus.critical:
        statusColor = const Color(0xFFFF453A);
        statusText = "CRITICAL";
        break;
      case HealthStatus.unknown:
        statusColor = context.textSecondary;
        statusText = "NO DATA";
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionLabel("EST. RUNWAY"),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: GoogleFonts.inter(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isLoading)
                Text(
                  "--",
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 56,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    letterSpacing: -2,
                  ),
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _buildRunwayDisplay(runwayValue ?? "0"),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getRunwaySubtitle(runwayValue ?? "0"),
                        style: GoogleFonts.inter(
                          color: context.textTertiary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _calculateRunwayProgress(),
              minHeight: 4,
              backgroundColor: context.glassBackground,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlatMetricCard({
    required String label,
    String? value,
    required IconData icon,
    bool isBurn = false,
    bool isLoading = false,
    String? emptyLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        children: [
          Icon(icon, color: context.iconSecondary, size: 20),
          const SizedBox(height: 20),
          if (isLoading)
            AnimatedOpacity(
              opacity: 0.3,
              duration: const Duration(milliseconds: 600),
              child: Container(
                width: 80,
                height: 24,
                decoration: BoxDecoration(
                  color: context.glassBackgroundStrong,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value ??
                    emptyLabel ??
                    (_isLoadingCountry
                        ? "₹0"
                        : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)}0"),
                style: GoogleFonts.inter(
                  color: value != null
                      ? context.textPrimary
                      : context.textSecondary,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
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
      child: _isTrendLoading
          ? SizedBox(
              height: 160,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.iconSecondary,
                ),
              ),
            )
          : _trendData.isEmpty
          ? _buildEmptyState("Not enough data for trend analysis")
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
                      return _buildFlatBar(
                        data['month'] as String,
                        pct,
                        amount,
                        isActive: data['isCurrentMonth'] as bool? ?? false,
                      );
                    }).toList(),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildFlatBar(
    String label,
    double pct,
    double amount, {
    bool isActive = false,
  }) {
    final safePct = pct == 0.0 ? 0.02 : pct.clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            _formatCurrency(amount),
            style: GoogleFonts.inter(
              color: isActive ? context.textPrimary : context.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: safePct,
              child: Container(
                width: 36,
                decoration: BoxDecoration(
                  color: isActive
                      ? context.textPrimary
                      : context.cardSecondaryBackground,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            color: isActive ? context.textPrimary : context.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildPieChartBreakdown() {
    if (_isPieChartLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderColor),
        ),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.iconSecondary,
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
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderColor),
        ),
        child: _buildEmptyState("No expense data available"),
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
      (a, b) => ((b['percentage'] as num?)?.toInt() ?? 0)
          .compareTo((a['percentage'] as num?)?.toInt() ?? 0),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
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
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 140,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 4,
                      centerSpaceRadius: 40,
                      centerSpaceColor: Colors.transparent,
                      sections: expenseData.map((data) {
                        return PieChartSectionData(
                          color: data['color'] as Color,
                          value: _toDouble(data['percentage']),
                          title: '',
                          radius: 16,
                          showTitle: false,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: expenseData.map((data) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: data['color'] as Color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              data['category'] as String,
                              style: GoogleFonts.inter(
                                color: context.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${data['percentage']}%',
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [
                                const FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.glassBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Monthly Expenses',
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatCurrency(totalExpenses),
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
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

  Widget _buildViewAllButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MonthlyBurnScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: context.glassBackgroundStrong,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Text(
              "VIEW ALL",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward, color: context.textPrimary, size: 12),
          ],
        ),
      ),
    );
  }
}

enum HealthStatus { safe, warning, critical, unknown }