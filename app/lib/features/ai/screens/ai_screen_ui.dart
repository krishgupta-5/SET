import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:startup_expense_tracker/theme/app_theme.dart';

import 'package:startup_expense_tracker/services/currency_formatter.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';
import 'package:startup_expense_tracker/services/ai_cache_service.dart';
import 'package:startup_expense_tracker/services/chat_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:startup_expense_tracker/features/ai/widgets/main_insight_card.dart';
import 'package:google_fonts/google_fonts.dart';

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
  bool _isFetchingMore = false; // a batch of section requests is in flight
  final List<String> _pendingSections = [];
  Map<String, dynamic>? _cachedPayload;

  Map<String, dynamic>? _mainData;
  Map<String, dynamic>? _keyPointsData;
  Map<String, dynamic>? _runwayData;
  Map<String, dynamic>? _burnData;
  Map<String, dynamic>? _staffingData;
  Map<String, dynamic>? _expenseData;
  Map<String, dynamic>? _subscriptionData;
  
  String _userCountryCode = '+1'; // Default

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _initializeLoadStates();
    _initializeAndFetch();
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) {
      final newCurrency = CurrencyPreferenceService.getCurrencyPreferenceSync();
      if (_userCountryCode != newCurrency) {
        setState(() {
          _userCountryCode = newCurrency;
        });
        
        // Reset load states so lazy-loaded sections will re-fetch
        _initializeLoadStates();
        _pendingSections.clear();
        
        // Re-fetch insights from backend with new currency
        _fetchAIInsight();
      }
    }
  }

  Future<void> _initializeAndFetch() async {
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    final asyncCode = await CurrencyPreferenceService.getCurrencyPreference();
    if (mounted && asyncCode != _userCountryCode) {
      setState(() => _userCountryCode = asyncCode);
    }
    
    // Removed unnecessary AIService.syncAICollections() here since _fetchAIInsight fetches data.

    await _fetchAIInsight();
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

  Future<void> _fetchAIInsight({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final String uid = user.uid;

      // Check cache first!
      if (!forceRefresh) {
        final isValid = await AiCacheService.isCacheValid();
        if (isValid) {
          final rawCachedState = await AiCacheService.loadSectionCache('full_ui_state');
          if (rawCachedState != null && rawCachedState.isNotEmpty) {
            debugPrint("Loaded UI AI insights from fast local cache!");
            setState(() {
              final map = rawCachedState[0] as Map<String, dynamic>;
              _mainData = map["main"];
              _keyPointsData = map["keyPoints"];
              _runwayData = map["runway"];
              _burnData = map["burn"];
              _staffingData = map["staffing"];
              _expenseData = map["expense"];
              _subscriptionData = map["subscription"];
              // Everything is restored, so show every section immediately.
              _sectionLoadStates.updateAll((_, _) => true);
              _isLoading = false;
            });
            return;
          }
        }
      }

      final db = FirebaseFirestore.instance;
      final results = await Future.wait<QuerySnapshot<Map<String, dynamic>>?>([
        // All expenses (not the latest 50): totals, recurring expansion and
        // runway are wrong on a slice. The backend re-reads Firestore anyway;
        // this is the fallback snapshot.
        db.collection('expenses').where('uid', isEqualTo: uid).limit(1000).get(),
        db.collection('companies').where('uid', isEqualTo: uid).limit(1).get(),
        db.collection('teams').where('uid', isEqualTo: uid).get(),
        db.collection('members').where('uid', isEqualTo: uid).get(),
        db
            .collection('revenue')
            .where('uid', isEqualTo: uid)
            .get()
            .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s, onError: (_) => null),
      ]);
      final expensesSnapshot = results[0]!;
      final companySnapshot = results[1]!;
      final teamsSnapshot = results[2]!;
      final membersSnapshot = results[3]!;
      final revenueSnapshot = results[4];

      if (!mounted) return;

      if (expensesSnapshot.docs.isEmpty && membersSnapshot.docs.isEmpty) {
        setState(() {
          _mainData = {
            "primary_insight": "Welcome to AI Insights",
            "high_impact_summary": "NO DATA",
            "description": "No expenses recorded yet. Add some expenses to generate your first financial intelligence report.",
          };
          _isLoading = false;
        });
        return;
      }

      // Keep every field the metrics need (isFunding, recurrence, tenure,
      // skippedOccurrences, memberId) plus the doc id.
      List<Map<String, dynamic>> docs(QuerySnapshot<Map<String, dynamic>>? s) =>
          (s?.docs ?? const [])
              .map((d) => {..._cleanTimestamps(d.data()), 'id': d.id})
              .toList();

      final company = docs(companySnapshot);
      _cachedPayload = {
        "expenses": docs(expensesSnapshot),
        "revenue": docs(revenueSnapshot),
        "company": company.isNotEmpty ? company.first : {},
        "members": docs(membersSnapshot),
        "teams": docs(teamsSnapshot),
      };

      // Above-the-fold first; the rest load as the user scrolls.
      _pendingSections.addAll(["main", "keyPoints"]);
      _processQueue();
    } catch (e) {
      debugPrint("Error fetching data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processQueue() async {
    if (_isFetchingMore || _pendingSections.isEmpty || _cachedPayload == null) {
      return;
    }

    setState(() => _isFetchingMore = true);

    final sectionsToProcess = List<String>.from(_pendingSections);
    _pendingSections.clear();

    String baseUrl = ChatService.baseUrl;

    final currencySymbol = CurrencyFormatter.getCurrencySymbol(_userCountryCode);
    debugPrint("====== AI SCREEN UI DEBUG ======");
    debugPrint("Current _userCountryCode: $_userCountryCode");
    debugPrint("Calculated currencySymbol: $currencySymbol");
    debugPrint("=============================");

    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();

    // Sections are independent; request them in parallel instead of one
    // after another (7 sequential LLM calls took up to ~2 minutes).
    await Future.wait(sectionsToProcess.map((sectionKey) async {
      try {
        final requestBody = {
          "sectionName": sectionKey,
          "sectionData": _cachedPayload,
          "currencySymbol": currencySymbol,
        };

        final res = await _postWithRetry(
          "$baseUrl/generate-ai-section",
          {
            "Content-Type": "application/json",
            if (token != null) "Authorization": "Bearer $token",
          },
          requestBody,
        );

        if (!mounted) return;

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final insight = data["insight"];

          if (!mounted) return;

          // Backend may return HTTP 200 with an error payload inside "insight".
          if (insight is Map<String, dynamic> &&
              insight.containsKey('error')) {
            debugPrint(
              "Backend error for section $sectionKey: "
              "${insight['code'] ?? insight['error']}",
            );
            _applySectionError(
              sectionKey,
              "We couldn't load this section right now. Please try again in a moment.",
            );
            return;
          }

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
        } else {
          debugPrint("AI section $sectionKey failed: HTTP ${res.statusCode}");
          _applySectionError(
            sectionKey,
            res.statusCode == 429
                ? "Too many requests. Please wait a minute and pull to refresh."
                : "We couldn't load this section right now. Please try again in a moment.",
          );
        }
      } catch (e) {
        debugPrint("Failed to load AI section $sectionKey: $e");
        if (mounted) {
          // Don't surface raw exception text to users.
          _applySectionError(
            sectionKey,
            "Couldn't reach the AI service. Pull down to retry.",
          );
        }
      }
    }));

    if (!mounted) return;
    setState(() => _isFetchingMore = false);

    // Sections requested while this batch was running (scrolling) go next.
    if (_pendingSections.isNotEmpty) {
      _processQueue();
      return;
    }

    {
      // Only cache once every section loaded cleanly; never persist error
      // placeholders, or a one-off failure keeps showing until the cache expires.
      final hasError = _sectionHasError(_mainData) ||
          _sectionHasError(_keyPointsData) ||
          _sectionHasError(_runwayData) ||
          _sectionHasError(_burnData) ||
          _sectionHasError(_staffingData) ||
          _sectionHasError(_expenseData) ||
          _sectionHasError(_subscriptionData);
      if (!hasError && _mainData != null) {
        final uiState = {
          "main": _mainData,
          "keyPoints": _keyPointsData,
          "runway": _runwayData,
          "burn": _burnData,
          "staffing": _staffingData,
          "expense": _expenseData,
          "subscription": _subscriptionData,
        };
        await AiCacheService.saveSectionCache('full_ui_state', [uiState]);
        await AiCacheService.updateSyncTimestamp();
      }
    }
  }

  /// Posts to the backend with a retry for Render free-tier cold starts.
  /// Retries on network errors/timeouts and 5xx responses; 60s timeout per attempt.
  Future<http.Response> _postWithRetry(
    String url,
    Map<String, String> headers,
    Object body, {
    int maxAttempts = 2,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final r = await http.post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 60));

        // Accept any response on the final attempt; retry 5xx cold starts.
        if (r.statusCode < 500 || attempt == maxAttempts) {
          return r;
        }
      } catch (_) {
        if (attempt == maxAttempts) rethrow;
      }
      await Future.delayed(Duration(seconds: 2 * attempt));
    }
    throw Exception('Request failed after $maxAttempts attempts');
  }

  Map<String, dynamic>? _dataFor(String sectionKey) => switch (sectionKey) {
    'main' => _mainData,
    'keyPoints' => _keyPointsData,
    'runway' => _runwayData,
    'burn' => _burnData,
    'staffing' => _staffingData,
    'expense' => _expenseData,
    'subscription' => _subscriptionData,
    _ => null,
  };

  /// True if a section is missing or holds an error placeholder from
  /// [_applySectionError].
  bool _sectionHasError(Map<String, dynamic>? data) {
    if (data == null) return true;
    if (data.containsKey('error')) return true;
    final items = data['items'];
    if (items is List &&
        items.any((i) => i is Map && i['title'] == 'Connection Error')) {
      return true;
    }
    final bullets = data['bullet_points'];
    if (bullets is List &&
        bullets.any((b) => b is String && b.startsWith('Connection Error'))) {
      return true;
    }
    final insight = data['insight'];
    return insight is String && insight.startsWith('Connection Error');
  }

  /// Applies a per-section error fallback so the UI shows friendly content
  /// instead of raw API responses.
  void _applySectionError(String sectionKey, String error) {
    setState(() {
      if (sectionKey == "main") {
        _mainData = {"error": error, "code": "llm_unavailable"};
      } else if (sectionKey == "keyPoints") {
        _keyPointsData = {
          "items": [
            {
              "title": "Connection Error",
              "description": error,
              "savings": "N/A",
              "color": "#FF453A",
            },
          ],
        };
      } else if (sectionKey == "runway") {
        _runwayData = {"bullet_points": ["Connection Error: $error"]};
      } else if (sectionKey == "burn") {
        _burnData = {
          "items": [
            {
              "title": "Connection Error",
              "description": error,
              "savings": "N/A",
              "color": "#FF453A",
            },
          ],
        };
      } else if (sectionKey == "staffing") {
        _staffingData = {"insight": "Connection Error: $error"};
      } else if (sectionKey == "expense") {
        _expenseData = {"insight": "Connection Error: $error"};
      } else if (sectionKey == "subscription") {
        _subscriptionData = {
          "items": [
            {
              "title": "Connection Error",
              "description": error,
              "savings": "N/A",
              "color": "#FF453A",
            },
          ],
        };
      }
    });
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
    // Only the above-the-fold sections start loaded; the rest are requested
    // by _loadSection as the user scrolls (previously all were "true", so
    // lazy loading never happened and every refresh made 7 LLM calls).
    const eager = {'main', 'keyPoints'};
    for (final section in sections) {
      _sectionLoadStates[section] = eager.contains(section);
    }
  }

  void _loadSection(String sectionKey) {
    if (_sectionLoadStates[sectionKey]! || _cachedPayload == null) return;
    // Already have content for this section (e.g. restored from cache).
    if (_dataFor(sectionKey) != null) {
      setState(() => _sectionLoadStates[sectionKey] = true);
      return;
    }
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
                  ? ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      itemCount: 5,
                      separatorBuilder: (_, __) => const SizedBox(height: 32),
                      itemBuilder: (_, __) => _buildShimmerPlaceholder(height: 140),
                    )
                  : RefreshIndicator(
                      color: context.textPrimary,
                      backgroundColor: context.cardBackground,
                      onRefresh: () async {
                        _initializeLoadStates();
                        _pendingSections.clear();
                        await _fetchAIInsight(forceRefresh: true);
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (scrollInfo) {
                          if (scrollInfo.metrics.pixels > 200) {
                            _loadSection('runway');
                          }
                          if (scrollInfo.metrics.pixels > 600) {
                            _loadSection('burn');
                            _loadSection('staffing');
                          }
                          if (scrollInfo.metrics.pixels > 1000) {
                            _loadSection('expense');
                            _loadSection('subscription');
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(
                            left: 24,
                            right: 24,
                            top: 16,
                            bottom: 120, // Padding for the bottom nav bar
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Main Insight Card
                              MainInsightCard(mainData: _mainData),

                              // Key Points
                              if (_sectionLoadStates['keyPoints']!)
                                _buildKeyPointsSection(),

                              // Runway Recommendations
                              if (_sectionLoadStates['runway']!)
                                _buildRunwayRecommendationsSection(),

                              // Burn Optimization
                              if (_sectionLoadStates['burn']!)
                                _buildBurnOptimizationSection(),

                              // Staffing Insights
                              if (_sectionLoadStates['staffing']!)
                                _buildStaffingInsightsSection(),

                              // Expense Analysis
                              if (_sectionLoadStates['expense']!)
                                _buildExpenseAnalysisSection(),

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

  Widget _buildShimmerPlaceholder({double height = 140}) {
    return Shimmer.fromColors(
      baseColor: context.isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: context.isDarkMode ? Colors.grey[700]! : Colors.grey[100]!,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: context.isDarkMode ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(20),
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
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Financial Recommendations",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
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
              boxShadow: context.cardShadow,
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

  // MainInsightCard extracted to widgets/main_insight_card.dart

  bool _isInsightBlank(String insight) {
    final lower = insight.toLowerCase().trim();
    if (lower.isEmpty) return true;
    if (lower.contains("insufficient data")) return true;
    if (lower.contains("not enough data")) return true;
    if (lower == "none" || lower == "n/a") return true;
    if (lower.contains("no insight")) return true;
    return false;
  }

  Widget _buildKeyPointsSection() {
    if (_keyPointsData == null) {
      return _buildShimmerPlaceholder(height: 160);
    }
    final items = _keyPointsData?['items'] as List<dynamic>? ?? [];

    if (items.isEmpty || (items.length == 1 && _isInsightBlank(items[0]['title']?.toString() ?? ''))) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          "Key Recommendations",
          style: TextStyle(
            fontFamily: 'Satoshi',
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
            boxShadow: context.cardShadow,
          ),
          child: Column(
            children: items.map((item) {
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
    ),
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
        color: context.isDarkMode
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
                  style: TextStyle(
                    fontFamily: 'Satoshi',
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
                  style: TextStyle(
                    fontFamily: 'Satoshi',
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
            style: TextStyle(
              fontFamily: 'Satoshi',
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

  Widget _buildChart(Map<String, dynamic> data, {String defaultType = 'bar'}) {
    final chartType = data['chart_type'] as String? ?? defaultType;
    final chartData = data['chart_data'] as List<dynamic>?;
    
    if (chartData == null || chartData.isEmpty) {
      return const SizedBox.shrink();
    }

    try {
      if (chartType == 'pie') {
        return _buildPieChart(chartData);
      } else if (chartType == 'bar') {
        return _buildBarChart(chartData);
      }
    } catch (e) {
      debugPrint("Error building chart: $e");
    }
    return const SizedBox.shrink();
  }

  Widget _buildPieChart(List<dynamic> chartData) {
    double total = chartData.fold(0.0, (sum, item) {
      double val = double.tryParse((item as Map<String, dynamic>)['value'].toString()) ?? 0;
      return sum + val;
    });

    return Column(
      children: [
        Container(
          height: 200,
          margin: const EdgeInsets.only(top: 24, bottom: 24),
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 60,
              sections: chartData.map((dynamic dataItem) {
                final item = dataItem as Map<String, dynamic>;
                double val = double.tryParse(item['value'].toString()) ?? 0;
                double percent = total > 0 ? (val / total) * 100 : 0;
                if (val <= 0) val = 0.0001; // Avoid layout crash if sum is 0
                final colorHex = item['color']?.toString() ?? '#30D158';
                final color = HexColor.fromHex(colorHex, context);
                return PieChartSectionData(
                  color: color,
                  value: val,
                  showTitle: percent >= 5,
                  title: '${percent.toStringAsFixed(0)}%',
                  titleStyle: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  radius: percent >= 5 ? 25 : 20,
                );
              }).toList(),
            ),
          ),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: chartData.map((item) {
            final data = item as Map<String, dynamic>;
            final colorHex = data['color']?.toString() ?? '#30D158';
            final color = HexColor.fromHex(colorHex, context);
            final label = data['label']?.toString() ?? '';
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBarChart(List<dynamic> chartData) {
    final maxVal = chartData.map((e) {
      if (e is Map) return double.tryParse(e['value'].toString()) ?? 0.0;
      return 0.0;
    }).reduce((a, b) => a > b ? a : b);
    
    final safeMaxY = maxVal <= 0 ? 100.0 : maxVal * 1.2;

    return Container(
      height: 200,
      margin: const EdgeInsets.only(top: 24, bottom: 8),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: safeMaxY,
          minY: 0,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < chartData.length) {
                    final item = chartData[value.toInt()] as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        item['label']?.toString() ?? '',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: safeMaxY / 4 > 0 ? safeMaxY / 4 : 1, // Safe interval
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: context.isDarkMode ? Colors.white10 : Colors.black12,
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(show: false),
          barGroups: chartData.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value as Map<String, dynamic>;
            final val = double.tryParse(item['value'].toString()) ?? 0;
            final colorHex = item['color']?.toString() ?? '#30D158';
            final color = HexColor.fromHex(colorHex, context);
            return BarChartGroupData(
              x: idx,
              barRods: [
                BarChartRodData(
                  toY: val < 0 ? 0 : val,
                  color: color,
                  width: 16,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(6),
                  ),
                )
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRunwayRecommendationsSection() {
    if (_runwayData == null) {
      return _buildShimmerPlaceholder(height: 140);
    }
    final bulletPoints = _runwayData?['bullet_points'] as List<dynamic>? ?? [];
    
    if (bulletPoints.isEmpty || (bulletPoints.length == 1 && _isInsightBlank(bulletPoints[0].toString()))) {
      return const SizedBox.shrink();
    }
    
    final textContent = bulletPoints.map((b) => "• $b").join('\n');

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          "Runway Optimization",
          style: TextStyle(
            fontFamily: 'Satoshi',
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
            boxShadow: context.cardShadow,
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
                    style: TextStyle(
                      fontFamily: 'Satoshi',
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
                style: TextStyle(
                  fontFamily: 'Satoshi',
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
    ),
  );
}

  Widget _buildBurnOptimizationSection() {
    if (_burnData == null) {
      return _buildShimmerPlaceholder(height: 140);
    }
    final items = _burnData?['items'] as List<dynamic>? ?? [];

    if (items.isEmpty || (items.length == 1 && _isInsightBlank(items[0]['title']?.toString() ?? ''))) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          "Burn Optimization",
          style: TextStyle(
            fontFamily: 'Satoshi',
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
            boxShadow: context.cardShadow,
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
                    style: TextStyle(
                      fontFamily: 'Satoshi',
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
              if (_burnData != null && _burnData!['chart_data'] != null)
                _buildChart(_burnData!, defaultType: 'bar'),
            ],
          ),
        ),
      ],
    ),
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
        color: context.isDarkMode
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
                  style: TextStyle(
                    fontFamily: 'Satoshi',
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
                  style: TextStyle(
                    fontFamily: 'Satoshi',
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
            style: TextStyle(
              fontFamily: 'Satoshi',
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
      return _buildShimmerPlaceholder(height: 140);
    }
    final insight = _staffingData?['insight']?.toString() ?? "";

    if (_isInsightBlank(insight)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          "Staffing Analysis",
          style: TextStyle(
            fontFamily: 'Satoshi',
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
            boxShadow: context.cardShadow,
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
                    style: TextStyle(
                      fontFamily: 'Satoshi',
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
                style: TextStyle(
                  fontFamily: 'Satoshi',
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
    ),
  );
}

  Widget _buildExpenseAnalysisSection() {
    if (_expenseData == null) {
      return _buildShimmerPlaceholder(height: 140);
    }
    final insight = _expenseData?['insight']?.toString() ?? "";

    if (_isInsightBlank(insight)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          "Expense Analysis",
          style: TextStyle(
            fontFamily: 'Satoshi',
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
            boxShadow: context.cardShadow,
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
                    style: TextStyle(
                      fontFamily: 'Satoshi',
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
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (_expenseData != null && _expenseData!['chart_data'] != null)
                _buildChart(_expenseData!, defaultType: 'pie'),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildSubscriptionInsightsSection() {
    if (_subscriptionData == null) {
      return _buildShimmerPlaceholder(height: 160);
    }
    final items = _subscriptionData?['items'] as List<dynamic>? ?? [];

    if (items.isEmpty || (items.length == 1 && _isInsightBlank(items[0]['title']?.toString() ?? ''))) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          "Subscription Analysis",
          style: TextStyle(
            fontFamily: 'Satoshi',
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
            boxShadow: context.cardShadow,
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
                    style: TextStyle(
                      fontFamily: 'Satoshi',
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
    ),
  );
}
}
