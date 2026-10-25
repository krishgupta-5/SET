import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import 'edit_team_screen.dart';
import 'add_member_screen.dart';
import 'member_detail_screen.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/telegram_service.dart';
import 'team_expense_history_screen.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';
import '../team_style.dart';

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
  String _userCountryCode = '+1';

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
      setState(() => _userCountryCode = currencyCode);
    }
  }

  String _money(double v) =>
      CurrencyFormatter.formatByCountryCompact(v, _userCountryCode);

  double _salaryOf(Map<String, dynamic> md) =>
      double.tryParse((md['salary'] ?? md['Salary'])?.toString() ?? '0') ?? 0.0;

  void _addMember() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddMemberScreen(teamId: widget.teamId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: rx.background,
        floatingActionButton: _buildAddMemberButton(),
        body: SafeArea(
          bottom: false,
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('teams')
                .doc(widget.teamId)
                .snapshots(),
            builder: (context, teamSnapshot) {
              final teamData =
                  teamSnapshot.hasData && teamSnapshot.data!.data() != null
                  ? teamSnapshot.data!.data() as Map<String, dynamic>
                  : widget.initialTeamData;

              final String teamName = teamData['teamName'] ?? "Team";
              final String description = teamData['description'] ?? "";
              final double teamBudget = (teamData['monthlyBudget'] ?? 0.0)
                  .toDouble();
              final Color teamColor = TeamStyle.color(
                context,
                teamData['color']?.toString(),
              );

              return Column(
                children: [
                  RxTopBar(
                    title: '',
                    trailing: RxCircleButton(
                      icon: HugeIcons.strokeRoundedPencilEdit02,
                      semanticLabel: 'Edit team',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditTeamScreen(
                            teamId: widget.teamId,
                            teamData: teamData,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (teamSnapshot.hasError)
                    const Expanded(
                      child: Center(
                        child: RxEmptyState(
                          icon: HugeIcons.strokeRoundedAlert02,
                          title: "Couldn't load this team",
                          message: 'Go back and try again',
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('members')
                            .where('teamId', isEqualTo: widget.teamId)
                            .snapshots(),
                        builder: (context, membersSnapshot) {
                          final loadingMembers =
                              membersSnapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !membersSnapshot.hasData;
                          final membersDocs = membersSnapshot.data?.docs ?? [];
                          final sortedMembers = membersDocs.toList()
                            ..sort((a, b) {
                              double cost(QueryDocumentSnapshot d) =>
                                  ((d.data()
                                              as Map<
                                                String,
                                                dynamic
                                              >)['monthlyCost']
                                          as num?)
                                      ?.toDouble() ??
                                  0.0;
                              return cost(b).compareTo(cost(a));
                            });

                          return ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              20,
                              8,
                              20,
                              MediaQuery.paddingOf(context).bottom + 110,
                            ),
                            children: [
                              RxReveal.index(
                                0,
                                child: _buildTitle(
                                  teamName,
                                  description,
                                  teamData,
                                  teamColor,
                                  loadingMembers ? null : membersDocs.length,
                                ),
                              ),
                              const SizedBox(height: 24),
                              RxReveal.index(
                                1,
                                child: _buildSpendStream(
                                  membersDocs,
                                  teamName,
                                  teamBudget,
                                  teamColor,
                                ),
                              ),
                              const SizedBox(height: 28),
                              RxReveal.index(
                                2,
                                child: RxSectionHeader(
                                  title: 'Members',
                                  actionLabel: sortedMembers.isEmpty
                                      ? null
                                      : 'Add',
                                  onAction: _addMember,
                                ),
                              ),
                              if (loadingMembers)
                                RxCard(
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < 3; i++)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              RxSkeleton(
                                                width: 40,
                                                height: 40,
                                                radius: 100,
                                              ),
                                              SizedBox(width: 12),
                                              Expanded(
                                                child: RxSkeleton(height: 14),
                                              ),
                                              SizedBox(width: 40),
                                              RxSkeleton(width: 60, height: 14),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              else
                                RxReveal.index(
                                  3,
                                  child: _buildMembersBlock(sortedMembers),
                                ),
                            ],
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

  Widget _buildAddMemberButton() {
    final rx = context.rx;
    return RxPressable(
      onTap: _addMember,
      semanticLabel: 'Add member',
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: rx.inverse,
          borderRadius: BorderRadius.circular(100),
          boxShadow: rx.raisedShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedUserAdd01,
              color: rx.onInverse,
              size: 19,
              strokeWidth: 2,
            ),
            const SizedBox(width: 8),
            Text(
              'Add member',
              style: RxText.body(
                context,
                color: rx.onInverse,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // --- TITLE ---

  Widget _buildTitle(
    String teamName,
    String description,
    Map<String, dynamic> teamData,
    Color teamColor,
    int? memberCount,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TeamIconTile(
          icon: TeamStyle.icon(teamData),
          colorName: teamData['color']?.toString(),
          size: 52,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memberCount == null
                    ? 'Team'
                    : memberCount == 1
                    ? '1 member'
                    : '$memberCount members',
                style: RxText.label(context),
              ),
              const SizedBox(height: 2),
              Text(
                teamName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: RxText.title(context),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(description, style: RxText.caption(context)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // --- SPEND ---
  // Same rule as before: this month's non-salary team expenses (recurring
  // expanded) plus active members' salaries.

  Widget _buildSpendStream(
    List<QueryDocumentSnapshot> membersDocs,
    String teamName,
    double budget,
    Color teamColor,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .where('TeamId', isEqualTo: widget.teamId)
          .snapshots(),
      builder: (context, expenseSnapshot) {
        if (!expenseSnapshot.hasData) {
          return const RxCard(
            padding: EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RxSkeleton(width: 110, height: 13),
                      SizedBox(height: 10),
                      RxSkeleton(width: 150, height: 32),
                    ],
                  ),
                ),
                RxSkeleton(width: 92, height: 92, radius: 100),
              ],
            ),
          );
        }

        double otherSpend = 0.0;
        double payroll = 0.0;
        final now = DateTime.now();
        final rawList = expenseSnapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {...data, 'id': doc.id};
        }).toList();
        final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        final expanded = ExpenseExpansionHelper.expandExpenses(
          rawList,
          maxDate: endOfMonth,
          allowFuture: true,
        );
        for (final data in expanded) {
          if (data['isFunding'] == true) continue;
          final category = (data['Category'] ?? '').toString().toLowerCase();
          if (category == 'salary') continue;
          final rawDate = data['Date'] ?? data['date'];
          DateTime? date;
          if (rawDate is Timestamp) {
            date = rawDate.toDate();
          } else if (rawDate is DateTime) {
            date = rawDate;
          }
          if (date != null &&
              date.month == now.month &&
              date.year == now.year) {
            otherSpend += (data['Amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
        for (final memberDoc in membersDocs) {
          final md = memberDoc.data() as Map<String, dynamic>;
          if ((md['status']?.toString() ?? 'Active') != 'Active') continue;
          payroll += _salaryOf(md);
        }

        return _buildBudgetBlock(
          payroll: payroll,
          other: otherSpend,
          budget: budget,
          teamName: teamName,
          teamColor: teamColor,
        );
      },
    );
  }

  Widget _buildBudgetBlock({
    required double payroll,
    required double other,
    required double budget,
    required String teamName,
    required Color teamColor,
  }) {
    final rx = context.rx;
    final total = payroll + other;
    final hasBudget = budget > 0;
    final ratio = hasBudget ? total / budget : 0.0;
    final over = hasBudget && total > budget;
    final near = hasBudget && !over && ratio >= 0.8;
    final pct = ratio * 100;
    final pctText = pct >= 10 || pct == 0
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);

    Widget split(String label, double value) => Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: RxText.label(context)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _money(value),
                style: RxText.value(context, size: 18),
              ),
            ),
          ],
        ),
      ),
    );

    return RxCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Spent this month',
                            style: RxText.label(context),
                          ),
                          if (over || near) ...[
                            const SizedBox(width: 8),
                            RxPill(
                              label: over ? 'Over budget' : 'Near limit',
                              dot: true,
                              foreground: over ? rx.negative : rx.warning,
                              background: over
                                  ? rx.negativeSoft
                                  : rx.warningSoft,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _money(total),
                          style: RxText.hero(
                            context,
                            size: 36,
                            color: over ? rx.negative : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hasBudget
                            ? '$pctText% of ${_money(budget)} monthly budget'
                            : 'No monthly budget set',
                        style: RxText.caption(
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
                ),
              ],
            ),
          ),
          const RxDivider(),
          IntrinsicHeight(
            child: Row(
              children: [
                split('Payroll', payroll),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Container(width: 1, color: rx.hairline),
                ),
                split('Other spend', other),
              ],
            ),
          ),
          const RxDivider(),
          RxPressable(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TeamExpenseHistoryScreen(
                  teamId: widget.teamId,
                  teamName: teamName,
                  monthlyBudget: budget,
                ),
              ),
            ),
            semanticLabel: 'View expense history',
            scale: 0.98,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 14, 15),
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedClock01,
                    color: rx.textSecondary,
                    size: 18,
                    strokeWidth: 1.8,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Expense history', style: RxText.body(context)),
                  ),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    color: rx.textTertiary,
                    size: 18,
                    strokeWidth: 1.8,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MEMBERS ---

  Widget _buildMembersBlock(List<QueryDocumentSnapshot> sortedMembers) {
    if (sortedMembers.isEmpty) {
      return RxCard(
        child: RxEmptyState(
          icon: HugeIcons.strokeRoundedUserGroup,
          title: 'No members yet',
          message: 'Add people to track their salary and spend',
          actionLabel: 'Add member',
          onAction: _addMember,
        ),
      );
    }

    final payrollTotal = sortedMembers.fold<double>(0, (a, d) {
      final md = d.data() as Map<String, dynamic>;
      return a + ((md['monthlyCost'] as num?)?.toDouble() ?? 0.0);
    });

    return RxCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < sortedMembers.length; i++) ...[
            if (i > 0) const RxDivider(indent: 54),
            _buildMemberRow(sortedMembers[i], payrollTotal),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberRow(QueryDocumentSnapshot doc, double payrollTotal) {
    final rx = context.rx;
    final member = doc.data() as Map<String, dynamic>;
    final memberId = doc.id;

    final String name = member['fullName'] ?? 'Unnamed Member';
    final String role = (member['jobTitle'] ?? '').toString();
    final double rawCost = (member['monthlyCost'] ?? 0.0).toDouble();
    final bool isPaused = (member['status'] ?? 'Active') == 'Paused';
    final share = payrollTotal > 0 ? (rawCost / payrollTotal * 100).round() : 0;

    final String? telegramFileId = member['telegramFileId'];
    final String? avatarUrl = member['avatarUrl'];
    final String? telegramFileIdFromAvatar =
        (avatarUrl != null &&
            avatarUrl.isNotEmpty &&
            !avatarUrl.startsWith('http') &&
            !avatarUrl.contains('ui-avatars.com'))
        ? avatarUrl
        : null;

    final subtitle = [
      if (role.isNotEmpty) role,
      if (isPaused) 'Paused' else if (payrollTotal > 0) '$share% of payroll',
    ].join(' · ');

    return RxPressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MemberDetailScreen(memberId: memberId),
        ),
      ),
      semanticLabel: '$name, $subtitle',
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: isPaused ? 0.5 : 1,
                  child: _buildMemberAvatar(
                    name,
                    40,
                    avatarUrl ?? "",
                    telegramFileId ?? telegramFileIdFromAvatar,
                  ),
                ),
                if (isPaused)
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: rx.warning,
                        shape: BoxShape.circle,
                        border: Border.all(color: rx.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
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
                      color: isPaused ? rx.textSecondary : rx.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RxText.caption(
                        context,
                        color: isPaused ? rx.warning : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _money(rawCost),
              style: RxText.amount(
                context,
                color: isPaused ? rx.textTertiary : rx.textPrimary,
              ),
            ),
            RxPressable(
              onTap: () => _showMemberOptions(memberId, name, isPaused),
              semanticLabel: 'Options for $name',
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedMoreVertical,
                    color: rx.textTertiary,
                    size: 18,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemberOptions(
    String memberId,
    String memberName,
    bool isCurrentlyPaused,
  ) {
    final ref = FirebaseFirestore.instance.collection('members').doc(memberId);
    showRxActionSheet(
      context,
      title: memberName,
      actions: [
        RxSheetAction(
          icon: isCurrentlyPaused
              ? HugeIcons.strokeRoundedPlayCircle
              : HugeIcons.strokeRoundedPauseCircle,
          label: isCurrentlyPaused ? 'Resume member' : 'Pause member',
          subtitle: isCurrentlyPaused
              ? 'Count their salary again'
              : 'Leave their salary out of team spend',
          onTap: () async {
            try {
              await ref.update({
                'status': isCurrentlyPaused ? 'Active' : 'Paused',
              });
            } catch (e) {
              debugPrint("Error updating status: $e");
            }
          },
        ),
        RxSheetAction(
          icon: HugeIcons.strokeRoundedUserRemove01,
          label: 'Remove from team',
          destructive: true,
          onTap: () async {
            try {
              await ref.delete();
            } catch (e) {
              debugPrint("Error deleting member: $e");
            }
          },
        ),
      ],
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
            return RxSkeleton(width: size, height: size, radius: 100);
          }
          return AvatarWidget(
            name: name,
            size: size,
            imageUrl: snapshot.hasData ? snapshot.data! : null,
            fontSize: size * 0.4,
          );
        },
      );
    }
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
