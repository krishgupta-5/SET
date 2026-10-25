import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';

class SalaryHistoryScreen extends StatefulWidget {
  final String memberId;
  final String memberName;
  final double currentSalary;

  const SalaryHistoryScreen({
    super.key,
    required this.memberId,
    required this.memberName,
    required this.currentSalary,
  });

  @override
  State<SalaryHistoryScreen> createState() => _SalaryHistoryScreenState();
}

class _SalaryHistoryScreenState extends State<SalaryHistoryScreen> {
  bool _isRevoking = false;

  String _formatCurrency(double amount) =>
      CurrencyFormatter.formatByCountryCompact(
        amount,
        CurrencyPreferenceService.getCurrencyPreferenceSync(),
      );

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "Unknown date";
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

  Future<void> _revokeFutureSalary() async {
    final ok = await showRxConfirm(
      context,
      title: 'Cancel scheduled change?',
      message: 'The salary stays at ${_formatCurrency(widget.currentSalary)}.',
      confirmLabel: 'Cancel change',
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _isRevoking = true);
    try {
      await FirebaseFirestore.instance
          .collection('members')
          .doc(widget.memberId)
          .update({
            'futureSalary': FieldValue.delete(),
            'futureSalaryDate': FieldValue.delete(),
            'futureSalaryReason': FieldValue.delete(),
          });
      if (mounted) showRxToast(context, "Scheduled change cancelled");
    } catch (e) {
      if (mounted) {
        showRxToast(context, "Failed to cancel change", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isRevoking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Salary history'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.paddingOf(context).bottom + 32,
                  ),
                  children: [
                    RxReveal.index(0, child: _buildCurrent()),
                    RxReveal.index(1, child: _buildPendingUpdateSection()),
                    const SizedBox(height: 28),
                    RxReveal.index(2, child: _buildHistorySection()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${widget.memberName} earns', style: RxText.label(context)),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _formatCurrency(widget.currentSalary),
            style: RxText.hero(context, size: 44),
          ),
        ),
        const SizedBox(height: 4),
        Text('per month', style: RxText.caption(context)),
      ],
    );
  }

  // Scheduled change, if any. Nothing is shown when none is pending.
  Widget _buildPendingUpdateSection() {
    final rx = context.rx;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('members')
          .doc(widget.memberId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final futureSalary = data['futureSalary'];
        final futureDate = data['futureSalaryDate'] as Timestamp?;
        if (futureSalary == null || futureDate == null) {
          return const SizedBox.shrink();
        }
        final reason =
            data['futureSalaryReason'] as String? ?? "No reason provided";
        final next = (futureSalary as num).toDouble();
        final up = next >= widget.currentSalary;

        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: RxCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RxPill(
                      label: 'Scheduled · ${_formatDate(futureDate)}',
                      dot: true,
                      foreground: rx.warning,
                      background: rx.warningSoft,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      _formatCurrency(widget.currentSalary),
                      style: RxText.amount(context, color: rx.textSecondary),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowRight02,
                        color: rx.textTertiary,
                        size: 16,
                        strokeWidth: 2,
                      ),
                    ),
                    Text(
                      _formatCurrency(next),
                      style: RxText.value(
                        context,
                        size: 20,
                        color: up ? rx.positive : rx.negative,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(reason, style: RxText.caption(context)),
                const SizedBox(height: 14),
                RxButton(
                  label: 'Cancel scheduled change',
                  height: 44,
                  style: RxButtonStyle.secondary,
                  loading: _isRevoking,
                  onTap: _revokeFutureSalary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistorySection() {
    final rx = context.rx;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('members')
          .doc(widget.memberId)
          .collection('salary_history')
          .orderBy('changedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const RxSkeleton(height: 160, radius: 22);
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const RxCard(
            child: RxEmptyState(
              icon: HugeIcons.strokeRoundedClock01,
              title: 'No changes yet',
              message: 'Raises and adjustments show up here',
            ),
          );
        }

        return Column(
          children: [
            const RxSectionHeader(title: 'Changes'),
            RxCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < docs.length; i++) ...[
                    if (i > 0) const RxDivider(indent: 52),
                    () {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final prev =
                          (data['previousSalary'] as num?)?.toDouble() ?? 0.0;
                      final current =
                          (data['newSalary'] as num?)?.toDouble() ?? 0.0;
                      final delta =
                          (data['delta'] as num?)?.toDouble() ??
                          (current - prev);
                      final reason =
                          data['reason'] as String? ?? 'No reason provided';
                      final date = data['effectiveDate'] as Timestamp?;
                      final initial = prev == 0 && current > 0;
                      final up = delta > 0;
                      final color = initial
                          ? rx.textSecondary
                          : (up ? rx.positive : rx.negative);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            RxIconTile(
                              icon: initial
                                  ? HugeIcons.strokeRoundedStar
                                  : up
                                  ? HugeIcons.strokeRoundedArrowUpRight01
                                  : HugeIcons.strokeRoundedArrowDownRight01,
                              size: 40,
                              iconSize: 19,
                              background: initial
                                  ? rx.surfaceMuted
                                  : (up ? rx.positiveSoft : rx.negativeSoft),
                              foreground: color,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reason,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: RxText.body(context),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_formatDate(date)} · from ${_formatCurrency(prev)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: RxText.caption(context),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatCurrency(current),
                                  style: RxText.amount(context),
                                ),
                                if (!initial)
                                  Text(
                                    '${up ? '+' : '−'}${_formatCurrency(delta.abs())}',
                                    style: RxText.micro(context, color: color),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }(),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
