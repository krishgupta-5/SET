import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../models/domain_events.dart';
import '../../../services/event_dispatcher.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';

class ManageRecurringPaymentsScreen extends StatefulWidget {
  const ManageRecurringPaymentsScreen({super.key});

  @override
  State<ManageRecurringPaymentsScreen> createState() =>
      _ManageRecurringPaymentsScreenState();
}

class _ManageRecurringPaymentsScreenState
    extends State<ManageRecurringPaymentsScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Helper to format currency
  String _formatCurrency(double amount) {
    final userCurrencyCode =
        CurrencyPreferenceService.getCurrencyPreferenceSync();
    return CurrencyFormatter.formatByCountryCompact(amount, userCurrencyCode);
  }

  // Calculate if recurring is active
  bool _isActive(Map<String, dynamic> data) {
    final rawDate = data['Date'] ?? data['date'];
    if (rawDate == null) return false;

    DateTime startDate;
    if (rawDate is Timestamp) {
      startDate = rawDate.toDate();
    } else if (rawDate is DateTime) {
      startDate = rawDate;
    } else {
      return false;
    }

    final tenureMonths = data['recurringTenureMonths'] as int?;
    if (tenureMonths == null) return true; // Indefinite

    final endDate = DateTime(
      startDate.year,
      startDate.month + tenureMonths,
      startDate.day,
      startDate.hour,
      startDate.minute,
      startDate.second,
      startDate.millisecond,
      startDate.microsecond,
    );

    return endDate.isAfter(DateTime.now());
  }

  // Stop a recurring payment
  Future<void> _stopRecurringPayment(
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      final rawDate = data['Date'] ?? data['date'];
      if (rawDate == null) return;

      DateTime startDate;
      if (rawDate is Timestamp) {
        startDate = rawDate.toDate();
      } else if (rawDate is DateTime) {
        startDate = rawDate;
      } else {
        return;
      }

      final now = DateTime.now();

      // Keep every charge that has already happened and nothing after it.
      // Tenure is exclusive (N months = charges at months 0..N-1), so the
      // tenure is "months up to and including the last past charge" + 1.
      // The old month-diff dropped the current month's charge when it had
      // already been billed (e.g. started Jan 20, stopped Mar 25 → lost Mar 20).
      int tenureMonths;
      if (now.isBefore(startDate)) {
        tenureMonths = 0; // never charged
      } else {
        final monthsSince =
            (now.year - startDate.year) * 12 + now.month - startDate.month;
        final thisMonthsCharge = DateTime(
          startDate.year,
          startDate.month + monthsSince,
          startDate.day,
        );
        tenureMonths = thisMonthsCharge.isAfter(now)
            ? monthsSince
            : monthsSince + 1;
      }

      // Tenure is month-based, which is too coarse for daily/weekly series,
      // so always record the exact stop time as well; expansion stops there.
      final update = <String, dynamic>{
        'recurringTenureMonths': tenureMonths,
        'recurringEndDate': Timestamp.fromDate(now),
      };

      await FirebaseFirestore.instance
          .collection('expenses')
          .doc(docId)
          .update(update);
      EventDispatcher().dispatch(ExpenseUpdatedEvent(docId));

      if (mounted) showRxToast(context, 'Recurring payment stopped');
    } catch (e) {
      if (mounted) {
        showRxToast(context, 'Failed to stop payment', isError: true);
      }
    }
  }

  Future<void> _confirmStop(String docId, Map<String, dynamic> data) async {
    final title = data['Title']?.toString() ?? 'this payment';
    final ok = await showRxConfirm(
      context,
      title: 'Stop $title?',
      message:
          'No future payments will be created. Past ones stay in your history.',
      confirmLabel: 'Stop payment',
      destructive: true,
    );
    if (ok) await _stopRecurringPayment(docId, data);
  }

  String _frequencyLabel(String f) => switch (f.toLowerCase()) {
    'daily' => 'Daily',
    'weekly' => 'Weekly',
    'yearly' => 'Yearly',
    _ => 'Monthly',
  };

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
              const RxTopBar(title: 'Recurring payments'),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('expenses')
                      .where('uid', isEqualTo: currentUser?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: const [
                          RxSkeleton(height: 92, radius: 22),
                          SizedBox(height: 24),
                          RxSkeleton(height: 220, radius: 22),
                        ],
                      );
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: RxEmptyState(
                          icon: HugeIcons.strokeRoundedAlert02,
                          title: "Couldn't load recurring payments",
                          message: 'Go back and try again',
                        ),
                      );
                    }

                    final docs = (snapshot.data?.docs ?? []).where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final type = (data['Type'] ?? data['type'] ?? '')
                          .toString()
                          .toLowerCase();
                      return type == 'recurring' || type == 'subscription';
                    }).toList();

                    if (docs.isEmpty) {
                      return const Center(
                        child: RxEmptyState(
                          icon: HugeIcons.strokeRoundedRepeat,
                          title: 'No recurring payments',
                          message:
                              'Subscriptions and salaries you set to repeat show up here',
                        ),
                      );
                    }

                    int byDate(
                      QueryDocumentSnapshot a,
                      QueryDocumentSnapshot b,
                    ) {
                      final da =
                          (a.data() as Map)['Date'] ??
                          (a.data() as Map)['date'];
                      final db =
                          (b.data() as Map)['Date'] ??
                          (b.data() as Map)['date'];
                      if (da is! Timestamp || db is! Timestamp) return 0;
                      return db.compareTo(da);
                    }

                    final active =
                        docs
                            .where(
                              (d) =>
                                  _isActive(d.data() as Map<String, dynamic>),
                            )
                            .toList()
                          ..sort(byDate);
                    final stopped =
                        docs
                            .where(
                              (d) =>
                                  !_isActive(d.data() as Map<String, dynamic>),
                            )
                            .toList()
                          ..sort(byDate);

                    // Monthly-equivalent total of what's still running.
                    double monthly = 0;
                    for (final d in active) {
                      final data = d.data() as Map<String, dynamic>;
                      final amt =
                          double.tryParse(data['Amount']?.toString() ?? '0') ??
                          0;
                      monthly += switch ((data['recurrenceFrequency'] ??
                              'monthly')
                          .toString()
                          .toLowerCase()) {
                        'daily' => amt * 30,
                        'weekly' => amt * 52 / 12,
                        'yearly' => amt / 12,
                        _ => amt,
                      };
                    }

                    return ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        20,
                        12,
                        20,
                        MediaQuery.paddingOf(context).bottom + 32,
                      ),
                      children: [
                        RxReveal.index(
                          0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Running each month',
                                style: RxText.label(context),
                              ),
                              const SizedBox(height: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _formatCurrency(monthly),
                                  style: RxText.hero(context, size: 44),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${active.length} active · ${stopped.length} stopped',
                                style: RxText.caption(context),
                              ),
                            ],
                          ),
                        ),
                        if (active.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          RxReveal.index(
                            1,
                            child: _section('Active', active, rx, true),
                          ),
                        ],
                        if (stopped.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          RxReveal.index(
                            2,
                            child: _section('Stopped', stopped, rx, false),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(
    String title,
    List<QueryDocumentSnapshot> docs,
    RxColors rx,
    bool active,
  ) {
    return Column(
      children: [
        RxSectionHeader(title: title),
        RxCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < docs.length; i++) ...[
                if (i > 0) const RxDivider(indent: 52),
                _row(docs[i], rx, active),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(QueryDocumentSnapshot doc, RxColors rx, bool active) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['Title']?.toString() ?? 'Unknown';
    final amount = double.tryParse(data['Amount']?.toString() ?? '0') ?? 0.0;
    final category = (data['Category'] ?? 'others').toString();
    final freq = _frequencyLabel(
      (data['recurrenceFrequency'] ?? 'monthly').toString(),
    );
    final tenure = data['recurringTenureMonths'] as int?;
    final subtitle = [
      freq,
      if (tenure != null) '$tenure ${tenure == 1 ? 'month' : 'months'}',
      if (tenure == null) 'Ongoing',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Opacity(
            opacity: active ? 1 : 0.5,
            child: RxIconTile(
              icon: RxCategory.icon(category),
              size: 40,
              iconSize: 19,
              background: RxCategory.soft(context, category),
              foreground: RxCategory.color(context, category),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RxText.body(
                    context,
                    color: active ? rx.textPrimary : rx.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RxText.caption(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatCurrency(amount),
            style: RxText.amount(
              context,
              color: active ? rx.textPrimary : rx.textTertiary,
            ),
          ),
          if (active)
            RxPressable(
              onTap: () => _confirmStop(doc.id, data),
              semanticLabel: 'Stop $title',
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedStopCircle,
                    color: rx.negative,
                    size: 20,
                    strokeWidth: 1.8,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
