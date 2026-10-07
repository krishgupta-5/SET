import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'edit_team_screen.dart';
import 'add_member_screen.dart';
import 'member_detail_screen.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/telegram_service.dart';
import 'team_expense_history_screen.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../theme/app_theme.dart';

class TeamDetailScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic> initialTeamData;

  const TeamDetailScreen({
    super.key,
    required this.teamId,
    required this.initialTeamData,
  });

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  String _userCountryCode = '+1'; // Default to USD

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadUserCountryCode();
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bgColor,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddMemberScreen(teamId: widget.teamId),
              ),
            );
          },
          backgroundColor: context.textPrimary,
          foregroundColor: context.appBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(Icons.add, size: 20),
          label: const Text(
            "Add Member",
            style: TextStyle(
              fontFamily: 'Satoshi',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('teams')
                .doc(widget.teamId)
                .snapshots(),
            builder: (context, teamSnapshot) {
              if (teamSnapshot.hasError) {
                return Center(
                  child: Text(
                    "Error loading team",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                    ),
                  ),
                );
              }

              final teamData =
                  teamSnapshot.hasData && teamSnapshot.data!.data() != null
                  ? teamSnapshot.data!.data() as Map<String, dynamic>
                  : widget.initialTeamData;

              final String teamName = teamData['teamName'] ?? "Team";
              final String description = teamData['description'] ?? "";
              final double teamBudget = (teamData['monthlyBudget'] ?? 0.0)
                  .toDouble();
              final Color teamColor = _getColorFromName(
                teamData['color'] ?? 'blue',
              );

              return Column(
                children: [
                  _buildHeader(
                    context,
                    teamName,
                    teamData,
                    cardColor,
                    borderColor,
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('members')
                          .where('teamId', isEqualTo: widget.teamId)
                          .snapshots(),
                      builder: (context, membersSnapshot) {
                        if (membersSnapshot.connectionState ==
                                ConnectionState.waiting &&
                            !membersSnapshot.hasData) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: context.textSecondary,
                              strokeWidth: 2,
                            ),
                          );
                        }

                        final membersDocs = membersSnapshot.data?.docs ?? [];
                        final String memberCount =
                            "${membersDocs.length} Members";

                        final sortedMembers = membersDocs.toList();
                        sortedMembers.sort((a, b) {
                          final costA =
                              ((a.data() as Map<String, dynamic>)['monthlyCost']
                                      as num?)
                                  ?.toDouble() ??
                              0.0;
                          final costB =
                              ((b.data() as Map<String, dynamic>)['monthlyCost']
                                      as num?)
                                  ?.toDouble() ??
                              0.0;
                          return costB.compareTo(costA);
                        });

                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),

                              // Clean Title & Description
                              Text(
                                teamName,
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textPrimary,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1.0,
                                ),
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  description,
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: context.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 32),

                              // Budget Block
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('expenses')
                                    .where(
                                      'uid',
                                      isEqualTo: FirebaseAuth
                                          .instance
                                          .currentUser
                                          ?.uid,
                                    )
                                    .where('TeamId', isEqualTo: widget.teamId)
                                    .snapshots(),
                                builder: (context, expenseSnapshot) {
                                  double totalSpentThisMonth = 0.0;
                                  if (expenseSnapshot.hasData) {
                                    final now = DateTime.now();
                                    final rawList = expenseSnapshot.data!.docs
                                        .map((doc) {
                                          final data =
                                              doc.data()
                                                  as Map<String, dynamic>;
                                          return {...data, 'id': doc.id};
                                        })
                                        .toList();

                                    final endOfMonth = DateTime(
                                      now.year,
                                      now.month + 1,
                                      0,
                                      23,
                                      59,
                                      59,
                                    );
                                    final expanded =
                                        ExpenseExpansionHelper.expandExpenses(
                                          rawList,
                                          maxDate: endOfMonth,
                                          allowFuture: true,
                                        );

                                    for (final data in expanded) {
                                      if (data['isFunding'] == true) continue;
                                      final category = (data['Category'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                      if (category == 'salary') continue;

                                      final rawDate =
                                          data['Date'] ?? data['date'];
                                      DateTime? date;
                                      if (rawDate is Timestamp) {
                                        date = rawDate.toDate();
                                      } else if (rawDate is DateTime) {
                                        date = rawDate;
                                      }
                                      if (date != null &&
                                          date.month == now.month &&
                                          date.year == now.year) {
                                        totalSpentThisMonth +=
                                            (data['Amount'] as num?)
                                                ?.toDouble() ??
                                            0.0;
                                      }
                                    }

                                    for (var memberDoc in membersDocs) {
                                      final md =
                                          memberDoc.data()
                                              as Map<String, dynamic>;
                                      final status =
                                          md['status']?.toString() ?? 'Active';
                                      if (status != 'Active') continue;
                                      final salary =
                                          double.tryParse(
                                            (md['salary'] ?? md['Salary'])
                                                    ?.toString() ??
                                                '0',
                                          ) ??
                                          0.0;
                                      totalSpentThisMonth += salary;
                                    }
                                  }
                                  return _buildBudgetBlock(
                                    totalSpentThisMonth,
                                    teamBudget,
                                    teamName,
                                    teamColor,
                                    cardColor,
                                    borderColor,
                                  );
                                },
                              ),

                              const SizedBox(height: 32),

                              // Members Block
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "MEMBERS",
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: context.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    memberCount.toUpperCase(),
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: context.textTertiary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              _buildMembersBlock(
                                sortedMembers,
                                cardColor,
                                borderColor,
                              ),

                              const SizedBox(height: 100),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildHeader(
    BuildContext context,
    String teamName,
    Map<String, dynamic> teamData,
    Color cardColor,
    Color borderColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_back,
                    color: context.textSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Back",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      EditTeamScreen(teamId: widget.teamId, teamData: teamData),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.textPrimary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                "Edit Team",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.appBackground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetBlock(
    double totalCost,
    double budget,
    String teamName,
    Color teamColor,
    Color cardColor,
    Color borderColor,
  ) {
    final bool isOverBudget = totalCost > budget && budget > 0;
    final Color progressColor = isOverBudget
        ? const Color(0xFFFF453A)
        : teamColor;

    double progress = budget > 0 ? (totalCost / budget) : 0.0;
    if (progress > 1.0) progress = 1.0;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "MONTHLY SPEND",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    if (isOverBudget)
                      Text(
                        "OVER BUDGET",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: const Color(0xFFFF453A),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.formatByCountryCompact(
                        totalCost,
                        _userCountryCode,
                      ),
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.0,
                        height: 1.1,
                      ),
                    ),
                    if (budget > 0) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          "of ${CurrencyFormatter.formatByCountryCompact(budget, _userCountryCode)}",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (budget > 0) ...[
                  const SizedBox(height: 20),
                  Stack(
                    children: [
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: context.textSecondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: progress > 0 ? progress : 0.02,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: progressColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TeamExpenseHistoryScreen(
                    teamId: widget.teamId,
                    teamName: teamName,
                    monthlyBudget: budget,
                  ),
                ),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "View Expense History",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersBlock(
    List<QueryDocumentSnapshot> sortedMembers,
    Color cardColor,
    Color borderColor,
  ) {
    if (sortedMembers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Text(
            "No members assigned to this team.",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: sortedMembers.asMap().entries.map((entry) {
          final isLast = entry.key == sortedMembers.length - 1;
          return Column(
            children: [
              _buildCleanMemberRow(entry.value),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.only(left: 72), // Indented divider
                  child: Divider(height: 1, color: borderColor),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCleanMemberRow(QueryDocumentSnapshot doc) {
    final member = doc.data() as Map<String, dynamic>;
    final memberId = doc.id;

    final String name = member['fullName'] ?? 'Unnamed Member';
    final String role = member['jobTitle'] ?? 'No Role';
    final double rawCost = (member['monthlyCost'] ?? 0.0).toDouble();
    final String salary = CurrencyFormatter.formatByCountryCompact(
      rawCost,
      _userCountryCode,
    );

    final String status = member['status'] ?? 'Active';
    final bool isPaused = status == 'Paused';

    final String? telegramFileId = member['telegramFileId'];
    final String? avatarUrl = member['avatarUrl'];
    final String? telegramFileIdFromAvatar =
        (avatarUrl != null &&
            avatarUrl.isNotEmpty &&
            !avatarUrl.startsWith('http') &&
            !avatarUrl.contains('ui-avatars.com'))
        ? avatarUrl
        : null;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MemberDetailScreen(memberId: memberId),
          ),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Stack(
              children: [
                _buildMemberAvatar(
                  name,
                  40,
                  avatarUrl ?? "",
                  telegramFileId ?? telegramFileIdFromAvatar,
                ),
                if (isPaused)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9F0A),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.cardBackground,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: isPaused
                          ? context.textSecondary
                          : context.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decoration: isPaused ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    role,
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Text(
                  salary,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: isPaused
                        ? context.textTertiary
                        : context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () =>
                      _showMemberOptions(context, memberId, name, isPaused),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    color: context.textTertiary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMemberOptions(
    BuildContext context,
    String memberId,
    String memberName,
    bool isCurrentlyPaused,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "MANAGE $memberName".toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                _buildActionOption(
                  isCurrentlyPaused
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  isCurrentlyPaused ? "Resume Member" : "Pause Member",
                  () async {
                    Navigator.pop(bottomSheetContext);
                    try {
                      await FirebaseFirestore.instance
                          .collection('members')
                          .doc(memberId)
                          .update({
                            'status': isCurrentlyPaused ? 'Active' : 'Paused',
                          });
                    } catch (e) {
                      debugPrint("Error updating status: $e");
                    }
                  },
                ),
                const SizedBox(height: 8),
                _buildActionOption(
                  Icons.person_remove_outlined,
                  "Remove from Team",
                  () async {
                    Navigator.pop(bottomSheetContext);
                    try {
                      await FirebaseFirestore.instance
                          .collection('members')
                          .doc(memberId)
                          .delete();
                    } catch (e) {
                      debugPrint("Error deleting member: $e");
                    }
                  },
                  isDestructive: true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionOption(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        color: Colors.transparent,
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive
                  ? const Color(0xFFFF453A)
                  : context.textPrimary,
              size: 22,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: isDestructive
                    ? const Color(0xFFFF453A)
                    : context.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberAvatar(
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
              ),
              child: Center(
                child: SizedBox(
                  width: size * 0.3,
                  height: size * 0.3,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.iconSecondary,
                  ),
                ),
              ),
            );
          } else if (snapshot.hasError || !snapshot.hasData) {
            return AvatarWidget(
              name: name,
              size: size,
              imageUrl: null,
              fontSize: size * 0.4,
            );
          } else {
            return AvatarWidget(
              name: name,
              size: size,
              imageUrl: snapshot.data!,
              fontSize: size * 0.4,
            );
          }
        },
      );
    } else {
      return AvatarWidget(
        name: name,
        size: size,
        imageUrl: avatarUrl.isNotEmpty && !avatarUrl.contains('ui-avatars.com')
            ? avatarUrl
            : null,
        fontSize: size * 0.4,
      );
    }
  }
}
