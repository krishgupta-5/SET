import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/theme/app_theme.dart';
import 'package:startup_expense_tracker/widgets/rx_ui.dart';
import 'package:startup_expense_tracker/features/ai/widgets/ai_widgets.dart';
import 'package:startup_expense_tracker/features/home/screens/chatbot_screen.dart';
import 'package:startup_expense_tracker/widgets/rx_motion.dart';
import 'package:startup_expense_tracker/widgets/custom_bottom_nav.dart'
    show RxTabBar;

import 'package:startup_expense_tracker/services/currency_formatter.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';
import 'package:startup_expense_tracker/services/ai_cache_service.dart';
import 'package:startup_expense_tracker/services/chat_service.dart';
import 'package:startup_expense_tracker/features/ai/widgets/main_insight_card.dart';

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
  const AiScreen({
    super.key,
    this.onAddExpense,
    this.onOpenTeam,
    this.refreshToken,
  });

  /// Opens the add-expense flow (used by the empty state).
  final VoidCallback? onAddExpense;

  /// Switches to the Team tab (used by the empty state).
  final VoidCallback? onOpenTeam;

  /// Changes when data may have changed or the tab is reopened. While the
  /// screen is empty, a change triggers a re-check so insights appear as soon
  /// as the user adds their first expense or team member.
  final Object? refreshToken;

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen>
    with AutomaticKeepAliveClientMixin {
  final Map<String, bool> _sectionLoadStates = {};

  bool _isLoading = true;

  // True when the account has no expenses and no team members yet.
  bool _isEmpty = false;

  // Bumped on every fetch; results from an older fetch are dropped, so a
  // refresh never shows old and new content one after another.
  int _generation = 0;
  bool _isFetchingMore = false;
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
  void didUpdateWidget(covariant AiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isEmpty &&
        !_isLoading &&
        widget.refreshToken != null &&
        widget.refreshToken != oldWidget.refreshToken) {
      _initializeLoadStates();
      _fetchAIInsight(forceRefresh: true);
    }
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
    _generation++;
    _pendingSections.clear();
    setState(() {
      _isLoading = true;
      if (forceRefresh) {
        _mainData = null;
        _keyPointsData = null;
        _runwayData = null;
        _burnData = null;
        _staffingData = null;
        _expenseData = null;
        _subscriptionData = null;
      }
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final String uid = user.uid;

      // Check cache first!
      if (!forceRefresh) {
        final isValid = await AiCacheService.isCacheValid();
        if (isValid) {
          final rawCachedState = await AiCacheService.loadSectionCache(
            'full_ui_state',
          );
          if (rawCachedState != null && rawCachedState.isNotEmpty) {
            debugPrint("Loaded UI AI insights from fast local cache!");
            setState(() {
              final map = rawCachedState[0] as Map<String, dynamic>;
              _isEmpty = false;
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

      final empty =
          expensesSnapshot.docs.isEmpty && membersSnapshot.docs.isEmpty;
      setState(() => _isEmpty = empty);
      if (empty) {
        // Nothing to analyse: show the getting-started card, not sections
        // that would wait forever for a payload that never comes.
        _cachedPayload = null;
        setState(() {
          _mainData = null;
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
      if (mounted) {
        setState(
          () => _mainData = {"error": "fetch_failed", "code": "fetch_failed"},
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processQueue() async {
    if (_isFetchingMore || _pendingSections.isEmpty || _cachedPayload == null) {
      return;
    }

    setState(() => _isFetchingMore = true);

    final gen = _generation;
    final sectionsToProcess = List<String>.from(_pendingSections);
    _pendingSections.clear();

    String baseUrl = ChatService.baseUrl;

    final currencySymbol = CurrencyFormatter.getCurrencySymbol(
      _userCountryCode,
    );
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

        final res = await _postWithRetry("$baseUrl/generate-ai-section", {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        }, requestBody);

        if (!mounted || gen != _generation) return; // newer refresh started

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final insight = data["insight"];

          if (!mounted || gen != _generation) return;

          // Backend may return HTTP 200 with an error payload inside "insight".
          if (insight is Map<String, dynamic> && insight.containsKey('error')) {
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
          // Server error: show the friendly fallback, not an endless loader.
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
        if (mounted && gen == _generation) {
          // Don't surface raw exception text to users.
          _applySectionError(
            sectionKey,
            "Couldn't reach the AI service. Pull down to retry.",
          );
        }
      }
    }));

    if (mounted) {
      // Only cache valid, current results; never persist errors.
      final allLoaded = _sectionLoadStates.values.every((v) => v);
      final hasError = [
        _mainData, _keyPointsData, _runwayData, _burnData,
        _staffingData, _expenseData, _subscriptionData,
      ].any(_sectionHasError);
      if (allLoaded && !hasError && gen == _generation) {
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

      setState(() => _isFetchingMore = false);
      // Sections queued while this run was busy (e.g. by a refresh).
      if (_pendingSections.isNotEmpty) _processQueue();
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
        final r = await http
            .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 60));

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
        _runwayData = {
          "bullet_points": ["Connection Error: $error"],
        };
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

  bool _isInsightBlank(String insight) {
    final lower = insight.toLowerCase().trim();
    if (lower.isEmpty) return true;
    if (lower.contains("insufficient data")) return true;
    if (lower.contains("not enough data")) return true;
    if (lower == "none" || lower == "n/a") return true;
    if (lower.contains("no insight")) return true;
    return false;
  }

  // --- UI ---

  Future<void> _refresh() async {
    if (_isLoading) return;
    HapticFeedback.selectionClick();
    _initializeLoadStates();
    _pendingSections.clear();
    await _fetchAIInsight(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rx = context.rx;
    final busy = _isLoading || _isFetchingMore;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: rx.textPrimary,
          backgroundColor: rx.surface,
          onRefresh: _refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              if (scrollInfo.metrics.pixels > 200) _loadSection('runway');
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
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                RxTabBar.reservedHeight(context),
              ),
              children: [
                RxReveal.index(0, child: _buildHeader(busy)),
                const SizedBox(height: 20),
                if (_isEmpty && !_isLoading)
                  RxReveal(child: _buildGettingStarted())
                else if (_isLoading || _mainData == null)
                  _centered(const AiThinking())
                else if (_mainData!.containsKey('error'))
                  _centered(AiOffline(onRetry: _refresh))
                else ...[
                  RxReveal(
                    key: ValueKey(identityHashCode(_mainData)),
                    child: MainInsightCard(mainData: _mainData),
                  ),
                  ..._section(
                    'keyPoints',
                    _keyPointsData,
                    _buildKeyPointsSection,
                  ),
                  ..._section(
                    'runway',
                    _runwayData,
                    _buildRunwayRecommendationsSection,
                  ),
                  ..._section('burn', _burnData, _buildBurnOptimizationSection),
                  ..._section(
                    'staffing',
                    _staffingData,
                    _buildStaffingInsightsSection,
                  ),
                  ..._section(
                    'expense',
                    _expenseData,
                    _buildExpenseAnalysisSection,
                  ),
                  ..._section(
                    'subscription',
                    _subscriptionData,
                    _buildSubscriptionInsightsSection,
                  ),
                  const SizedBox(height: 24),
                  RxReveal(
                    delay: const Duration(milliseconds: 200),
                    child: _buildAskCard(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _sectionNames = {
    'keyPoints': 'recommendations',
    'runway': 'your runway',
    'burn': 'your burn',
    'staffing': 'staffing',
    'expense': 'spending',
    'subscription': 'subscriptions',
  };

  /// A section in the feed: a small "analyzing" row while the model works,
  /// then the card, revealed when its data lands. Hidden if it says nothing.
  List<Widget> _section(
    String key,
    Map<String, dynamic>? data,
    Widget? Function() build,
  ) {
    if (!(_sectionLoadStates[key] ?? false)) return const [];
    final Widget? body = data == null
        ? _SectionLoading(label: 'Analyzing ${_sectionNames[key] ?? key}')
        : build();
    if (body == null) return const [];
    return [
      const SizedBox(height: 14),
      RxReveal(key: ValueKey('$key-${identityHashCode(data)}'), child: body),
    ];
  }

  Widget _buildHeader(bool busy) {
    return RxTabHeader(
      label: 'Insights from your numbers',
      title: 'AI CFO',
      actions: [
        RxCircleButton(
          icon: HugeIcons.strokeRoundedRefresh,
          semanticLabel: 'Refresh insights',
          onTap: busy ? null : _refresh,
        ),
      ],
    );
  }

  /// Places [child] in the middle of the space left under the header, so
  /// loading and offline states sit centred on screen (still pull-to-refresh).
  Widget _centered(Widget child) {
    final mq = MediaQuery.of(context);
    final h =
        mq.size.height -
        mq.padding.top -
        RxTabBar.reservedHeight(context) -
        110; // header + spacing
    return RxReveal(
      key: ValueKey(child.runtimeType),
      child: SizedBox(
        height: h.clamp(320.0, 900.0),
        child: Center(child: child),
      ),
    );
  }

  /// First-run state: explains what the AI CFO does and gives clear next
  /// steps, instead of a "no data" card above loaders that never finish.
  Widget _buildGettingStarted() {
    final rx = context.rx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RxCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AiChip(label: 'GET STARTED'),
              const SizedBox(height: 14),
              Text(
                'Your AI CFO needs a few numbers first',
                style: RxText.heading(context).copyWith(
                  fontSize: 19,
                  height: 1.35,
                  letterSpacing: -0.2,
                  color: rx.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Once you add expenses or team members, you get a daily '
                'briefing on runway, burn, payroll and subscriptions, with '
                'specific ways to save.',
                style: RxText.body(context, color: rx.textSecondary)
                    .copyWith(fontWeight: FontWeight.w400, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _StepCard(
          step: 1,
          icon: HugeIcons.strokeRoundedInvoice01,
          title: 'Add your first expense',
          subtitle: 'Scan a receipt or enter it manually',
          onTap: widget.onAddExpense,
        ),
        const SizedBox(height: 10),
        _StepCard(
          step: 2,
          icon: HugeIcons.strokeRoundedUserGroup,
          title: 'Add your team',
          subtitle: 'Salaries help estimate burn and runway',
          onTap: widget.onOpenTeam,
        ),
        const SizedBox(height: 10),
        _StepCard(
          step: 3,
          icon: HugeIcons.strokeRoundedSparkles,
          title: 'Come back for insights',
          subtitle: 'They appear here automatically',
        ),
        const SizedBox(height: 24),
        _buildAskCard(),
      ],
    );
  }

  Widget _buildAskCard() {
    final rx = context.rx;
    return RxPressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatbotScreen()),
      ),
      semanticLabel: 'Ask your AI CFO a question',
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
          color: rx.inverse,
          borderRadius: BorderRadius.circular(22),
          boxShadow: rx.raisedShadow,
        ),
        child: Row(
          children: [
            const RxAiBadge(size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Have a question?',
                    style: RxText.body(
                      context,
                      color: rx.onInverse,
                    ).copyWith(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ask about runway, hiring or any expense',
                    style: RxText.caption(
                      context,
                      color: rx.onInverse.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: rx.onInverse,
              size: 20,
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }

  /// Items reveal one after another inside a section.
  Widget _staggered(List<Widget> children, {bool dividers = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          dividers
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: RxDivider(indent: 28),
                )
              : const SizedBox(height: 10),
        RxReveal(
          delay: Duration(milliseconds: 120 + 90 * i),
          offset: 8,
          child: children[i],
        ),
      ],
    ],
  );

  List<Map<String, dynamic>> _items(Map<String, dynamic>? data) {
    final raw = data?['items'] as List<dynamic>? ?? [];
    final items = raw
        .whereType<Map<String, dynamic>>()
        .where((i) => i['title'] != 'Connection Error')
        .toList();
    if (items.isEmpty ||
        (items.length == 1 &&
            _isInsightBlank(items[0]['title']?.toString() ?? ''))) {
      return const [];
    }
    return items;
  }

  Widget? _itemsSection({
    required Map<String, dynamic>? data,
    required List<List<dynamic>> icon,
    required String title,
    required String subtitle,
    required AiTone tone,
    String? chartType,
  }) {
    final items = _items(data);
    if (items.isEmpty) return null;
    return AiSection(
      icon: icon,
      title: title,
      subtitle: subtitle,
      tone: tone,
      child: Column(
        children: [
          _staggered([
            for (var i = 0; i < items.length; i++)
              AiRecommendation(
                index: i + 1,
                title: (items[i]['title'] ?? '').toString(),
                description: (items[i]['description'] ?? '').toString(),
                savings: items[i]['savings']?.toString(),
                tone: tone,
              ),
          ], dividers: true),
        ],
      ),
    );
  }

  Widget? _textSection({
    required Map<String, dynamic>? data,
    required List<List<dynamic>> icon,
    required String title,
    required String subtitle,
    required AiTone tone,
    String? chartType,
  }) {
    final insight = data?['insight']?.toString() ?? '';
    if (_isInsightBlank(insight) || insight.startsWith('Connection Error')) {
      return null;
    }
    final rx = context.rx;
    return AiSection(
      icon: icon,
      title: title,
      subtitle: subtitle,
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiTypewriter(
            key: ValueKey(insight),
            text: insight,
            wordMs: 70,
            delay: const Duration(milliseconds: 150),
            style: RxText.body(
              context,
              color: rx.textSecondary,
            ).copyWith(fontWeight: FontWeight.w400, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget? _buildKeyPointsSection() => _itemsSection(
    data: _keyPointsData,
    icon: HugeIcons.strokeRoundedIdea01,
    title: 'Top recommendations',
    subtitle: 'What to act on first',
    tone: AiTone.brand,
  );

  Widget? _buildRunwayRecommendationsSection() {
    final points = (_runwayData?['bullet_points'] as List<dynamic>? ?? [])
        .map((b) => b.toString())
        .where((b) => !_isInsightBlank(b) && !b.startsWith('Connection Error'))
        .toList();
    if (points.isEmpty) return null;
    return AiSection(
      icon: HugeIcons.strokeRoundedAirplaneTakeOff01,
      title: 'Extend your runway',
      subtitle: 'Ways to make cash last longer',
      tone: AiTone.info,
      child: _staggered([
        for (final p in points) AiBullet(text: p, tone: AiTone.info),
      ]),
    );
  }

  Widget? _buildBurnOptimizationSection() => _itemsSection(
    data: _burnData,
    icon: HugeIcons.strokeRoundedFire,
    title: 'Cut your burn',
    subtitle: 'Where monthly spend can drop',
    tone: AiTone.warning,
    chartType: 'bar',
  );

  Widget? _buildStaffingInsightsSection() => _textSection(
    data: _staffingData,
    icon: HugeIcons.strokeRoundedUserGroup,
    title: 'Team and payroll',
    subtitle: 'How your people costs look',
    tone: AiTone.info,
  );

  Widget? _buildExpenseAnalysisSection() => _textSection(
    data: _expenseData,
    icon: HugeIcons.strokeRoundedPieChart,
    title: 'Spending patterns',
    subtitle: 'Where the money goes',
    tone: AiTone.negative,
    chartType: 'pie',
  );

  Widget? _buildSubscriptionInsightsSection() => _itemsSection(
    data: _subscriptionData,
    icon: HugeIcons.strokeRoundedRepeat,
    title: 'Subscriptions',
    subtitle: 'Recurring costs worth a look',
    tone: AiTone.brand,
  );
}

/// One numbered step in the getting-started list. Tappable when [onTap] set.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final int step;
  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxCard(
      onTap: onTap,
      semanticLabel: 'Step $step: $title',
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
        children: [
          RxIconTile(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: RxText.body(context, color: rx.textPrimary)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: RxText.caption(context, color: rx.textSecondary),
                ),
              ],
            ),
          ),
          if (onTap != null)
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: rx.textTertiary,
              size: 18,
              strokeWidth: 1.8,
            ),
        ],
      ),
    );
  }
}

/// Inline "the AI is working on this" row, shown while a section loads.
class _SectionLoading extends StatelessWidget {
  const _SectionLoading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return RxCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Expanded(child: Text('$label…', style: RxText.label(context))),
          const AiTypingDots(),
        ],
      ),
    );
  }
}
