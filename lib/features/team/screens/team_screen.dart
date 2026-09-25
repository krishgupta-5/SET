import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:startup_expense_tracker/features/team/screens/create_team_screen.dart';
import 'team_detail_screen.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/telegram_service.dart';
import '../../../theme/app_theme.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with WidgetsBindingObserver {
  // 1. Search State
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isSearching = false;

  // 2. Filter State (Defaults)
  String _selectedSortOption = "Name";
  String _selectedOrder = "A-Z"; // Default order

  // Refresh state
  String _userCountryCode = '+1'; // Default to USD

  // Cache for the last sort future to prevent rebuilding on every stream tick
  Future<List<Map<String, dynamic>>>? _sortedTeamsFuture;
  List<Map<String, dynamic>>? _lastTeamsData;
  String _lastTeamsFingerprint = '';

  String _teamsFingerprint(List<Map<String, dynamic>> teams) => teams
      .map((t) => '${t['id']}:${t['teamName']}:${t['monthlyBudget']}')
      .join('|');

  void _rebuildSortFuture(List<Map<String, dynamic>> teams) {
    _lastTeamsData = teams;
    _lastTeamsFingerprint = _teamsFingerprint(teams);
    _sortedTeamsFuture = _filterAndSortTeams(teams);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadUserCountryCode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
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
      setState(() {
        _userCountryCode = currencyCode;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  void _refreshData() {
    setState(() {});
  }

  IconData _getIconFromData(Map<String, dynamic> data) {
    final dynamic cp = data['iconCodePoint'];
    if (cp != null) {
      final int codePoint = cp is int ? cp : int.tryParse(cp.toString()) ?? 0;
      switch (codePoint) {
        case 0xe3af:
          return Icons.work;
        case 0xe0af:
          return Icons.business;
        case 0xe7fd:
          return Icons.group;
        case 0xe226:
          return Icons.code;
        case 0xe86c:
          return Icons.design_services;
        case 0xe85d:
          return Icons.computer;
        case 0xe53b:
          return Icons.build;
        case 0xe251:
          return Icons.lightbulb;
        case 0xe7f1:
          return Icons.trending_up;
        case 0xe8b6:
          return Icons.people;
        default:
          return Icons.rocket_launch_rounded;
      }
    }
    return Icons.rocket_launch_rounded;
  }

  Color _getColorFromName(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'blue':
        return const Color(0xFF0A84FF);
      case 'orange':
        return const Color(0xFFFF9F0A);
      case 'purple':
        return const Color(0xFFA259FF);
      case 'green':
        return const Color(0xFF30D158);
      case 'red':
        return const Color(0xFFFF453A);
      default:
        return const Color(0xFF0A84FF);
    }
  }

  Stream<List<Map<String, dynamic>>> _getTeamsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('teams')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          List<Map<String, dynamic>> allTeams = [];
          for (var doc in snapshot.docs) {
            final data = doc.data();
            allTeams.add({...data, 'id': doc.id, 'source': 'teams_collection'});
          }
          return allTeams;
        });
  }

  Future<List<Map<String, dynamic>>> _filterAndSortTeams(
    List<Map<String, dynamic>> teams,
  ) async {
    List<Map<String, dynamic>> filteredTeams = List.from(teams);

    if (_searchQuery.isNotEmpty) {
      filteredTeams = filteredTeams.where((team) {
        final teamName = (team['teamName'] ?? '').toString().toLowerCase();
        return teamName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (_selectedSortOption == "Team Size") {
      final user = FirebaseAuth.instance.currentUser;
      final teamSizes = <String, int>{};

      if (user != null) {
        final allMembersSnap = await FirebaseFirestore.instance
            .collection('members')
            .where('uid', isEqualTo: user.uid)
            .get();
        for (final doc in allMembersSnap.docs) {
          final tId = doc.data()['teamId'] as String?;
          if (tId != null) teamSizes[tId] = (teamSizes[tId] ?? 0) + 1;
        }
      }

      filteredTeams.sort((a, b) {
        final sizeA = teamSizes[a['id'] as String] ?? 0;
        final sizeB = teamSizes[b['id'] as String] ?? 0;
        return _selectedOrder == "Low-High"
            ? sizeA.compareTo(sizeB)
            : sizeB.compareTo(sizeA);
      });
    } else {
      filteredTeams.sort((a, b) {
        switch (_selectedSortOption) {
          case "Name":
            final nameA = (a['teamName'] ?? '').toString().toLowerCase();
            final nameB = (b['teamName'] ?? '').toString().toLowerCase();
            return _selectedOrder == "A-Z"
                ? nameA.compareTo(nameB)
                : nameB.compareTo(nameA);
          case "Monthly Amount":
            final costA = (a['monthlyBudget'] ?? 0).toDouble();
            final costB = (b['monthlyBudget'] ?? 0).toDouble();
            return _selectedOrder == "Low-High"
                ? costA.compareTo(costB)
                : costB.compareTo(costA);
          default:
            return 0;
        }
      });
    }

    return filteredTeams;
  }

  void _toggleOrder(String option) {
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
        if (option == "Name") {
          _selectedOrder = "A-Z";
        } else {
          _selectedOrder = "High-Low";
        }
      }
      if (_lastTeamsData != null) {
        _sortedTeamsFuture = _filterAndSortTeams(_lastTeamsData!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: context.appBackground,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              _refreshData();
            },
            color: context.textPrimary,
            backgroundColor: context.cardBackground,
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
                      const SizedBox(
                        height: 16,
                      ), // Replaced header with some top padding

                      _buildHeroSection(isDark),

                      // Fluid Animated Search Reveal
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        child: _isSearching
                            ? Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: _buildSearchBar(isDark),
                              )
                            : const SizedBox(width: double.infinity, height: 0),
                      ),
                      const SizedBox(height: 24),

                      _buildCreateTeamButton(isDark),
                      const SizedBox(height: 32),

                      if (!_isSearching) _buildFilterChips(isDark),
                      if (!_isSearching) const SizedBox(height: 24),

                      _buildFirebaseTeamsStream(isDark),
                      const SizedBox(height: 100),
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

  // Removed _buildHeader

  Widget _buildHeroSection(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          "Teams",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
          ),
        ),
        GestureDetector(
          onTap: () => setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) {
              _searchQuery = "";
              _searchController.clear();
              if (_lastTeamsData != null) {
                _sortedTeamsFuture = _filterAndSortTeams(_lastTeamsData!);
              }
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: _isSearching
                  ? context.textPrimary
                  : context.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isSearching ? Colors.transparent : context.borderColor,
              ),
              boxShadow: (isDark || _isSearching)
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _isSearching ? Icons.close_rounded : Icons.search_rounded,
                key: ValueKey(_isSearching),
                color: _isSearching
                    ? context.appBackground
                    : context.textPrimary,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // UPDATED PREMIUM SEARCH BAR
  Widget _buildSearchBar(bool isDark) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: context.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: context.textPrimary,
              decoration: InputDecoration(
                hintText: "Search team name...",
                hintStyle: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textTertiary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  if (_lastTeamsData != null) {
                    _sortedTeamsFuture = _filterAndSortTeams(_lastTeamsData!);
                  }
                });
              },
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                setState(() {
                  _searchQuery = "";
                  _searchController.clear();
                  if (_lastTeamsData != null) {
                    _sortedTeamsFuture = _filterAndSortTeams(_lastTeamsData!);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: context.textSecondary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  color: context.textPrimary,
                  size: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCreateTeamButton(bool isDark) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CreateTeamScreen()),
        ).then((_) => _refreshData());
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: context.textPrimary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: context.textPrimary.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: context.appBackground, size: 20),
            const SizedBox(width: 8),
            Text(
              "Create New Team",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.appBackground,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _buildFilterChip(
            label: "Name",
            icon: Icons.sort_by_alpha,
            isSelected: _selectedSortOption == "Name",
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: "Monthly Amount",
            icon: Icons.attach_money,
            isSelected: _selectedSortOption == "Monthly Amount",
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: "Team Size",
            icon: Icons.group_outlined,
            isSelected: _selectedSortOption == "Team Size",
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    IconData arrowIcon = Icons.arrow_downward;
    if (isSelected) {
      arrowIcon =
          (label == "Name"
              ? _selectedOrder == "A-Z"
              : _selectedOrder == "High-Low")
          ? Icons.arrow_downward
          : Icons.arrow_upward;
    }

    return GestureDetector(
      onTap: () => _toggleOrder(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? context.textPrimary : context.borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? context.appBackground : context.textSecondary,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: isSelected
                    ? context.appBackground
                    : context.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(arrowIcon, color: context.appBackground, size: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFirebaseTeamsStream(bool isDark) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _buildEmptyState("Please log in.");

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getTeamsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.textSecondary,
              ),
            ),
          );
        }

        if (snapshot.hasError) return _buildEmptyState("Error loading teams.");
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState("You don't have any teams yet.");
        }

        final newTeams = snapshot.data!;
        final newFingerprint = _teamsFingerprint(newTeams);
        if (_sortedTeamsFuture == null ||
            _lastTeamsFingerprint != newFingerprint) {
          _rebuildSortFuture(newTeams);
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _sortedTeamsFuture,
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.textSecondary,
                  ),
                ),
              );
            }
            if (futureSnapshot.hasError) {
              return _buildEmptyState("Error sorting teams.");
            }

            final teams = futureSnapshot.data ?? [];
            if (teams.isEmpty) {
              return _buildEmptyState("No teams match your search.");
            }

            return Column(
              children: teams
                  .map(
                    (teamData) =>
                        _buildCompactTeamCard(context, teamData, isDark),
                  )
                  .toList(),
            );
          },
        );
      },
    );
  }

  Widget _buildCompactTeamCard(
    BuildContext context,
    Map<String, dynamic> teamData,
    bool isDark,
  ) {
    final String name = teamData['teamName'] ?? 'Unnamed Team';
    final Color color = _getColorFromName(teamData['color'] ?? 'blue');
    final String teamId = teamData['id'] as String;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                TeamDetailScreen(teamId: teamId, initialTeamData: teamData),
          ),
        ).then((_) => _refreshData());
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderColor),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('members')
              .where('teamId', isEqualTo: teamId)
              .snapshots(),
          builder: (context, membersSnapshot) {
            final membersDocs = membersSnapshot.data?.docs ?? [];
            final int memberCount = membersDocs.length;
            final String memberCountStr =
                membersSnapshot.connectionState == ConnectionState.waiting
                ? '...'
                : (memberCount == 1 ? '1 Member' : '$memberCount Members');

            final List<Map<String, dynamic>> avatarInfos = membersDocs
                .take(3)
                .map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String? tgId = data['telegramFileId'] as String?;
                  final String? url = data['avatarUrl'] as String?;
                  final String? legacyTgId =
                      (url != null &&
                          url.isNotEmpty &&
                          !url.startsWith('http') &&
                          !url.contains('ui-avatars.com'))
                      ? url
                      : null;
                  return <String, dynamic>{
                    'name': data['fullName'] ?? 'Unnamed',
                    'avatarUrl': url ?? '',
                    'telegramFileId': (tgId != null && tgId.isNotEmpty)
                        ? tgId
                        : legacyTgId,
                    'memberId': doc.id,
                  };
                })
                .toList();

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('expenses')
                  .where('TeamId', isEqualTo: teamId)
                  .snapshots(),
              builder: (context, expenseSnap) {
                double actualSpent = 0.0;
                if (expenseSnap.hasData) {
                  final now = DateTime.now();
                  for (var doc in expenseSnap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final date = (data['Date'] as Timestamp?)?.toDate();
                    if (date != null &&
                        date.month == now.month &&
                        date.year == now.year) {
                      actualSpent +=
                          (data['Amount'] as num?)?.toDouble() ?? 0.0;
                    }
                  }
                }

                final budget = (teamData['monthlyBudget'] ?? 0).toDouble();
                final isOverBudget = actualSpent > budget && budget > 0;
                final spentStr = CurrencyFormatter.formatByCountryCompact(
                  actualSpent,
                  _userCountryCode,
                );
                final budgetStr = CurrencyFormatter.formatByCountryCompact(
                  budget,
                  _userCountryCode,
                );

                double progress = budget > 0 ? (actualSpent / budget) : 0.0;
                if (progress > 1.0) progress = 1.0;

                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getIconFromData(teamData),
                            color: color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    memberCountStr,
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: context.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (avatarInfos.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    _buildAvatarRow(avatarInfos),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              spentStr,
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: isOverBudget
                                    ? const Color(0xFFFF453A)
                                    : context.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (budget > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                "Budget: $budgetStr",
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildAvatarRow(List<Map<String, dynamic>> avatarInfos) {
    return SizedBox(
      height: 16,
      width: (avatarInfos.length * 12.0) + 4.0,
      child: Stack(
        children: List.generate(avatarInfos.length, (index) {
          final info = avatarInfos[index];
          return Positioned(
            left: index * 12.0,
            child: _buildMemberAvatarWithTelegram(
              info['name'] as String,
              16,
              info['avatarUrl'] as String,
              info['telegramFileId'] as String?,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMemberAvatarWithTelegram(
    String name,
    double size,
    String avatarUrl,
    String? telegramFileId,
  ) {
    if (telegramFileId != null && telegramFileId.isNotEmpty) {
      return FutureBuilder<String>(
        future: TelegramService.getImageUrl(telegramFileId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: context.cardSecondaryBackground,
                shape: BoxShape.circle,
                border: Border.all(color: context.cardBackground, width: 1.5),
              ),
            );
          } else if (snapshot.hasError || !snapshot.hasData) {
            return _buildFallbackAvatar(name, size);
          } else {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.cardBackground, width: 1.5),
                image: DecorationImage(
                  image: NetworkImage(snapshot.data!),
                  fit: BoxFit.cover,
                ),
              ),
            );
          }
        },
      );
    } else if (avatarUrl.isNotEmpty && !avatarUrl.contains('ui-avatars.com')) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.cardBackground, width: 1.5),
          image: DecorationImage(
            image: NetworkImage(avatarUrl),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      return _buildFallbackAvatar(name, size);
    }
  }

  Widget _buildFallbackAvatar(String name, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.textTertiary,
        shape: BoxShape.circle,
        border: Border.all(color: context.cardBackground, width: 1.5),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.appBackground,
            fontSize: size * 0.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
