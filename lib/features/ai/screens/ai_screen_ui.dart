import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:startup_expense_tracker/theme/app_theme.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';

extension HexColor on Color {
  static Color fromHex(String hexString, [BuildContext? context]) {
    if (hexString.isEmpty) {
      return context != null ? context.textPrimary : Colors.white;
    }
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    final parsed = Color(
      int.tryParse(buffer.toString(), radix: 16) ?? 0xFFFFFFFF,
    );
    if (context != null &&
        !context.isDarkMode &&
        parsed.toARGB32() == 0xFFFFFFFF) {
      return context.textPrimary;
    }
    return parsed;
  }
}

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen>
    with AutomaticKeepAliveClientMixin {
  final Map<String, bool> _sectionLoadStates = {};

  bool _isLoading = true;
  bool _isFetchingMore = false;
  final List<String> _pendingSections = [];
  Map<String, dynamic>? _cachedPayload;
  String _currencySymbol = '\$';

  Map<String, dynamic>? _mainData;
  Map<String, dynamic>? _keyPointsData;
  Map<String, dynamic>? _runwayData;
  Map<String, dynamic>? _burnData;
  Map<String, dynamic>? _staffingData;
  Map<String, dynamic>? _expenseData;
  Map<String, dynamic>? _subscriptionData;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeLoadStates();
    _initData();
  }

  Future<void> _initData() async {
    await _loadUserCurrency();
    await _fetchAIInsight();
  }

  Future<void> _loadUserCurrency() async {
    _currencySymbol = CurrencyPreferenceService.getCurrencySymbol(
      CurrencyPreferenceService.getCurrencyPreferenceSync(),
    );
    final asyncCode = await CurrencyPreferenceService.getCurrencyPreference();
    if (mounted) {
      setState(() {
        _currencySymbol = CurrencyPreferenceService.getCurrencySymbol(asyncCode);
      });
    }
  }

  Map<String, dynamic> _cleanTimestamps(Map<String, dynamic> data) {
    final cleaned = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is Timestamp) {
        cleaned[entry.key] = value.toDate().toIso8601String();
      } else if (value is Map<String, dynamic>) {
        cleaned[entry.key] = _cleanTimestamps(value);
      } else if (value is List) {
        cleaned[entry.key] = value.map((item) {
          if (item is Timestamp) return item.toDate().toIso8601String();
          if (item is Map<String, dynamic>) return _cleanTimestamps(item);
          return item;
        }).toList();
      } else {
        cleaned[entry.key] = value;
      }
    }
    return cleaned;
  }

  Future<void> _fetchAIInsight() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final String uid = user.uid;

      final expensesSnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: uid)
          .orderBy('Date', descending: true)
          .limit(50)
          .get();

      final companySnapshot = await FirebaseFirestore.instance
          .collection('companies')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      final teamsSnapshot = await FirebaseFirestore.instance
          .collection('teams')
          .where('uid', isEqualTo: uid)
          .get();

      final membersSnapshot = await FirebaseFirestore.instance
          .collection('members')
          .where('uid', isEqualTo: uid)
          .get();

      if (!mounted) return;

      final expenses = expensesSnapshot.docs.map((doc) => doc.data()).toList();
      final cleanExpenses = expenses.map((e) {
        return {
          "Amount": (e["Amount"] ?? 0).toDouble(),
          "Category": (e["Category"] ?? "unknown").toString(),
          "Type": (e["Type"] ?? "unknown").toString(),
          "Description": (e["Description"] ?? e["Title"] ?? "").toString(),
          "ExpenseType": (e["ExpenseType"] ?? "unknown").toString(),
          "TeamName": (e["TeamName"] ?? e["linkedTeamName"] ?? "general").toString(),
          "TeamMemberName": (e["TeamMemberName"] ?? "none").toString(),
          "PaymentMethod": (e["BankAccount"] ?? e["PaymentMethod"] ?? "unknown").toString(),
          "Date": (e["Date"] is Timestamp)
              ? (e["Date"] as Timestamp).toDate().toIso8601String()
              : e["Date"]?.toString() ?? "",
        };
      }).toList();

      final companyData = companySnapshot.docs.isNotEmpty
          ? _cleanTimestamps(companySnapshot.docs.first.data())
          : {};
      final teamsData = teamsSnapshot.docs.map((doc) => _cleanTimestamps(doc.data())).toList();
      final membersData = membersSnapshot.docs.map((doc) => _cleanTimestamps(doc.data())).toList();

      _cachedPayload = {
        "expenses": cleanExpenses,
        "revenue": [], 
        "company": companyData,
        "members": membersData,
        "teams": teamsData,
      };

      _pendingSections.clear();
      _pendingSections.addAll([
        "main",
        "keyPoints",
        "runway",
        "burn",
        "staffing",
        "expense",
        "subscription"
      ]);
      _processQueue();

    } catch (e) {
      debugPrint("Error fetching data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processQueue() async {
    if (_isFetchingMore || _pendingSections.isEmpty || _cachedPayload == null) return;

    setState(() => _isFetchingMore = true);

    while (_pendingSections.isNotEmpty) {
      final sectionKey = _pendingSections.removeAt(0);
      try {
        String baseUrl = Platform.isIOS ? "http://127.0.0.1:8000" : "http://10.0.2.2:8000";
        
        final requestBody = {
          "sectionName": sectionKey,
          "sectionData": _cachedPayload,
          "currencySymbol": _currencySymbol,
        };

        final res = await http.post(
          Uri.parse("$baseUrl/generate-ai-section"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(requestBody),
        );

        if (!mounted) return;

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final insight = data["insight"];
          
          setState(() {
            if (sectionKey == "main") {
              _mainData = insight;
            } else if (sectionKey == "keyPoints") {
              _keyPointsData = insight;
            } else if (sectionKey == "runway") {
              _runwayData = insight;
            } else if (sectionKey == "burn") {
              _burnData = insight;
            } else if (sectionKey == "staffing") {
              _staffingData = insight;
            } else if (sectionKey == "expense") {
              _expenseData = insight;
            } else if (sectionKey == "subscription") {
              _subscriptionData = insight;
            }
          });
        }
      } catch (e) {
        debugPrint("Failed to load AI section $sectionKey: $e");
      }
    }

    if (mounted) {
      setState(() => _isFetchingMore = false);
    }
  }

  void _initializeLoadStates() {
    final sections = [
      'main',
      'keyPoints',
      'runway',
      'burn',
      'staffing',
      'expense',
      'subscription',
    ];
    for (final section in sections) {
      _sectionLoadStates[section] = true;
    }
  }

  void _loadSection(String sectionKey) {
    if (_sectionLoadStates[sectionKey]! || _cachedPayload == null) return;
    setState(() {
      _sectionLoadStates[sectionKey] = true;
    });
    _pendingSections.add(sectionKey);
    _processQueue();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isDarkMode
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.textPrimary.withValues(alpha: 0.3),
                      ),
                    )
                  : RefreshIndicator(
                      color: context.textPrimary,
                      backgroundColor: context.cardBackground,
                      onRefresh: () async {
                  // This will show a spinner until the sync is complete
                  await _fetchAIInsight();
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (scrollInfo) {
                    return false;
                  },
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Main Insight Card
                        _buildMainInsightCard(),

                        const SizedBox(height: 32),

                        // Key Points
                        if (_sectionLoadStates['keyPoints']!)
                          _buildKeyPointsSection(),

                        const SizedBox(height: 32),

                        // Runway Recommendations
                        if (_sectionLoadStates['runway']!)
                          _buildRunwayRecommendationsSection(),

                        const SizedBox(height: 32),

                        // Burn Optimization
                        if (_sectionLoadStates['burn']!)
                          _buildBurnOptimizationSection(),

                        const SizedBox(height: 32),

                        // Staffing Insights
                        if (_sectionLoadStates['staffing']!)
                          _buildStaffingInsightsSection(),

                        const SizedBox(height: 32),

                        // Expense Analysis
                        if (_sectionLoadStates['expense']!)
                          _buildExpenseAnalysisSection(),

                        const SizedBox(height: 32),

                        // Subscription Insights
                        if (_sectionLoadStates['subscription']!)
                          _buildSubscriptionInsightsSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AI Insights",
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Financial Recommendations",
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: Icon(
              Icons.auto_awesome,
              color: context.textPrimary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainInsightCard() {
    if (_mainData == null) {
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
            color: context.textPrimary.withValues(alpha: 0.3),
          ),
        ),
      );
    }

    final primaryInsight =
        _mainData?['primary_insight'] ?? "No insight available.";
    final description =
        _mainData?['description'] ??
        "We couldn't generate an insight at this time.";
    final highImpact = _mainData?['high_impact_summary'] ?? "HIGH IMPACT";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF30D158).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: const Color(0xFF30D158).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  "PRIMARY INSIGHT",
                  style: GoogleFonts.inter(
                    color: const Color(0xFF30D158),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 96,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: const Color(0xFFFF9F0A).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    highImpact.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFF9F0A),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            primaryInsight,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyPointsSection() {
    if (_keyPointsData == null) {
      return Center(
        child: CircularProgressIndicator(
          color: context.textPrimary.withValues(alpha: 0.3),
        ),
      );
    }
    final items = _keyPointsData?['items'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Key Recommendations",
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            children:
                items.map((item) {
                  return Column(
                    children: [
                      _buildKeyPoint(
                        item['title'] ?? '',
                        item['description'] ?? '',
                        item['savings'] ?? '',
                        HexColor.fromHex(item['color'] ?? '#ffffff', context),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyPoint(
    String title,
    String description,
    String savings,
    Color color,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            context.isDarkMode
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  savings,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunwayRecommendationsSection() {
    if (_runwayData == null) {
      return Center(
        child: CircularProgressIndicator(
          color: context.textPrimary.withValues(alpha: 0.3),
        ),
      );
    }
    final bulletPoints =
        _runwayData?['bullet_points'] as List<dynamic>? ?? [];
    final textContent = bulletPoints.map((b) => "• $b").join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Runway Optimization",
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cardBackground,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: context.textPrimary,
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "OPTIMIZATION OPPORTUNITIES",
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                textContent,
                style: GoogleFonts.inter(
                  color: context.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBurnOptimizationSection() {
    if (_burnData == null) {
      return Center(
        child: CircularProgressIndicator(
          color: context.textPrimary.withValues(alpha: 0.3),
        ),
      );
    }
    final items = _burnData?['items'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Burn Optimization",
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cardBackground,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: context.textPrimary,
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "OPTIMIZATION OPPORTUNITIES",
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildOptimizationItem(
                    item['title'] ?? '',
                    item['description'] ?? '',
                    item['savings'] ?? '',
                    HexColor.fromHex(item['color'] ?? '#ffffff', context),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptimizationItem(
    String title,
    String description,
    String savings,
    Color color,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            context.isDarkMode
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  savings,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffingInsightsSection() {
    if (_staffingData == null) {
      return Center(
        child: CircularProgressIndicator(
          color: context.textPrimary.withValues(alpha: 0.3),
        ),
      );
    }
    final insight = _staffingData?['insight'] ?? "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Staffing Analysis",
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cardBackground,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF0A84FF),
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "STAFFING INSIGHT",
                    style: GoogleFonts.inter(
                      color: const Color(0xFF0A84FF),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                insight,
                style: GoogleFonts.inter(
                  color: context.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseAnalysisSection() {
    if (_expenseData == null) {
      return Center(
        child: CircularProgressIndicator(
          color: context.textPrimary.withValues(alpha: 0.3),
        ),
      );
    }
    final insight = _expenseData?['insight'] ?? "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Expense Analysis",
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cardBackground,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFFFF453A),
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "SPENDING INSIGHT",
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFF453A),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                insight,
                style: GoogleFonts.inter(
                  color: context.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionInsightsSection() {
    if (_subscriptionData == null) {
      return Center(
        child: CircularProgressIndicator(
          color: context.textPrimary.withValues(alpha: 0.3),
        ),
      );
    }
    final items = _subscriptionData?['items'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Subscription Analysis",
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cardBackground,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: context.textPrimary,
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "SUBSCRIPTION OPPORTUNITIES",
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildOptimizationItem(
                    item['title'] ?? '',
                    item['description'] ?? '',
                    item['savings'] ?? '',
                    HexColor.fromHex(item['color'] ?? '#ffffff', context),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
