import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/features/team/screens/create_team_screen.dart';
import 'team_detail_screen.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/telegram_service.dart';
import '../../../widgets/custom_bottom_nav.dart' show RxTabBar;
import '../../../widgets/rx_charts.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';
import '../team_style.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, this.visit});

  /// Changes each time the Team tab is opened (null while hidden), so the
  /// charts replay their entrance.
  final int? visit;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with WidgetsBindingObserver {
  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isSearching = false;

  // Sort
  String _selectedSortOption = "Name";
  String _selectedOrder = "A-Z";

  String _userCountryCode = '+1';

  // Live data: teams, all members, and this month's team spend. One
  // listener each instead of two per card.
  StreamSubscription<QuerySnapshot>? _teamsSub;
  StreamSubscription<QuerySnapshot>? _membersSub;
  StreamSubscription<QuerySnapshot>? _expensesSub;

  List<Map<String, dynamic>> _teams = [];
  final Map<String, List<Map<String, dynamic>>> _membersByTeam = {};
  final Map<String, double> _payrollByTeam = {};
  final Map<String, double> _spentByTeam = {};
  bool _teamsLoaded = false;
  bool _membersLoaded = false;
  bool _spendLoaded = false;
  String? _error;

  // Keys the charts; bumping it replays their sweep.
  int _chartEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadUserCountryCode();
    _listen();
  }

  @override
  void didUpdateWidget(covariant TeamScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visit != null && widget.visit != oldWidget.visit) {
      _chartEpoch++;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _teamsSub?.cancel();
    _membersSub?.cancel();
    _expensesSub?.cancel();
    _searchController.dispose();
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

  Future<void> _loadUserCountryCode() async {
    final currencyCode =
        await CurrencyPreferenceService.getCurrencyPreference();
    if (mounted && currencyCode != _userCountryCode) {
      setState(() => _userCountryCode = currencyCode);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshData();
  }

  void _refreshData() {
    if (mounted) setState(() {});
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // --- DATA ---

  void _listen() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _teamsLoaded = _membersLoaded = _spendLoaded = true;
      return;
    }
    final db = FirebaseFirestore.instance;

    _teamsSub = db
        .collection('teams')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _teams = [
                for (final doc in snap.docs)
                  {...doc.data(), 'id': doc.id, 'source': 'teams_collection'},
              ];
              _teamsLoaded = true;
              _error = null;
            });
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _teamsLoaded = true;
                _error = "Couldn't load teams";
              });
            }
          },
        );

    _membersSub = db
        .collection('members')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            _membersByTeam.clear();
            _payrollByTeam.clear();
            for (final doc in snap.docs) {
              final data = doc.data();
              final teamId = data['teamId'] as String?;
              if (teamId == null || teamId.isEmpty) continue;
              final String? tgId = data['telegramFileId'] as String?;
              final String? url = data['avatarUrl'] as String?;
              final String? legacyTgId =
                  (url != null &&
                      url.isNotEmpty &&
                      !url.startsWith('http') &&
                      !url.contains('ui-avatars.com'))
                  ? url
                  : null;
              (_membersByTeam[teamId] ??= []).add({
                'name': data['fullName'] ?? 'Unnamed',
                'avatarUrl': url ?? '',
                'telegramFileId': (tgId != null && tgId.isNotEmpty)
                    ? tgId
                    : legacyTgId,
                'memberId': doc.id,
              });
              _payrollByTeam[teamId] =
                  (_payrollByTeam[teamId] ?? 0) +
                  _num(data['monthlyCost'] ?? data['salary']);
            }
            setState(() => _membersLoaded = true);
          },
          onError: (_) {
            if (mounted) setState(() => _membersLoaded = true);
          },
        );

    // Same rule as before: expenses tagged with a team, dated this month.
    _expensesSub = db
        .collection('expenses')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            final now = DateTime.now();
            _spentByTeam.clear();
            for (final doc in snap.docs) {
              final data = doc.data();
              final teamId = data['TeamId'] as String?;
              if (teamId == null || teamId.isEmpty) continue;
              if (data['isFunding'] == true) continue;
              final date = (data['Date'] as Timestamp?)?.toDate();
              if (date == null ||
                  date.month != now.month ||
                  date.year != now.year) {
                continue;
              }
              _spentByTeam[teamId] =
                  (_spentByTeam[teamId] ?? 0) + _num(data['Amount']);
            }
            setState(() => _spendLoaded = true);
          },
          onError: (_) {
            if (mounted) setState(() => _spendLoaded = true);
          },
        );
  }

  /// Search + sort, synchronous now that member counts are local.
  List<Map<String, dynamic>> get _visibleTeams {
    var list = List<Map<String, dynamic>>.from(_teams);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where(
            (t) => (t['teamName'] ?? '').toString().toLowerCase().contains(q),
          )
          .toList();
    }
    final asc = _selectedOrder == "A-Z" || _selectedOrder == "Low-High";
    int dir(int c) => asc ? c : -c;
    list.sort((a, b) {
      switch (_selectedSortOption) {
        case "Monthly Amount":
          return dir(
            _num(a['monthlyBudget']).compareTo(_num(b['monthlyBudget'])),
          );
        case "Team Size":
          return dir(
            (_membersByTeam[a['id']]?.length ?? 0).compareTo(
              _membersByTeam[b['id']]?.length ?? 0,
            ),
          );
        default:
          return dir(
            (a['teamName'] ?? '').toString().toLowerCase().compareTo(
              (b['teamName'] ?? '').toString().toLowerCase(),
            ),
          );
      }
    });
    return list;
  }

  void _toggleOrder(String option) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedSortOption == option) {
        if (option == "Name") {
          _selectedOrder = _selectedOrder == "A-Z" ? "Z-A" : "A-Z";
        } else {
          _selectedOrder = _selectedOrder == "Low-High"
              ? "High-Low"
              : "Low-High";
        }
      } else {
        _selectedSortOption = option;
        _selectedOrder = option == "Name" ? "A-Z" : "High-Low";
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = "";
        _searchController.clear();
      }
    });
  }

  void _openCreateTeam() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateTeamScreen()),
    ).then((_) => _refreshData());
  }

  void _openTeam(Map<String, dynamic> team) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamDetailScreen(
          teamId: team['id'] as String,
          initialTeamData: team,
        ),
      ),
    ).then((_) => _refreshData());
  }

  // --- TEAM LOOK ---

  Color _teamColor(Map<String, dynamic> team) =>
      TeamStyle.color(context, team['color']?.toString());

  String _money(double v) =>
      CurrencyFormatter.formatByCountryCompact(v, _userCountryCode);

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final loading = !_teamsLoaded;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: rx.background,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async => _refreshData(),
            color: rx.textPrimary,
            backgroundColor: rx.surface,
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
                RxReveal.index(0, child: _buildHeader()),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _isSearching
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _buildSearchBar(),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 28),
                if (loading)
                  _buildSkeleton()
                else if (_error != null)
                  _buildError()
                else if (_teams.isEmpty)
                  RxReveal.index(1, child: _buildEmptyTeams())
                else ...[
                  RxReveal(
                    key: const ValueKey('team-hero'),
                    delay: const Duration(milliseconds: 60),
                    child: _buildHero(),
                  ),
                  const SizedBox(height: 24),
                  RxReveal(
                    key: const ValueKey('team-stats'),
                    delay: const Duration(milliseconds: 120),
                    child: _buildStatsCard(),
                  ),
                  const SizedBox(height: 12),
                  RxReveal(
                    key: const ValueKey('team-create'),
                    delay: const Duration(milliseconds: 180),
                    child: _buildCreateTeamButton(),
                  ),
                  const SizedBox(height: 28),
                  RxReveal(
                    key: const ValueKey('team-list'),
                    delay: const Duration(milliseconds: 240),
                    child: _buildTeamsSection(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final count = _teams.length;
    return RxTabHeader(
      label: !_teamsLoaded
          ? 'Your teams'
          : count == 1
          ? '1 team'
          : '$count teams',
      title: 'Team',
      actions: [
        RxCircleButton(
          icon: _isSearching
              ? HugeIcons.strokeRoundedCancel01
              : HugeIcons.strokeRoundedSearch01,
          semanticLabel: _isSearching ? 'Close search' : 'Search teams',
          filled: _isSearching,
          onTap: _toggleSearch,
        ),
      ],
    );
  }

  /// Primary action on the tab: a full-width, high-contrast row placed
  /// right under the summary, so it's the first thing after the numbers.
  Widget _buildCreateTeamButton() {
    final rx = context.rx;
    return RxPressable(
      onTap: _openCreateTeam,
      semanticLabel: 'Create new team',
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
        decoration: BoxDecoration(
          color: rx.inverse,
          borderRadius: BorderRadius.circular(22),
          boxShadow: rx.raisedShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: rx.onInverse.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedUserAdd01,
                color: rx.onInverse,
                size: 22,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create new team',
                    style: RxText.body(
                      context,
                      color: rx.onInverse,
                    ).copyWith(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Group people and set a monthly budget',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  Widget _buildSearchBar() {
    final rx = context.rx;
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(
        color: rx.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rx.hairline),
        boxShadow: rx.cardShadow,
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedSearch01,
            color: rx.textTertiary,
            size: 18,
            strokeWidth: 1.8,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: RxText.body(context),
              cursorColor: rx.textPrimary,
              textInputAction: TextInputAction.search,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: 'Search teams',
                hintStyle: RxText.body(context, color: rx.textTertiary),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            RxPressable(
              onTap: () => setState(() {
                _searchQuery = "";
                _searchController.clear();
              }),
              semanticLabel: 'Clear search',
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedCancelCircle,
                    color: rx.textTertiary,
                    size: 18,
                    strokeWidth: 1.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Spent this month across all teams, with a ring against total budget.
  Widget _buildHero() {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spent = _spentByTeam.values.fold<double>(0, (a, b) => a + b);
    final budget = _teams.fold<double>(
      0,
      (a, t) => a + _num(t['monthlyBudget']),
    );
    final hasBudget = budget > 0;
    final ratio = hasBudget ? spent / budget : 0.0;
    final over = hasBudget && spent > budget;
    final pct = ratio * 100;
    final pctText = pct >= 10 || pct == 0
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
    final ringColor = over
        ? rx.negative
        : ratio >= 0.8
        ? rx.warning
        : (isDark ? rx.accent : rx.inverse);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Team spend this month', style: RxText.label(context)),
              const SizedBox(height: 10),
              if (!_spendLoaded)
                const RxSkeleton(width: 160, height: 44, radius: 12)
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _money(spent),
                    style: RxText.hero(context, size: 46),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                hasBudget
                    ? over
                          ? 'Over the ${_money(budget)} monthly budget'
                          : 'of ${_money(budget)} monthly budget'
                    : 'Set team budgets to track spend',
                maxLines: 2,
                style: RxText.caption(
                  context,
                  color: over ? rx.negative : null,
                ),
              ),
            ],
          ),
        ),
        if (hasBudget) ...[
          const SizedBox(width: 16),
          RxRing(
            key: ValueKey('team-ring-$_chartEpoch-$_spendLoaded'),
            size: 96,
            thickness: 9,
            value: ratio.clamp(0.0, 1.0),
            color: ringColor,
            trackColor: rx.textPrimary.withValues(alpha: 0.08),
            semanticLabel: '$pctText percent of team budget used',
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$pctText%',
                    style: RxText.value(
                      context,
                      size: 18,
                      color: over ? rx.negative : null,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text('used', style: RxText.micro(context)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsCard() {
    final rx = context.rx;
    final members = _membersByTeam.values.fold<int>(0, (a, l) => a + l.length);
    final payroll = _payrollByTeam.values.fold<double>(0, (a, b) => a + b);

    Widget half(String label, String value, String note) => Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: RxText.label(context)),
            const SizedBox(height: 8),
            if (!_membersLoaded)
              const RxSkeleton(width: 80, height: 24)
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: RxText.value(context, size: 20)),
              ),
            const SizedBox(height: 4),
            Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RxText.caption(context),
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
            half(
              'People',
              '$members',
              members == 1 ? 'member' : 'members across teams',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(width: 1, color: rx.hairline),
            ),
            half('Payroll', _money(payroll), 'per month'),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamsSection() {
    final teams = _visibleTeams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RxSectionHeader(title: 'All teams'),
        _buildSortChips(),
        const SizedBox(height: 12),
        if (teams.isEmpty)
          RxCard(
            child: RxEmptyState(
              icon: HugeIcons.strokeRoundedSearch01,
              title: 'No matches',
              message: 'No team is called "$_searchQuery"',
            ),
          )
        else
          for (var i = 0; i < teams.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RxReveal.index(
                i,
                key: ValueKey('team-card-${teams[i]['id']}'),
                child: _buildTeamCard(teams[i], i),
              ),
            ),
      ],
    );
  }

  Widget _buildSortChips() {
    Widget chip(String option, String label) {
      final rx = context.rx;
      final selected = _selectedSortOption == option;
      final ascending = _selectedOrder == "A-Z" || _selectedOrder == "Low-High";
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          button: true,
          selected: selected,
          label: selected
              ? 'Sort by $label, ${ascending ? 'ascending' : 'descending'}'
              : 'Sort by $label',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleOrder(option),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? rx.inverse : rx.surface,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: selected ? Colors.transparent : rx.hairline,
                ),
                boxShadow: selected ? null : rx.cardShadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: RxText.label(
                      context,
                      color: selected ? rx.onInverse : rx.textSecondary,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    HugeIcon(
                      icon: ascending
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: rx.onInverse,
                      size: 14,
                      strokeWidth: 2,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: [
          chip("Name", "Name"),
          chip("Monthly Amount", "Budget"),
          chip("Team Size", "Size"),
        ],
      ),
    );
  }

  Widget _buildTeamCard(Map<String, dynamic> team, int index) {
    final rx = context.rx;
    final teamId = team['id'] as String;
    final name = (team['teamName'] ?? 'Unnamed Team').toString();
    final color = _teamColor(team);
    final members = _membersByTeam[teamId] ?? const [];
    final spent = _spentByTeam[teamId] ?? 0.0;
    final budget = _num(team['monthlyBudget']);
    final hasBudget = budget > 0;
    final ratio = hasBudget ? spent / budget : 0.0;
    final over = hasBudget && spent > budget;
    final near = hasBudget && !over && ratio >= 0.8;

    final memberLabel = !_membersLoaded
        ? '…'
        : members.length == 1
        ? '1 member'
        : '${members.length} members';

    return RxCard(
      onTap: () => _openTeam(team),
      semanticLabel:
          '$name, $memberLabel, ${_money(spent)} spent this month${hasBudget ? ' of ${_money(budget)}' : ''}',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.16
                        : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(TeamStyle.icon(team), color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RxText.body(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (members.isNotEmpty) ...[
                          _buildAvatarRow(members.take(3).toList()),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            memberLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RxText.caption(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(spent),
                    style: RxText.amount(
                      context,
                      color: over ? rx.negative : rx.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Budget use as text, no bar: amber near the limit,
                  // red once over.
                  Text(
                    !hasBudget
                        ? 'this month'
                        : over
                        ? 'over ${_money(budget)}'
                        : '${(ratio * 100).round()}% of ${_money(budget)}',
                    style: RxText.micro(
                      context,
                      color: over
                          ? rx.negative
                          : near
                          ? rx.warning
                          : null,
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

  // --- AVATARS ---

  Widget _buildAvatarRow(List<Map<String, dynamic>> avatarInfos) {
    const size = 20.0;
    const step = 14.0;
    return SizedBox(
      height: size,
      width: (avatarInfos.length - 1) * step + size,
      child: Stack(
        children: [
          for (var i = 0; i < avatarInfos.length; i++)
            Positioned(
              left: i * step,
              child: _buildMemberAvatar(
                avatarInfos[i]['name'] as String,
                size,
                avatarInfos[i]['avatarUrl'] as String,
                avatarInfos[i]['telegramFileId'] as String?,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatar(
    String name,
    double size,
    String avatarUrl,
    String? telegramFileId,
  ) {
    final rx = context.rx;
    Widget image(String url) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: rx.surface, width: 1.5),
        image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
    );

    if (telegramFileId != null && telegramFileId.isNotEmpty) {
      return FutureBuilder<String>(
        future: TelegramService.getImageUrl(telegramFileId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: rx.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: rx.surface, width: 1.5),
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _buildFallbackAvatar(name, size);
          }
          return image(snapshot.data!);
        },
      );
    }
    if (avatarUrl.isNotEmpty &&
        avatarUrl.startsWith('http') &&
        !avatarUrl.contains('ui-avatars.com')) {
      return image(avatarUrl);
    }
    return _buildFallbackAvatar(name, size);
  }

  Widget _buildFallbackAvatar(String name, double size) {
    final rx = context.rx;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: RxCategory.soft(context, name),
        shape: BoxShape.circle,
        border: Border.all(color: rx.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontFamily: RxText.family,
          color: RxCategory.color(context, name),
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  // --- STATES ---

  Widget _buildEmptyTeams() {
    return RxCard(
      child: RxEmptyState(
        icon: HugeIcons.strokeRoundedUserGroup,
        title: 'No teams yet',
        message: 'Group people by function to track payroll and budgets',
        actionLabel: 'Create team',
        onAction: _openCreateTeam,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      ),
    );
  }

  Widget _buildError() {
    return RxCard(
      child: RxEmptyState(
        icon: HugeIcons.strokeRoundedAlert02,
        title: _error ?? "Couldn't load teams",
        message: 'Pull down to try again',
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RxSkeleton(width: 140, height: 13),
                  SizedBox(height: 12),
                  RxSkeleton(width: 170, height: 44, radius: 12),
                ],
              ),
            ),
            RxSkeleton(width: 96, height: 96, radius: 100),
          ],
        ),
        const SizedBox(height: 24),
        const RxSkeleton(height: 92, radius: 22),
        const SizedBox(height: 28),
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: RxSkeleton(height: 96, radius: 22),
          ),
      ],
    );
  }
}
