import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../theme/app_theme.dart';

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

      // Calculate how many months have passed since the start date
      int elapsedMonths =
          (now.year - startDate.year) * 12 + now.month - startDate.month;

      // If stopped in the same month it started, set to 1 so at least the first occurrence stays,
      // or 0 if it hasn't even happened yet.
      if (now.isBefore(startDate)) {
        elapsedMonths = 0;
      } else if (elapsedMonths <= 0) {
        elapsedMonths = 1;
      }

      await FirebaseFirestore.instance.collection('expenses').doc(docId).update(
        {'recurringTenureMonths': elapsedMonths},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Recurring payment stopped successfully.",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: const Color(0xFF30D158),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Failed to stop payment: $e",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: const Color(0xFFFF453A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _showStopConfirmation(String docId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.borderColor),
          ),
          title: Text(
            "Stop Recurring Payment?",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            "This will prevent any future occurrences from being generated, but past transactions will remain in your history. Do you want to proceed?",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                "Cancel",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _stopRecurringPayment(docId, data);
              },
              child: Text(
                "Stop Payment",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: const Color(0xFFFF453A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        "Recurring Payments",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "View and manage your active subscriptions",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 40),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('expenses')
                            .where('uid', isEqualTo: currentUser?.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: CircularProgressIndicator(
                                  color: context.textSecondary,
                                ),
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Text(
                                  "Error loading recurring payments.",
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: const Color(0xFFFF453A),
                                  ),
                                ),
                              ),
                            );
                          }

                          final allDocs = snapshot.data?.docs ?? [];
                          final recurringDocs = allDocs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final type = (data['Type'] ?? data['type'] ?? '')
                                .toString()
                                .toLowerCase();
                            return type == 'recurring' ||
                                type == 'subscription';
                          }).toList();

                          // Sort: Active first, then stopped
                          recurringDocs.sort((a, b) {
                            final dataA = a.data() as Map<String, dynamic>;
                            final dataB = b.data() as Map<String, dynamic>;
                            final isActiveA = _isActive(dataA);
                            final isActiveB = _isActive(dataB);

                            if (isActiveA && !isActiveB) return -1;
                            if (!isActiveA && isActiveB) return 1;

                            // If same status, sort by date descending
                            final dateA = dataA['Date'] ?? dataA['date'];
                            final dateB = dataB['Date'] ?? dataB['date'];
                            final Timestamp? tsA = dateA is Timestamp
                                ? dateA
                                : null;
                            final Timestamp? tsB = dateB is Timestamp
                                ? dateB
                                : null;
                            if (tsA == null || tsB == null) return 0;
                            return tsB.compareTo(tsA);
                          });

                          if (recurringDocs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 40,
                                ),
                                child: Text(
                                  "You don't have any recurring payments or subscriptions set up yet.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: context.textSecondary,
                                    height: 1.5,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: recurringDocs.length,
                            itemBuilder: (context, index) {
                              final doc = recurringDocs[index];
                              final data = doc.data() as Map<String, dynamic>;

                              final title =
                                  data['Title']?.toString() ?? 'Unknown';
                              final amount =
                                  double.tryParse(
                                    data['Amount']?.toString() ?? '0',
                                  ) ??
                                  0.0;
                              final frequency =
                                  (data['recurrenceFrequency'] ?? 'monthly')
                                      .toString();
                              final isActive = _isActive(data);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: context.cardBackground,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: context.borderColor,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: context.isDarkMode
                                                    ? Colors.white.withValues(
                                                        alpha: 0.05,
                                                      )
                                                    : Colors.black.withValues(
                                                        alpha: 0.05,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                Icons.autorenew,
                                                color: context.iconSecondary,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: TextStyle(
                                                    fontFamily: 'Satoshi',
                                                    color: context.textPrimary,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  frequency.toUpperCase(),
                                                  style: TextStyle(
                                                    fontFamily: 'Satoshi',
                                                    color: context.textTertiary,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _formatCurrency(amount),
                                              style: TextStyle(
                                                fontFamily: 'Satoshi',
                                                color: context.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isActive
                                                    ? const Color(
                                                        0xFF30D158,
                                                      ).withValues(alpha: 0.1)
                                                    : context.isDarkMode
                                                    ? Colors.white.withValues(
                                                        alpha: 0.1,
                                                      )
                                                    : Colors.black.withValues(
                                                        alpha: 0.1,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                isActive ? "ACTIVE" : "STOPPED",
                                                style: TextStyle(
                                                  fontFamily: 'Satoshi',
                                                  color: isActive
                                                      ? const Color(0xFF30D158)
                                                      : context.textSecondary,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (isActive) ...[
                                      const SizedBox(height: 16),
                                      Divider(
                                        color: context.borderColor,
                                        height: 1,
                                      ),
                                      const SizedBox(height: 16),
                                      GestureDetector(
                                        onTap: () =>
                                            _showStopConfirmation(doc.id, data),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFFFF453A,
                                            ).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFFFF453A,
                                              ).withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              "STOP PAYMENT",
                                              style: TextStyle(
                                                fontFamily: 'Satoshi',
                                                color: const Color(0xFFFF453A),
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 44), // To balance the back button
        ],
      ),
    );
  }
}
