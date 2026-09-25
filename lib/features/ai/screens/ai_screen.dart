import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart';

import 'package:startup_expense_tracker/services/ai_service.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../theme/app_theme.dart';

class AiScreen extends StatefulWidget {
  final String uid;

  const AiScreen({super.key, required this.uid});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen>
    with AutomaticKeepAliveClientMixin {
  final Map<String, bool> _sectionLoadStates = {};

  bool _isLoading = true;
  bool _isFetchingMore = false;
  final List<String> _pendingSections = [];
  String _userCountryCode = '+1'; // Default
  Map<String, dynamic>? aiMetrics;
  Map<String, dynamic>? _cachedPayload;

  // Dynamic list to hold parsed markdown sections from live AI
  List<Map<String, String>> _parsedInsights = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeLoadStates();
    _loadUserCurrency();
    _initialSyncAndFetch();
  }

  Future<void> _loadUserCurrency() async {
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    final asyncCode = await CurrencyPreferenceService.getCurrencyPreference();
    if (mounted && asyncCode != _userCountryCode) {
      setState(() => _userCountryCode = asyncCode);
    }
  }

  Future<void> _initialSyncAndFetch() async {
    try {
      await AIService.syncAICollections();
    } catch (e) {
      debugPrint("Failed to sync AI data in AI screen init: $e");
    }
    await _fetchAIInsight();
  }

  void _initializeLoadStates() {
    final sections = [
      'keyPoints',
      'runway',
      'investment',
      'burn',
      'staffing',
      'performance',
      'team',
      'expense',
      'subscription',
    ];
    for (final section in sections) {
      _sectionLoadStates[section] = false;
    }
    _sectionLoadStates['keyPoints'] = true;
  }

  void _loadSection(String sectionKey) {
    if (_sectionLoadStates[sectionKey]! || _cachedPayload == null) return;

    _sectionLoadStates[sectionKey] = true;
    _pendingSections.add(sectionKey);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isFetchingMore || _pendingSections.isEmpty || _cachedPayload == null) {
      return;
    }

    setState(() => _isFetchingMore = true);

    while (_pendingSections.isNotEmpty) {
      final sectionKey = _pendingSections.removeAt(0);
      try {
        String baseUrl = Platform.isIOS
            ? "http://127.0.0.1:8000"
            : "http://10.0.2.2:8000";

        final requestBody = {
          "sectionName": sectionKey,
          "sectionData": _cachedPayload,
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
          if (insight != null) {
            setState(() {
              _addStructuredInsight(insight, sectionKey, append: true);
            });
          }
        }
      } catch (e) {
        debugPrint("Failed to load AI section $sectionKey: $e");
      }
    }

    if (mounted) {
      setState(() => _isFetchingMore = false);
    }
  }

  // --- AI DATA FETCHING ---
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

      if (expensesSnapshot.docs.isEmpty) {
        setState(() {
          _parsedInsights = [
            {
              "title": "Welcome to AI Insights",
              "content":
                  "No expenses recorded yet. Add some expenses to generate your first financial intelligence report.",
            },
          ];
          _isLoading = false;
        });
        return;
      }

      final expenses = expensesSnapshot.docs.map((doc) => doc.data()).toList();
      final cleanExpenses = expenses.map((e) {
        return {
          "Amount": (e["Amount"] ?? 0).toDouble(),
          "Category": (e["Category"] ?? "unknown").toString(),
          "Type": (e["Type"] ?? "unknown").toString(),
          "Description": (e["Description"] ?? e["Title"] ?? "").toString(),
          "ExpenseType": (e["ExpenseType"] ?? "unknown").toString(),
          "TeamName": (e["TeamName"] ?? e["linkedTeamName"] ?? "general")
              .toString(),
          "TeamMemberName": (e["TeamMemberName"] ?? "none").toString(),
          "PaymentMethod": (e["BankAccount"] ?? e["PaymentMethod"] ?? "unknown")
              .toString(),
          "Date": (e["Date"] is Timestamp)
              ? (e["Date"] as Timestamp).toDate().toIso8601String()
              : e["Date"]?.toString() ?? "",
        };
      }).toList();

      final companyData = companySnapshot.docs.isNotEmpty
          ? _cleanTimestamps(companySnapshot.docs.first.data())
          : {};
      final teamsData = teamsSnapshot.docs
          .map((doc) => _cleanTimestamps(doc.data()))
          .toList();
      final membersData = membersSnapshot.docs
          .map((doc) => _cleanTimestamps(doc.data()))
          .toList();

      final sectionData = {
        "expenses": cleanExpenses,
        "revenue": [],
        "company": companyData,
        "members": membersData,
        "teams": teamsData,
      };

      _cachedPayload = sectionData;

      final requestBody = {"sectionName": "main", "sectionData": sectionData};

      String baseUrl = Platform.isIOS
          ? "http://127.0.0.1:8000"
          : "http://10.0.2.2:8000";

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
          _addStructuredInsight(insight, "main", append: false);
          aiMetrics = data["metrics"] as Map<String, dynamic>?;
        });
      } else {
        setState(() {
          _parsedInsights = [
            {"title": "Error", "content": "Server error: ${res.statusCode}"},
          ];
        });
      }
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _parsedInsights = [
          {
            "title": "Connection Failed",
            "content":
                "AI server is not running locally. Please start the Python server.",
          },
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parsedInsights = [
          {
            "title": "Error",
            "content": "Could not load AI insights. Please try again later.",
          },
        ];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- DYNAMIC MARKDOWN PARSER ---
  void _parseMarkdownToSections(String rawText, {bool append = false}) {
    if (!append) {
      _parsedInsights.clear();
    }

    String currentTitle = "Analysis";
    List<String> currentContent = [];

    final lines = rawText.split('\n');

    for (var line in lines) {
      final trimmed = line.trim();

      if (trimmed.length >= 3 &&
          (trimmed.replaceAll('=', '').isEmpty ||
              trimmed.replaceAll('-', '').isEmpty ||
              trimmed.replaceAll('*', '').isEmpty)) {
        continue;
      }

      bool isHeader = false;
      String newTitle = "";

      if (trimmed.startsWith('#')) {
        isHeader = true;
        newTitle = trimmed.replaceAll('#', '').trim();
      } else if (trimmed.startsWith('**') &&
          (trimmed.endsWith('**') ||
              trimmed.endsWith(':') ||
              trimmed.endsWith('**:') ||
              trimmed.endsWith(':**'))) {
        isHeader = true;
        newTitle = trimmed.replaceAll('*', '').replaceAll(':', '').trim();
      }

      if (isHeader) {
        if (currentContent.join('').trim().isNotEmpty) {
          _parsedInsights.add({
            'title': currentTitle,
            'content': currentContent.join('\n').trim(),
          });
        }
        currentTitle = newTitle;
        currentContent.clear();
      } else {
        currentContent.add(line);
      }
    }

    if (currentContent.join('').trim().isNotEmpty) {
      _parsedInsights.add({
        'title': currentTitle,
        'content': currentContent.join('\n').trim(),
      });
    }

    if (_parsedInsights.isEmpty) {
      _parsedInsights.add({"title": "Analysis", "content": rawText});
    }
  }

  /// Handles structured JSON insight responses from the backend.
  /// The backend returns different JSON shapes per section:
  ///   main     -> {primary_insight, high_impact_summary, description}
  ///   keyPoints/burn/subscription -> {items: [{title, description, savings, color}]}
  ///   runway   -> {bullet_points: [...]}
  ///   staffing/expense/others -> {insight: "..."}
  void _addStructuredInsight(
    dynamic insight,
    String sectionKey, {
    bool append = false,
  }) {
    if (!append) {
      _parsedInsights.clear();
    }

    // If the backend returned a plain string (fallback), parse as markdown
    if (insight is String) {
      _parseMarkdownToSections(insight, append: append);
      return;
    }

    // If it's not a Map, convert to string fallback
    if (insight is! Map) {
      _parsedInsights.add({
        "title": "Analysis",
        "content": insight?.toString() ?? "No insight available.",
      });
      return;
    }

    final Map<String, dynamic> insightMap = Map<String, dynamic>.from(insight);

    // Check for error from LLM
    if (insightMap.containsKey("error")) {
      _parsedInsights.add({
        "title": "Error",
        "content": insightMap["error"].toString(),
      });
      return;
    }

    switch (sectionKey) {
      case "main":
        final primaryInsight =
            insightMap["primary_insight"]?.toString() ?? "Financial Insight";
        final description = insightMap["description"]?.toString() ?? "";
        final impact = insightMap["high_impact_summary"]?.toString() ?? "";
        _parsedInsights.add({
          "title": primaryInsight,
          "content": impact.isNotEmpty ? "$impact — $description" : description,
        });
        break;

      case "keyPoints":
      case "burn":
      case "subscription":
        final items = insightMap["items"];
        if (items is List && items.isNotEmpty) {
          for (final item in items) {
            if (item is Map) {
              final title = item["title"]?.toString() ?? "Recommendation";
              final desc = item["description"]?.toString() ?? "";
              final savings = item["savings"]?.toString() ?? "";
              _parsedInsights.add({
                "title": title,
                "content": savings.isNotEmpty
                    ? "$desc\nPotential savings: $savings"
                    : desc,
              });
            }
          }
        }
        break;

      case "runway":
        final bullets = insightMap["bullet_points"];
        if (bullets is List && bullets.isNotEmpty) {
          final content = bullets.map((b) => "• ${b.toString()}").join("\n");
          _parsedInsights.add({
            "title": "Runway Optimization",
            "content": content,
          });
        }
        break;

      default:
        // staffing, expense, performance, team, investment, etc.
        final insightText = insightMap["insight"]?.toString() ?? "";
        if (insightText.isNotEmpty) {
          // Capitalize sectionKey for title
          final title = sectionKey[0].toUpperCase() + sectionKey.substring(1);
          _parsedInsights.add({
            "title": "$title Analysis",
            "content": insightText,
          });
        }
        break;
    }

    // If nothing was added (e.g. empty items), add a fallback
    if (_parsedInsights.isEmpty) {
      _parsedInsights.add({
        "title": "No insight available.",
        "content": "We couldn't generate an insight at this time.",
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

  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // --- CONTENT FORMATTER (BULLETS & BOLD TEXT) ---
  Widget _buildFormattedContent(String text) {
    final List<Widget> widgets = [];
    final lines = text.split('\n');

    for (var line in lines) {
      line = line.trim();

      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (line.length >= 3 &&
          (line.replaceAll('=', '').isEmpty ||
              line.replaceAll('-', '').isEmpty)) {
        continue;
      }

      if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          line.startsWith('• ')) {
        final cleanLine = line.substring(2).trim();
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "•  ",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                Expanded(child: _parseInlineMarkdown(cleanLine)),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _parseInlineMarkdown(line),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _parseInlineMarkdown(String text) {
    final List<TextSpan> spans = [];
    final parts = text.split('**');

    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;

      if (i % 2 == 1) {
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontWeight: FontWeight.w400,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        );
      }
    }
    return RichText(text: TextSpan(children: spans));
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
            _buildHeader(context),
            Expanded(
              child: _isLoading
                  ? _buildShimmerLoadingState()
                  : RefreshIndicator(
                      color: context.textPrimary,
                      backgroundColor: context.cardBackground,
                      onRefresh: () async {
                        await AIService.syncAICollections();
                        await _fetchAIInsight();
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (scrollInfo) {
                          if (scrollInfo.metrics.pixels > 100) {
                            _loadSection('runway');
                            _loadSection('investment');
                          }
                          if (scrollInfo.metrics.pixels > 400) {
                            _loadSection('burn');
                            _loadSection('staffing');
                          }
                          if (scrollInfo.metrics.pixels > 800) {
                            _loadSection('performance');
                            _loadSection('team');
                          }
                          if (scrollInfo.metrics.pixels > 1200) {
                            _loadSection('expense');
                            _loadSection('subscription');
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // --- LIVE AI DATA ---
                              if (aiMetrics != null) _buildMetricsCard(),

                              ..._parsedInsights.asMap().entries.map((entry) {
                                int index = entry.key;
                                Map<String, String> section = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: _buildDynamicInsightCard(
                                    title: section['title']!,
                                    content: section['content']!,
                                    isFirst: index == 0,
                                  ),
                                );
                              }),

                              if (_isFetchingMore) _buildShimmerBlock(),

                              const SizedBox(height: 16),

                              // --- PENDING AI SECTIONS ---
                              if (_sectionLoadStates['keyPoints']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Key Recommendations",
                                  child: Column(
                                    children: [
                                      _buildKeyPoint(
                                        "Marketing Optimization",
                                        "Reduce digital ad spend by 20% and focus on organic growth.",
                                        "\$800/mo",
                                        const Color(0xFF30D158),
                                      ),
                                      const SizedBox(height: 16),
                                      _buildKeyPoint(
                                        "Infrastructure Costs",
                                        "Switch to AWS reserved instances.",
                                        "\$1,200/mo",
                                        const Color(0xFF0A84FF),
                                      ),
                                    ],
                                  ),
                                ),

                              if (_sectionLoadStates['runway']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Runway Optimization",
                                  content:
                                      "• Reduce marketing budget by 20% to extend runway by 1.8 months\n• Delay non-essential hiring until Q1\n• Negotiate better terms with SaaS providers",
                                ),

                              if (_sectionLoadStates['investment']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Investment Strategy",
                                  content:
                                      "• Consider high-yield savings for reserve funds\n• Start Series A preparation in 3 months\n• Explore strategic partnerships",
                                ),

                              if (_sectionLoadStates['burn']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Burn Optimization",
                                  child: _buildKeyPoint(
                                    "Tool Consolidation",
                                    "Replace HubSpot with cheaper alternatives",
                                    "\$600/month",
                                    const Color(0xFFFF9F0A),
                                  ),
                                ),

                              if (_sectionLoadStates['staffing']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Staffing Analysis",
                                  content:
                                      "Engineering costs have risen by 12% due to new hires. Marketing is currently under budget.",
                                ),

                              if (_sectionLoadStates['performance']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Performance Analysis",
                                  content:
                                      "James's cost efficiency is in the top 10% of engineers. Market rate for this role is currently \$14k/mo.",
                                ),

                              if (_sectionLoadStates['team']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Team Efficiency",
                                  content:
                                      "Backend development costs are 20% higher than industry average. Consider optimizing resource allocation.",
                                ),

                              if (_sectionLoadStates['expense']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Expense Analysis",
                                  content:
                                      "This expense is 15% higher than your average for Infrastructure. Consider reviewing unused instances.",
                                ),

                              if (_sectionLoadStates['subscription']! &&
                                  !_isFetchingMore)
                                _buildPendingSection(
                                  title: "Subscription Analysis",
                                  content:
                                      "Subscriptions are 15% higher this month. Review your active AWS instances.",
                                ),

                              const SizedBox(height: 64),
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
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoading || _isFetchingMore
                      ? "Analyzing Data..."
                      : "Financial Intelligence",
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
            child: _isLoading || _isFetchingMore
                ? Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Shimmer.fromColors(
                      baseColor: context.isDarkMode
                          ? Colors.white24
                          : Colors.black26,
                      highlightColor: context.isDarkMode
                          ? Colors.white
                          : Colors.black,
                      child: const Icon(Icons.auto_awesome, size: 20),
                    ),
                  )
                : Icon(
                    Icons.auto_awesome,
                    color: context.iconPrimary,
                    size: 20,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoadingState() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          _buildShimmerBlock(height: 250),
          const SizedBox(height: 24),
          _buildShimmerBlock(height: 180),
          const SizedBox(height: 24),
          _buildShimmerBlock(height: 200),
        ],
      ),
    );
  }

  Widget _buildShimmerBlock({double height = 180}) {
    return Shimmer.fromColors(
      baseColor: context.isDarkMode
          ? const Color(0xFF141416)
          : Colors.black.withValues(alpha: 0.04),
      highlightColor: context.isDarkMode
          ? const Color(0xFF2A2A2E)
          : Colors.black.withValues(alpha: 0.08),
      child: Container(
        width: double.infinity,
        height: height,
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(24),
          boxShadow: context.cardShadow,
        ),
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 32),
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
          Text(
            "KEY METRICS",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _buildMetricRow(
            "Total Spending",
            CurrencyFormatter.formatByCountry(
              _safeDouble(aiMetrics!['total_spending']),
              _userCountryCode,
            ),
          ),
          _buildMetricRow(
            "Average Spending",
            CurrencyFormatter.formatByCountry(
              _safeDouble(aiMetrics!['avg_spending']),
              _userCountryCode,
            ),
          ),
          _buildMetricRow(
            "Net Burn Rate",
            CurrencyFormatter.formatByCountry(
              _safeDouble(aiMetrics!['net_burn']),
              _userCountryCode,
            ),
          ),
          _buildMetricRow("Risk Level", "${aiMetrics!['risk'] ?? 'Unknown'}"),
          if (aiMetrics!['funding'] != null)
            _buildMetricRow(
              "Total Funding",
              CurrencyFormatter.formatByCountry(
                _safeDouble(aiMetrics!['funding']),
                _userCountryCode,
              ),
            ),
          _buildMetricRow("Teams", "${aiMetrics!['team_count'] ?? 0}"),
          _buildMetricRow("Members", "${aiMetrics!['member_count'] ?? 0}"),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicInsightCard({
    required String title,
    required String content,
    required bool isFirst,
  }) {
    final Color badgeColor = isFirst
        ? const Color(0xFF30D158)
        : const Color(0xFF0A84FF);
    final String badgeText = isFirst ? "PRIMARY INSIGHT" : "RECOMMENDATION";

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: badgeColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          _buildFormattedContent(content),
        ],
      ),
    );
  }

  Widget _buildPendingSection({
    required String title,
    String? content,
    Widget? child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.glassBackgroundStrong,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  "PENDING AI",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    "EXAMPLE GENERATION:",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (content != null) _buildFormattedContent(content),
                ?child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyPoint(
    String title,
    String desc,
    String savings,
    Color color,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.glassBackgroundStrong,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
          const SizedBox(height: 12),
          Text(
            desc,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
