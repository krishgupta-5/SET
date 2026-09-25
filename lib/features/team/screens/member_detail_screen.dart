import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// NOTE: Ensure these files exist or comment them out if testing in isolation
import 'edit_member_screen.dart';
import 'adjust_salary_screen.dart';
import 'payment_history_screen.dart';
import 'salary_history_screen.dart';
import 'process_payment_screen.dart';
import 'transaction_details_screen.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../utils/data_helpers.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/expense_expansion_helper.dart';

class MemberDetailScreen extends StatefulWidget {
  final String memberId;

  const MemberDetailScreen({super.key, required this.memberId});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  String _userCountryCode = '+1'; // Default to USD
  final bool _isLoadingCountry =
      false; // Start as false since we use sync method

  // Cache for Telegram photos to avoid repeated fetching
  static final Map<String, String> _telegramPhotoCache = {};

  @override
  void initState() {
    super.initState();
    // Get currency preference synchronously for instant display
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    // Listen for currency changes
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    // Load in background for more accurate result
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

  // Format the raw employment type to a readable string
  String _formatEmploymentType(String raw) {
    switch (raw) {
      case 'full_time':
        return 'Full-time';
      case 'part_time':
        return 'Part-time';
      case 'contractor':
        return 'Contractor';
      case 'intern':
        return 'Intern';
      default:
        return raw;
    }
  }

  // Format Timestamp to "Aug 12, 2023" format
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "Unknown";
    final DateTime dt = timestamp.toDate();
    final List<String> months = [
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
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
                return Center(
                  child: CircularProgressIndicator(
                    color: context.textSecondary,
                  ),
                );
              }

              if (snapshot.hasError ||
                  !snapshot.hasData ||
                  !snapshot.data!.exists) {
                return Center(
                  child: Text(
                    "Member not found.",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                    ),
                  ),
                );
              }

              final memberData = snapshot.data!.data() as Map<String, dynamic>;

              final String name = memberData['fullName'] ?? "Unnamed Member";
              final String role = memberData['jobTitle'] ?? "No Role";
              final String email = memberData['email'] ?? "No Email";
              final String status = memberData['status'] ?? "Active";
              final double cost = (memberData['monthlyCost'] ?? 0.0).toDouble();
              final String salary = _isLoadingCountry
                  ? CurrencyFormatter.formatByCountryCompact(cost, '+1')
                  : CurrencyFormatter.formatByCountryCompact(
                      cost,
                      _userCountryCode,
                    );
              final String empType = _formatEmploymentType(
                memberData['employmentType'] ?? "",
              );

              // Get Joining Date
              final Timestamp? joinedTs =
                  memberData['joiningDate'] as Timestamp?;
              final DateTime joinedDateObj =
                  joinedTs?.toDate() ?? DateTime.now();
              final String joinedDateStr = _formatDate(joinedTs);

              final String teamId = memberData['teamId'] ?? "";

              // Check for Telegram photo in both telegramFileId and avatarUrl fields
              final String? telegramFileId = memberData['telegramFileId'];
              final String? avatarUrl = memberData['avatarUrl'];

              // Determine if avatarUrl contains a Telegram file ID (for backward compatibility)
              final String? telegramFileIdFromAvatar =
                  (avatarUrl != null &&
                      avatarUrl.isNotEmpty &&
                      !avatarUrl.startsWith('http') &&
                      !avatarUrl.contains('ui-avatars.com'))
                  ? avatarUrl
                  : null;

              return Column(
                children: [
                  // 1. Header
                  _buildHeader(context, name, status, cost, memberData),

                  // 2. Scrollable Content
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 24),

                          // --- PROFILE HERO ---
                          FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('teams')
                                .doc(teamId)
                                .get(),
                            builder: (context, teamSnapshot) {
                              String teamName = "Loading Team...";
                              if (teamSnapshot.hasData &&
                                  teamSnapshot.data!.exists) {
                                teamName =
                                    (teamSnapshot.data!.data()
                                        as Map<String, dynamic>)['teamName'] ??
                                    "Unknown Team";
                              }

                              return Column(
                                children: [
                                  _buildProfileHero(
                                    name,
                                    role,
                                    teamName,
                                    avatarUrl ?? "",
                                    status,
                                    telegramFileId ?? telegramFileIdFromAvatar,
                                  ),

                                  const SizedBox(height: 32),

                                  // --- FINANCIAL HERO ---
                                  _buildCostCard(salary, status),

                                  const SizedBox(height: 16),

                                  // --- PAY SALARY / ADVANCE ACTION ---
                                  _buildPaySalaryAction(
                                    cost,
                                    joinedDateObj,
                                    status,
                                    name,
                                    teamId,
                                    teamName,
                                  ),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 32),

                          // --- DETAILS SECTION ---
                          _buildSectionTitle("EMPLOYMENT DETAILS"),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: context.cardBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: context.borderColor),
                              boxShadow: context.cardShadow,
                            ),
                            child: Column(
                              children: [
                                _buildDetailRow(
                                  "Email",
                                  email,
                                  Icons.email_outlined,
                                ),
                                _buildDivider(),
                                _buildDetailRow(
                                  "Joined",
                                  joinedDateStr,
                                  Icons.calendar_today,
                                ),
                                _buildDivider(),
                                _buildDetailRow(
                                  "Type",
                                  empType,
                                  Icons.badge_outlined,
                                ),
                                _buildDivider(),
                                _buildDetailRow(
                                  "Location",
                                  "Remote",
                                  Icons.location_on_outlined,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // --- RECENT PAYOUTS ---
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSectionTitle("PAYMENT HISTORY"),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          PaymentHistoryScreen(
                                            joiningDate: joinedDateObj,
                                            salary: cost,
                                            memberName: name,
                                            memberId: widget.memberId,
                                          ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical:
                                        8, // Slightly taller for touch area
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.cardBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: context.borderColor,
                                    ),
                                    boxShadow: context.cardShadow,
                                  ),
                                  child: Text(
                                    "VIEW ALL",
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: context.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildPaymentHistory(salary, joinedDateObj, name),

                          const SizedBox(height: 40),
                        ],
                      ),
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
    String memberName,
    String currentStatus,
    double currentSalary,
    Map<String, dynamic> memberData,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
                boxShadow: context.cardShadow,
              ),
              child: Icon(
                Icons.arrow_back,
                color: context.textPrimary,
                size: 20,
              ),
            ),
          ),

          Expanded(
            child: Text(
              "Member Profile",
              textAlign: TextAlign.center, // Centered title
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          GestureDetector(
            onTap: () => _showMemberActionSheet(
              context,
              memberName,
              currentStatus,
              currentSalary,
              memberData,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
                boxShadow: context.cardShadow,
              ),
              child: Icon(
                Icons.more_horiz,
                color: context.textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHero(
    String name,
    String role,
    String team,
    String avatarUrl,
    String status,
    String? telegramFileId,
  ) {
    Color statusColor = status == "Active"
        ? const Color(0xFF30D158)
        : const Color(0xFFFF9F0A);

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            ),
            _buildMemberAvatar(name, 100, avatarUrl, telegramFileId),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          name,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "$role • $team",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.2)),
          ),
          child: Text(
            status.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: statusColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCostCard(String salary, String status) {
    bool isPaused = status == "Paused";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        children: [
          Text(
            "MONTHLY COST",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPaused
                ? "${CurrencyFormatter.getCurrencySymbol(_isLoadingCountry ? '+1' : _userCountryCode)}0.00"
                : salary,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: isPaused ? context.textTertiary : context.textPrimary,
              fontSize: 42,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              decoration: isPaused ? TextDecoration.lineThrough : null,
              decorationColor: context.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPaused ? Icons.pause_circle_outline : Icons.trending_flat,
                color: isPaused
                    ? const Color(0xFFFF9F0A)
                    : context.textSecondary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                isPaused ? "Payroll Suspended" : "No change from last month",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: isPaused
                      ? const Color(0xFFFF9F0A)
                      : context.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaySalaryAction(
    double cost,
    DateTime joinedDate,
    String status,
    String memberName,
    String teamId,
    String teamName,
  ) {
    bool isPaused = status == "Paused";

    // Hide payment option if payroll is suspended
    if (isPaused) return const SizedBox.shrink();

    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: currentUser?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(color: context.textSecondary),
          );
        }

        // 1. Count Total Salary Payments Made for this member
        // A recurring salary doc represents multiple months — expand it into
        // individual occurrences and count how many have passed up to today.
        int totalPaymentsMade = 0;
        if (snapshot.hasData) {
          final now2 = DateTime.now();
          final salaryDocs = snapshot.data!.docs
              .map(
                (doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id},
              )
              .where((data) {
                final category =
                    data['Category']?.toString().toLowerCase() ?? '';
                return category == 'salary' &&
                    data['memberId'] == widget.memberId;
              })
              .toList();

          // Expand all salary entries (handles recurring by splitting into occurrences)
          final expanded = ExpenseExpansionHelper.expandExpenses(
            salaryDocs,
            maxDate: now2,
          );
          totalPaymentsMade = expanded.length;
        }

        DateTime addMonths(DateTime date, int months) {
          int newYear = date.year + (date.month + months - 1) ~/ 12;
          int newMonth = (date.month + months - 1) % 12 + 1;
          int newDay = date.day;

          int maxDaysInNewMonth = DateTime(newYear, newMonth + 1, 0).day;
          if (newDay > maxDaysInNewMonth) {
            newDay = maxDaysInNewMonth;
          }
          return DateTime(newYear, newMonth, newDay);
        }

        DateTime nextDueDate = addMonths(joinedDate, totalPaymentsMade + 1);
        DateTime now = DateTime.now();
        DateTime today = DateTime(now.year, now.month, now.day);

        bool isAdvance = today.isBefore(nextDueDate);
        bool shouldHideAdvanceButton = totalPaymentsMade == 0;

        final List<String> monthsStr = [
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
        String formattedDueDate =
            "${monthsStr[nextDueDate.month - 1]} ${nextDueDate.day}, ${nextDueDate.year}";

        if (isAdvance && shouldHideAdvanceButton) {
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: context.textSecondary,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Next Due: $formattedDueDate",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                  boxShadow: context.cardShadow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: context.textSecondary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Advance payment not available yet",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isAdvance ? Icons.info_outline : Icons.warning_amber_rounded,
                  color: isAdvance
                      ? context.textSecondary
                      : const Color(0xFFFF9F0A),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  isAdvance
                      ? "Next Due: $formattedDueDate"
                      : "Due: $formattedDueDate",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: isAdvance
                        ? context.textSecondary
                        : const Color(0xFFFF9F0A),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProcessPaymentScreen(
                        memberId: widget.memberId,
                        memberName: memberName,
                        teamId: teamId,
                        teamName: teamName,
                        defaultAmount: cost,
                        isAdvance: isAdvance,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isAdvance
                      ? context.cardBackground
                      : context.textPrimary,
                  foregroundColor: isAdvance
                      ? context.textPrimary
                      : context.appBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isAdvance
                        ? BorderSide(color: context.borderColor)
                        : BorderSide.none,
                  ),
                  elevation: 0,
                ),
                child: Text(
                  isAdvance ? "Advance Pay" : "Pay Salary",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: context.textSecondary, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(color: context.borderColor, height: 1),
    );
  }

  Widget _buildPaymentHistory(
    String currentSalary,
    DateTime joinedDate,
    String memberName,
  ) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: currentUser?.uid)
          // Fix #7: Filter server-side to avoid loading all expenses
          .where('memberId', isEqualTo: widget.memberId)
          .where('Category', isEqualTo: 'salary')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
              boxShadow: context.cardShadow,
            ),
            child: Center(
              child: CircularProgressIndicator(color: context.textSecondary),
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
              boxShadow: context.cardShadow,
            ),
            child: Center(
              child: Text(
                "Error loading payment history.",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        // Extract raw docs, expand recurring entries into individual occurrences
        final allDocs = snapshot.data?.docs ?? [];
        final rawList = allDocs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {...data, 'id': doc.id};
        }).toList();

        final expanded = ExpenseExpansionHelper.expandExpenses(
          rawList,
          maxDate: DateTime.now(),
        );

        List<Map<String, dynamic>> memberPayments = [];

        for (var data in expanded) {
          final String title = data['Title']?.toString() ?? '';
          final rawDate = data['Date'] ?? data['date'];
          final Timestamp? ts = rawDate is Timestamp ? rawDate : null;

          final double amt = (data['Amount'] as num?)?.toDouble() ?? 0.0;

          memberPayments.add({
            "id": data['id'] ?? data['expenseId'] ?? '',
            "rawData": data,
            "rawDate": ts,
            "date": _formatDate(ts),
            "amt": _isLoadingCountry
                ? CurrencyFormatter.formatByCountryCompact(amt, '+1')
                : CurrencyFormatter.formatByCountryCompact(
                    amt,
                    _userCountryCode,
                  ),
            "title": title.contains("Advance")
                ? "Advance Payout"
                : "Salary Payout",
          });
        }

        // Sort newest first and take only top 3
        memberPayments.sort((a, b) {
          final Timestamp? dateA = a["rawDate"];
          final Timestamp? dateB = b["rawDate"];
          if (dateA == null || dateB == null) return 0;
          return dateB.compareTo(dateA);
        });

        final previewPayments = memberPayments.take(3).toList();

        if (previewPayments.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
              boxShadow: context.cardShadow,
            ),
            child: Center(
              child: Text(
                "No payouts processed yet.\nClick 'Pay Salary' to log the first payment.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        return Column(
          children: previewPayments.map((p) {
            bool isAdvance = p['title'] == "Advance Payout";

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TransactionDetailsScreen(
                        transactionId: p['id'],
                        transactionData: p['rawData'],
                        formattedDate: p['date'],
                        formattedAmount: p['amt'],
                        displayTitle: p['title'],
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: context.cardBackground,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: context.borderColor),
                    boxShadow: context.cardShadow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: context.appBackground,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isAdvance
                                  ? Icons.fast_forward
                                  : Icons.arrow_outward,
                              color: context.textPrimary,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['title']!,
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p['date']!,
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        p['amt']!,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showMemberActionSheet(
    BuildContext context,
    String memberName,
    String currentStatus,
    double currentSalary,
    Map<String, dynamic> memberData,
  ) {
    bool isPaused = currentStatus == "Paused";

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
                  "Manage $memberName",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),

                _buildActionOption(Icons.edit_outlined, "Edit Profile", () {
                  Navigator.pop(bottomSheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditMemberScreen(
                        memberId: widget.memberId,
                        memberData: memberData,
                      ),
                    ),
                  );
                }),

                _buildActionOption(Icons.currency_rupee, "Adjust Salary", () {
                  Navigator.pop(bottomSheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdjustSalaryScreen(
                        memberId: widget.memberId,
                        currentSalary: currentSalary,
                      ),
                    ),
                  );
                }),

                _buildActionOption(Icons.history, "Appraisal History", () {
                  Navigator.pop(bottomSheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SalaryHistoryScreen(
                        memberId: widget.memberId,
                        memberName: memberName,
                        currentSalary: currentSalary,
                      ),
                    ),
                  );
                }),

                _buildActionOption(
                  isPaused
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  isPaused ? "Resume Member" : "Pause Member",
                  () async {
                    Navigator.pop(bottomSheetContext);
                    try {
                      await FirebaseFirestore.instance
                          .collection('members')
                          .doc(widget.memberId)
                          .update({'status': isPaused ? 'Active' : 'Paused'});

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: context.textPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              isPaused
                                  ? "Member resumed."
                                  : "Member paused. Payroll suspended.",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.appBackground,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint("Failed to update status: $e");
                    }
                  },
                ),

                const SizedBox(height: 16),
                Divider(color: context.borderColor, height: 1),
                const SizedBox(height: 16),

                _buildActionOption(
                  Icons.person_remove_outlined,
                  "Remove Member",
                  () {
                    Navigator.pop(bottomSheetContext);
                    _showDeleteConfirmation(context, memberName);
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

  // --- WHITE GLASS ACTION SHEET BUTTONS ---
  Widget _buildActionOption(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDestructive
              ? const Color(0xFFFF453A).withValues(alpha: 0.1)
              : context.appBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDestructive
                ? const Color(0xFFFF453A).withValues(alpha: 0.2)
                : context.borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive
                  ? const Color(0xFFFF453A)
                  : context.textPrimary,
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: isDestructive
                    ? const Color(0xFFFF453A)
                    : context.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- GORGEOUS CUSTOM DELETE DIALOG ---
  void _showDeleteConfirmation(BuildContext context, String memberName) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8), // Darken backdrop
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon & Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF453A).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFFF453A),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Remove Member?",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Warning Text
                Text(
                  "This will permanently remove $memberName from the team and archive all associated payment history.",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(dialogContext),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: context.appBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.borderColor),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            "Cancel",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          try {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null) {
                              throw Exception('User not authenticated');
                            }

                            // Get companyId from user document
                            final userDoc = await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .get();

                            final companyId = userDoc.data()?['companyId'];
                            if (companyId == null) {
                              throw Exception('Company not found');
                            }

                            // Get member data before deletion for financial calculations
                            final memberDoc = await FirebaseFirestore.instance
                                .collection('members')
                                .doc(widget.memberId)
                                .get();

                            if (!memberDoc.exists) {
                              throw Exception('Member not found');
                            }

                            final memberData = memberDoc.data()!;
                            final memberSalary = DataHelpers.safeParseDouble(
                              memberData['monthlyCost'] ?? 0,
                            );
                            final memberName =
                                memberData['fullName'] ?? 'Unknown';

                            // Use batch for atomic operations
                            final batch = FirebaseFirestore.instance.batch();

                            // Fix #6: Salary payments are stored in 'expenses'
                            // (not 'payments') with Category='salary'.
                            // Archive them before deletion so history is preserved.
                            final paymentsSnapshot = await FirebaseFirestore
                                .instance
                                .collection('expenses')
                                .where('uid', isEqualTo: user.uid)
                                .where('memberId', isEqualTo: widget.memberId)
                                .where('Category', isEqualTo: 'salary')
                                .get();

                            // Create archived payment records
                            final archiveCollection = FirebaseFirestore.instance
                                .collection('archived_payments');

                            for (var paymentDoc in paymentsSnapshot.docs) {
                              final paymentData = paymentDoc.data();
                              paymentData['originalMemberId'] = widget.memberId;
                              paymentData['originalMemberName'] = memberName;
                              paymentData['archivedAt'] =
                                  FieldValue.serverTimestamp();
                              paymentData['archiveReason'] = 'member_deleted';

                              final archiveRef = archiveCollection.doc();
                              batch.set(archiveRef, paymentData);

                              // Delete original payment
                              batch.delete(paymentDoc.reference);
                            }

                            // Delete member document
                            final memberRef = FirebaseFirestore.instance
                                .collection('members')
                                .doc(widget.memberId);
                            batch.delete(memberRef);

                            // Update company financial totals
                            final companyRef = FirebaseFirestore.instance
                                .collection('companies')
                                .doc(companyId);

                            // monthlyCost is already the monthly amount, no division needed
                            final monthlySalaryImpact = memberSalary;
                            batch.update(companyRef, {
                              "totalExpenses": FieldValue.increment(
                                -monthlySalaryImpact,
                              ),
                            });

                            // Commit all operations atomically
                            await batch.commit();

                            if (context.mounted) {
                              Navigator.pop(context); // Go back to team detail
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Member removed and payment history archived",
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: context.appBackground,
                                    ),
                                  ),
                                  backgroundColor: context.textPrimary,
                                ),
                              );
                            }
                          } catch (e) {
                            debugPrint("Failed to delete member: $e");
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Failed to remove member",
                                    style: TextStyle(fontFamily: 'Satoshi'),
                                  ),
                                  backgroundColor: const Color(0xFFFF453A),
                                ),
                              );
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF453A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            "Remove",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Build member avatar with Telegram photo support
  Widget _buildMemberAvatar(
    String name,
    double size,
    String avatarUrl,
    String? telegramFileId,
  ) {
    // Check if it's a Telegram photo
    if (telegramFileId != null && telegramFileId.isNotEmpty) {
      return FutureBuilder<String>(
        future: getTelegramImageUrl(telegramFileId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Show loading indicator while fetching Telegram photo
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: context.cardBackground,
                shape: BoxShape.circle,
                border: Border.all(color: context.borderColor),
                boxShadow: context.cardShadow,
              ),
              child: Center(
                child: SizedBox(
                  width: size * 0.3,
                  height: size * 0.3,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.textSecondary,
                  ),
                ),
              ),
            );
          } else if (snapshot.hasError || !snapshot.hasData) {
            // Fallback to generated avatar on error
            return AvatarWidget(
              name: name,
              size: size,
              imageUrl: null,
              fontSize: size * 0.4,
            );
          } else {
            // Show Telegram photo
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
      // Handle regular avatar URL
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

  // Telegram photo fetching methods with caching
  Future<String> getTelegramImageUrl(String fileId) async {
    // Check cache first
    if (_telegramPhotoCache.containsKey(fileId)) {
      return _telegramPhotoCache[fileId]!;
    }

    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];
      if (botToken == null) {
        throw Exception('Telegram bot token not found in environment');
      }

      final res = await http.get(
        Uri.parse(
          "https://api.telegram.org/bot$botToken/getFile?file_id=$fileId",
        ),
      );

      final data = jsonDecode(res.body);
      final path = data['result']['file_path'];
      final imageUrl = "https://api.telegram.org/file/bot$botToken/$path";

      // Cache the result
      _telegramPhotoCache[fileId] = imageUrl;

      return imageUrl;
    } catch (e) {
      debugPrint('Error getting Telegram image URL: $e');
      rethrow;
    }
  }
}
