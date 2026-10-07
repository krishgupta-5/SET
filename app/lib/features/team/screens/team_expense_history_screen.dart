import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'transaction_details_screen.dart';
import '../../../../services/currency_formatter.dart';
import '../../../../services/currency_preference_service.dart';
import '../../../../services/bank_account_service.dart';
import '../../../../utils/expense_expansion_helper.dart';
import '../../../../theme/app_theme.dart';

class TeamExpenseHistoryScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final double? monthlyBudget;

  const TeamExpenseHistoryScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    this.monthlyBudget,
  });

  @override
  State<TeamExpenseHistoryScreen> createState() =>
      _TeamExpenseHistoryScreenState();
}

class _TeamExpenseHistoryScreenState extends State<TeamExpenseHistoryScreen> {
  bool _isDownloading = false;

  // Helper to format currency
  String _formatCurrency(double amount) {
    final userCurrencyCode =
        CurrencyPreferenceService.getCurrencyPreferenceSync();
    return CurrencyFormatter.formatByCountryCompact(amount, userCurrencyCode);
  }

  // Helper to format Firestore Timestamp
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "Unknown Date";
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
    return "${months[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}";
  }

  // --- TEAM EXPENSE HISTORY DOWNLOAD LOGIC ---
  Future<void> _downloadPaymentHistory() async {
    setState(() => _isDownloading = true);

    // Use currency service for PDF formatting with fallback for unsupported symbols
    String getPdfCurrencySymbol(double amount) {
      final userCurrencyCode =
          CurrencyPreferenceService.getCurrencyPreferenceSync();
      return CurrencyFormatter.formatCompactPdfSafe(
        amount,
        countryCode: userCurrencyCode,
      );
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in");

      // Fetch all expense data for this team
      final querySnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .where('TeamId', isEqualTo: widget.teamId)
          .get();

      final rawDocs = querySnapshot.docs.map((doc) {
        return {...doc.data(), 'id': doc.id};
      }).toList();

      final expandedPayments = ExpenseExpansionHelper.expandExpenses(
        rawDocs,
        maxDate: DateTime.now(),
      );

      if (expandedPayments.isEmpty) {
        _showMessage("No expense history found for this team.");
        setState(() => _isDownloading = false);
        return;
      }

      // Sort payments by date (ascending for chronological order in PDF)
      expandedPayments.sort((a, b) {
        final rawA = a['Date'] ?? a['date'];
        final rawB = b['Date'] ?? b['date'];
        final Timestamp? dateA = rawA is Timestamp ? rawA : null;
        final Timestamp? dateB = rawB is Timestamp ? rawB : null;
        if (dateA == null || dateB == null) return 0;
        return dateA.compareTo(dateB);
      });

      // Generate PDF
      final pdf = pw.Document();
      double totalAmount = 0;

      // Map Firestore data to PDF table rows
      final List<List<String>> tableData = expandedPayments
          .map((data) {
            final amount = double.tryParse(data['Amount'].toString()) ?? 0.0;
            totalAmount += amount;

            final rawDate = data['Date'] ?? data['date'];
            final date = rawDate is Timestamp
                ? rawDate.toDate()
                : DateTime.now();
            final dateStr = "${date.day}/${date.month}/${date.year}";

            final title = data['Title']?.toString() ?? 'Unknown';
            final memberName = data['TeamMemberName']?.toString();
            final category = data['Category']?.toString() ?? '';

            String details = title;
            if (memberName != null && memberName.isNotEmpty) {
              details = "$title ($memberName)";
            } else if (category.isNotEmpty) {
              details = "$title - $category";
            }

            // Format bank account
            String paymentMethod = _getBankAccountDisplay(data);

            return [
              dateStr,
              details,
              paymentMethod,
              getPdfCurrencySymbol(amount),
            ];
          })
          .cast<List<String>>()
          .toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // PDF Header
              pw.Header(
                level: 0,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "TEAM EXPENSE REPORT",
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      "Team: ${widget.teamName}",
                      style: const pw.TextStyle(
                        fontSize: 16,
                        color: PdfColors.grey700,
                      ),
                    ),
                    if (widget.monthlyBudget != null &&
                        widget.monthlyBudget! > 0)
                      pw.Text(
                        "Monthly Budget: ${getPdfCurrencySymbol(widget.monthlyBudget!)}",
                        style: const pw.TextStyle(
                          fontSize: 14,
                          color: PdfColors.grey700,
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // PDF Table
              pw.TableHelper.fromTextArray(
                headers: ['Date', 'Details', 'Payment Method', 'Amount'],
                data: tableData,
                border: null,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey800,
                ),
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerRight,
                },
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  ),
                ),
              ),
              pw.SizedBox(height: 20),

              // PDF Summary
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "Total Expenses: ${expandedPayments.length}",
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      "Total Amount: ${getPdfCurrencySymbol(totalAmount)}",
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ];
          },
        ),
      );

      // Print / Share / Download the PDF
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: '${widget.teamName.replaceAll(' ', '_')}_Expenses.pdf',
      );
    } catch (e) {
      _showMessage("Error generating expense history: $e");
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.appBackground,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: context.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: Stack(
        children: [
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: context.isDarkMode
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // 1. Header
                  _buildHeader(context),

                  // 2. Content with StreamBuilder
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('expenses')
                          .where('uid', isEqualTo: currentUser?.uid)
                          .where('TeamId', isEqualTo: widget.teamId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: context.textSecondary,
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              "Error loading expense history.",
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: Colors.redAccent,
                              ),
                            ),
                          );
                        }

                        // Extract raw docs and expand recurring expenses
                        final allDocs = snapshot.data?.docs ?? [];
                        final rawList = allDocs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return {...data, 'id': doc.id};
                        }).toList();

                        // Expand recurring/subscription expenses into individual
                        // occurrences up to today so every past payment is visible.
                        final expanded = ExpenseExpansionHelper.expandExpenses(
                          rawList,
                          maxDate: DateTime.now(),
                        );

                        List<Map<String, dynamic>> teamExpenses = [];
                        double totalSpent = 0.0;

                        for (var data in expanded) {
                          if (data['isFunding'] == true) continue;

                          final String title = data['Title']?.toString() ?? '';
                          final String memberName =
                              data['TeamMemberName']?.toString() ?? '';

                          final Timestamp? rawDate =
                              data['Date'] as Timestamp? ??
                              data['date'] as Timestamp?;

                          final double amt =
                              (data['Amount'] as num?)?.toDouble() ??
                              double.tryParse(
                                data['amount']?.toString() ?? '0',
                              ) ??
                              0.0;

                          totalSpent += amt;
                          teamExpenses.add({
                            "id": data['id'] ?? data['expenseId'] ?? '',
                            "rawData": data,
                            "rawDate": rawDate,
                            "date": _formatDate(rawDate),
                            "amt": _formatCurrency(amt),
                            "status": "Completed",
                            "title": title,
                            "subtitle": memberName.isNotEmpty
                                ? memberName
                                : null,
                          });
                        }

                        // Sort newest first
                        teamExpenses.sort((a, b) {
                          final Timestamp? dateA = a["rawDate"];
                          final Timestamp? dateB = b["rawDate"];
                          if (dateA == null || dateB == null) return 0;
                          return dateB.compareTo(dateA);
                        });

                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              Text(
                                "Expense History",
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textPrimary,
                                  fontSize: 28, // Compact Hero
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1.0,
                                ),
                              ),
                              const SizedBox(height: 24),

                              // --- SUMMARY CARD ---
                              _buildSummaryCard(
                                teamExpenses.length,
                                totalSpent,
                              ),

                              const SizedBox(height: 32),

                              // --- EXPENSE LIST ---
                              if (teamExpenses.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 40),
                                  child: Center(
                                    child: Text(
                                      "No team expenses yet.\nClick '+' to add an expense for this team.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Satoshi',
                                        color: context.textSecondary,
                                        height: 1.5,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                _buildExpenseList(teamExpenses, context),

                              const SizedBox(height: 40),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading Overlay
          if (_isDownloading)
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: CircularProgressIndicator(color: context.textPrimary),
              ),
            ),
        ],
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

          // Export Button
          GestureDetector(
            onTap: _downloadPaymentHistory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.textPrimary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: _isDownloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.appBackground,
                      ),
                    )
                  : Row(
                      children: [
                        Icon(
                          Icons.download,
                          color: context.appBackground,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Export",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.appBackground,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(int expenseCount, double totalSpent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TOTAL SPENT (ALL TIME)",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _formatCurrency(totalSpent),
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              fontFeatures: [
                const FontFeature.enable('liga'),
                const FontFeature.enable('clig'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF30D158).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  expenseCount == 0
                      ? "No expenses yet"
                      : "$expenseCount expense(s) logged",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: const Color(0xFF30D158),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseList(
    List<Map<String, dynamic>> expenses,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("ALL EXPENSES"),
        const SizedBox(height: 16),
        Column(
          children: expenses.map((expense) {
            final hasSubtitle = expense['subtitle'] != null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TransactionDetailsScreen(
                        transactionId: expense['id'],
                        transactionData: expense['rawData'],
                        formattedDate: expense['date'],
                        formattedAmount: expense['amt'],
                        displayTitle: expense['title'],
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
                    borderRadius: BorderRadius.circular(16),
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
                              color: context.textPrimary.withValues(
                                alpha: 0.05,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.arrow_outward,
                              color: context.textSecondary,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                expense['title'],
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (hasSubtitle) ...[
                                Text(
                                  expense['subtitle'],
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: context.textSecondary,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                expense['date'],
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            expense['amt'],
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [
                                const FontFeature.enable('liga'),
                                const FontFeature.enable('clig'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF30D158,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              expense['status'],
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: const Color(0xFF30D158),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
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

  String _getBankAccountDisplay(Map<String, dynamic> transactionData) {
    final bankAccountId =
        transactionData['bankAccount'] as String? ??
        transactionData['BankAccount'] as String?;

    if (bankAccountId != null) {
      if (bankAccountId == 'Cash-' || bankAccountId == 'Cash') {
        return 'Cash';
      }

      if (bankAccountId.contains('-')) {
        final parts = bankAccountId.split('-');
        if (parts.length >= 2) {
          final bankName = parts[0];
          final rawLast4 = parts[1];
          final last4 = rawLast4.isNotEmpty
              ? BankAccountService.extractLast4(rawLast4)
              : '';
          return last4.isNotEmpty ? '$bankName ****$last4' : bankName;
        }
      }

      return bankAccountId.replaceAll(RegExp(r'[^\w\s\-\.\*]'), '');
    }

    final paymentMethod = transactionData['PaymentMethod'] as String?;
    if (paymentMethod == 'cash') {
      return 'Cash';
    }

    return 'Not specified';
  }
}
