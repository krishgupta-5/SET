import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'edit_member_screen.dart';
import 'adjust_salary_screen.dart';
import 'payment_history_screen.dart';
import 'salary_history_screen.dart';
import 'process_payment_screen.dart';
import 'transaction_details_screen.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/team_member_service.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';
import '../team_widgets.dart';

class MemberDetailScreen extends StatefulWidget {
  final String memberId;

  const MemberDetailScreen({super.key, required this.memberId});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
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

  /// "Aug 12, 2023". Used for display and passed on to detail screens.
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "Unknown";
    final dt = timestamp.toDate();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return "${months[dt.month - 1]} ${dt.day}, ${dt.year}";
  }

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('members')
                .doc(widget.memberId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Column(
                  children: [
                    RxTopBar(title: ''),
                    Expanded(child: Center(child: CircularProgressIndicator())),
                  ],
                );
              }
              if (snapshot.hasError ||
                  !snapshot.hasData ||
                  !snapshot.data!.exists) {
                return const Column(
                  children: [
                    RxTopBar(title: ''),
                    Expanded(
                      child: Center(
                        child: RxEmptyState(
                          icon: HugeIcons.strokeRoundedUserRemove01,
                          title: 'Member not found',
                          message: 'They may have been removed',
                        ),
                      ),
                    ),
                  ],
                );
              }

              final memberData = snapshot.data!.data() as Map<String, dynamic>;
              final String name = memberData['fullName'] ?? "Unnamed Member";
              final String role = (memberData['jobTitle'] ?? '').toString();
              final String email = (memberData['email'] ?? '').toString();
              final String status = memberData['status'] ?? "Active";
              final double cost = (memberData['monthlyCost'] ?? 0.0).toDouble();
              final Timestamp? joinedTs =
                  memberData['joiningDate'] as Timestamp?;
              final DateTime joinedDate = joinedTs?.toDate() ?? DateTime.now();
              final String teamId = memberData['teamId'] ?? "";

              return Column(
                children: [
                  RxTopBar(
                    title: '',
                    trailing: RxCircleButton(
                      icon: HugeIcons.strokeRoundedMoreHorizontal,
                      semanticLabel: 'Member actions',
                      onTap: () => _showMemberActionSheet(
                        name,
                        status,
                        cost,
                        memberData,
                      ),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('teams')
                          .doc(teamId.isEmpty ? '_' : teamId)
                          .get(),
                      builder: (context, teamSnapshot) {
                        String teamName = '';
                        if (teamSnapshot.hasData && teamSnapshot.data!.exists) {
                          teamName =
                              ((teamSnapshot.data!.data()
                                          as Map<
                                            String,
                                            dynamic
                                          >)['teamName'] ??
                                      'Unknown team')
                                  .toString();
                        }

                        return ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            20,
                            8,
                            20,
                            MediaQuery.paddingOf(context).bottom + 32,
                          ),
                          children: [
                            RxReveal.index(
                              0,
                              child: _buildProfile(
                                memberData,
                                name,
                                role,
                                teamName,
                                status,
                              ),
                            ),
                            const SizedBox(height: 24),
                            RxReveal.index(
                              1,
                              child: _buildPayCard(
                                cost,
                                joinedDate,
                                status,
                                name,
                                teamId,
                                teamName,
                              ),
                            ),
                            const SizedBox(height: 28),
                            RxReveal.index(
                              2,
                              child: Column(
                                children: [
                                  const RxSectionHeader(title: 'Details'),
                                  RxCard(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: Column(
                                      children: [
                                        if (email.isNotEmpty) ...[
                                          RxDetailRow(
                                            label: 'Email',
                                            value: email,
                                          ),
                                          const RxDivider(),
                                        ],
                                        RxDetailRow(
                                          label: 'Joined',
                                          value: _formatDate(joinedTs),
                                        ),
                                        const RxDivider(),
                                        RxDetailRow(
                                          label: 'Type',
                                          value: employmentLabel(
                                            memberData['employmentType']
                                                as String?,
                                          ),
                                        ),
                                        if (teamName.isNotEmpty) ...[
                                          const RxDivider(),
                                          RxDetailRow(
                                            label: 'Team',
                                            value: teamName,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                            RxReveal.index(
                              3,
                              child: _buildPaymentHistory(
                                joinedDate,
                                name,
                                cost,
                              ),
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

  // --- PROFILE ---

  Widget _buildProfile(
    Map<String, dynamic> memberData,
    String name,
    String role,
    String teamName,
    String status,
  ) {
    final rx = context.rx;
    final isActive = status == 'Active';
    final subtitle = [
      if (role.isNotEmpty) role,
      if (teamName.isNotEmpty) teamName,
    ].join(' · ');

    return Column(
      children: [
        Opacity(
          opacity: isActive ? 1 : 0.6,
          child: MemberAvatar.fromData(memberData, size: 88),
        ),
        const SizedBox(height: 14),
        Text(
          name,
          textAlign: TextAlign.center,
          style: RxText.title(context).copyWith(fontSize: 24),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: RxText.label(context),
          ),
        ],
        const SizedBox(height: 10),
        RxPill(
          label: status,
          dot: true,
          foreground: isActive ? rx.positive : rx.warning,
          background: isActive ? rx.positiveSoft : rx.warningSoft,
        ),
      ],
    );
  }

  // --- SALARY + PAY ---
  // Logic unchanged: count paid occurrences (recurring expanded) to find
  // the next due date; before it, paying is an advance.

  Widget _buildPayCard(
    double cost,
    DateTime joinedDate,
    String status,
    String memberName,
    String teamId,
    String teamName,
  ) {
    final rx = context.rx;
    final isPaused = status == "Paused";

    Widget card({required Widget footer}) => RxCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly salary', style: RxText.label(context)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(cost),
              style: RxText.hero(
                context,
                size: 36,
                color: isPaused ? rx.textTertiary : null,
              ),
            ),
          ),
          const SizedBox(height: 14),
          footer,
        ],
      ),
    );

    if (isPaused) {
      return card(
        footer: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedPauseCircle,
              color: rx.warning,
              size: 16,
              strokeWidth: 2,
            ),
            const SizedBox(width: 6),
            Text(
              'Payroll paused',
              style: RxText.caption(context, color: rx.warning),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return card(footer: const RxSkeleton(height: 52, radius: 16));
        }

        int totalPaymentsMade = 0;
        if (snapshot.hasData) {
          final salaryDocs = snapshot.data!.docs
              .map(
                (doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id},
              )
              .where(
                (data) =>
                    (data['Category']?.toString().toLowerCase() ?? '') ==
                        'salary' &&
                    data['memberId'] == widget.memberId,
              )
              .toList();
          totalPaymentsMade = ExpenseExpansionHelper.expandExpenses(
            salaryDocs,
            maxDate: DateTime.now(),
          ).length;
        }

        DateTime addMonths(DateTime date, int months) {
          final y = date.year + (date.month + months - 1) ~/ 12;
          final m = (date.month + months - 1) % 12 + 1;
          final maxDay = DateTime(y, m + 1, 0).day;
          return DateTime(y, m, date.day > maxDay ? maxDay : date.day);
        }

        final nextDueDate = addMonths(joinedDate, totalPaymentsMade + 1);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final isAdvance = today.isBefore(nextDueDate);
        final advanceLocked = isAdvance && totalPaymentsMade == 0;
        final due = rxFormatDate(nextDueDate);

        final dueLine = Row(
          children: [
            HugeIcon(
              icon: isAdvance
                  ? HugeIcons.strokeRoundedCalendar03
                  : HugeIcons.strokeRoundedAlert02,
              color: isAdvance ? rx.textSecondary : rx.warning,
              size: 15,
              strokeWidth: 1.9,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isAdvance ? 'Next due $due' : 'Due $due',
                style: RxText.caption(
                  context,
                  color: isAdvance ? null : rx.warning,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        );

        return card(
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dueLine,
              const SizedBox(height: 14),
              if (advanceLocked)
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: rx.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedSquareLock02,
                        color: rx.textSecondary,
                        size: 16,
                        strokeWidth: 1.9,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Advance available after the first payout',
                        style: RxText.caption(context),
                      ),
                    ],
                  ),
                )
              else
                RxButton(
                  label: isAdvance ? 'Pay in advance' : 'Pay salary',
                  icon: HugeIcons.strokeRoundedMoneySend01,
                  style: isAdvance
                      ? RxButtonStyle.secondary
                      : RxButtonStyle.primary,
                  onTap: () => _push(
                    ProcessPaymentScreen(
                      memberId: widget.memberId,
                      memberName: memberName,
                      teamId: teamId,
                      teamName: teamName,
                      defaultAmount: cost,
                      isAdvance: isAdvance,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // --- PAYMENTS (latest 3) ---

  Widget _buildPaymentHistory(DateTime joinedDate, String name, double cost) {
    final rx = context.rx;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .where('memberId', isEqualTo: widget.memberId)
          .where('Category', isEqualTo: 'salary')
          .snapshots(),
      builder: (context, snapshot) {
        final header = RxSectionHeader(
          title: 'Payments',
          actionLabel: 'View all',
          onAction: () => _push(
            PaymentHistoryScreen(
              joiningDate: joinedDate,
              salary: cost,
              memberName: name,
              memberId: widget.memberId,
            ),
          ),
        );

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [header, const RxSkeleton(height: 140, radius: 22)],
          );
        }
        if (snapshot.hasError) {
          return Column(
            children: [
              header,
              const RxCard(
                child: RxEmptyState(
                  icon: HugeIcons.strokeRoundedAlert02,
                  title: "Couldn't load payments",
                ),
              ),
            ],
          );
        }

        final rawList = (snapshot.data?.docs ?? []).map((doc) {
          return {...doc.data() as Map<String, dynamic>, 'id': doc.id};
        }).toList();
        final expanded = ExpenseExpansionHelper.expandExpenses(
          rawList,
          maxDate: DateTime.now(),
        );

        final payments =
            <Map<String, dynamic>>[
              for (final data in expanded)
                () {
                  final rawDate = data['Date'] ?? data['date'];
                  final ts = rawDate is Timestamp ? rawDate : null;
                  final amt = (data['Amount'] as num?)?.toDouble() ?? 0.0;
                  final title = data['Title']?.toString() ?? '';
                  return {
                    "id": data['id'] ?? data['expenseId'] ?? '',
                    "rawData": data,
                    "rawDate": ts,
                    "date": _formatDate(ts),
                    "amt": _money(amt),
                    "title": title.contains("Advance")
                        ? "Advance Payout"
                        : "Salary Payout",
                  };
                }(),
            ]..sort((a, b) {
              final da = a["rawDate"] as Timestamp?;
              final db = b["rawDate"] as Timestamp?;
              if (da == null || db == null) return 0;
              return db.compareTo(da);
            });

        // No payouts yet: the pay card already says what to do next.
        if (payments.isEmpty) return const SizedBox.shrink();

        final preview = payments.take(3).toList();
        return Column(
          children: [
            header,
            RxCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < preview.length; i++) ...[
                    if (i > 0) const RxDivider(indent: 52),
                    _paymentRow(preview[i], rx),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _paymentRow(Map<String, dynamic> p, RxColors rx) {
    final isAdvance = p['title'] == "Advance Payout";
    return RxPressable(
      onTap: () => _push(
        TransactionDetailsScreen(
          transactionId: p['id'],
          transactionData: p['rawData'],
          formattedDate: p['date'],
          formattedAmount: p['amt'],
          displayTitle: p['title'],
        ),
      ),
      scale: 0.98,
      semanticLabel: '${p['title']}, ${p['date']}, ${p['amt']}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            RxIconTile(
              icon: isAdvance
                  ? HugeIcons.strokeRoundedFastWind
                  : HugeIcons.strokeRoundedMoneySend01,
              size: 40,
              iconSize: 19,
              background: isAdvance ? rx.warningSoft : rx.positiveSoft,
              foreground: isAdvance ? rx.warning : rx.positive,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAdvance ? 'Advance' : 'Salary',
                    style: RxText.body(context),
                  ),
                  const SizedBox(height: 2),
                  Text(p['date'] as String, style: RxText.caption(context)),
                ],
              ),
            ),
            Text(p['amt'] as String, style: RxText.amount(context)),
          ],
        ),
      ),
    );
  }

  // --- ACTIONS ---

  void _showMemberActionSheet(
    String memberName,
    String currentStatus,
    double currentSalary,
    Map<String, dynamic> memberData,
  ) {
    final isPaused = currentStatus == "Paused";
    showRxActionSheet(
      context,
      title: memberName,
      actions: [
        RxSheetAction(
          icon: HugeIcons.strokeRoundedPencilEdit02,
          label: 'Edit profile',
          onTap: () => _push(
            EditMemberScreen(memberId: widget.memberId, memberData: memberData),
          ),
        ),
        RxSheetAction(
          icon: HugeIcons.strokeRoundedMoneyBag02,
          label: 'Adjust salary',
          onTap: () => _push(
            AdjustSalaryScreen(
              memberId: widget.memberId,
              currentSalary: currentSalary,
            ),
          ),
        ),
        RxSheetAction(
          icon: HugeIcons.strokeRoundedClock01,
          label: 'Salary history',
          onTap: () => _push(
            SalaryHistoryScreen(
              memberId: widget.memberId,
              memberName: memberName,
              currentSalary: currentSalary,
            ),
          ),
        ),
        RxSheetAction(
          icon: isPaused
              ? HugeIcons.strokeRoundedPlayCircle
              : HugeIcons.strokeRoundedPauseCircle,
          label: isPaused ? 'Resume member' : 'Pause member',
          subtitle: isPaused ? null : 'Suspends payroll',
          onTap: () async {
            try {
              await FirebaseFirestore.instance
                  .collection('members')
                  .doc(widget.memberId)
                  .update({'status': isPaused ? 'Active' : 'Paused'});
              if (mounted) {
                showRxToast(
                  context,
                  isPaused ? 'Member resumed' : 'Member paused',
                );
              }
            } catch (e) {
              debugPrint("Failed to update status: $e");
            }
          },
        ),
        RxSheetAction(
          icon: HugeIcons.strokeRoundedUserRemove01,
          label: 'Remove member',
          destructive: true,
          onTap: () => _confirmRemove(memberName),
        ),
      ],
    );
  }

  Future<void> _confirmRemove(String memberName) async {
    final ok = await showRxConfirm(
      context,
      title: 'Remove $memberName?',
      message:
          'They are removed from the team. Their past salary payments stay in your expenses, so totals and runway remain accurate.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Keep their payments (real spend); only the member record goes.
      await TeamMemberService.removeMembersKeepingHistory(
        uid: user.uid,
        memberIds: [widget.memberId],
        reason: 'member_deleted',
      );

      if (mounted) {
        Navigator.pop(context);
        showRxToast(context, 'Member removed. Payment history kept.');
      }
    } catch (e) {
      debugPrint("Failed to delete member: $e");
      if (mounted) {
        showRxToast(context, 'Failed to remove member', isError: true);
      }
    }
  }
}
