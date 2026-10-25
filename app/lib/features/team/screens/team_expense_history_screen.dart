import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'transaction_details_screen.dart';
import '../../../../services/currency_formatter.dart';
import '../../../../services/currency_preference_service.dart';
import '../../../../services/bank_account_service.dart';
import '../../../../utils/expense_expansion_helper.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';

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
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showMessage(String message) => showRxToast(context, message);

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              RxTopBar(
                title: 'Expense history',
                trailing: RxCircleButton(
                  icon: HugeIcons.strokeRoundedDownload04,
                  semanticLabel: 'Export as PDF',
                  onTap: _isDownloading ? null : _downloadPaymentHistory,
                ),
              ),
              if (_isDownloading)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: rx.textPrimary,
                  backgroundColor: Colors.transparent,
                ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('expenses')
                      .where('uid', isEqualTo: currentUser?.uid)
                      .where('TeamId', isEqualTo: widget.teamId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: const [
                          RxSkeleton(height: 92, radius: 22),
                          SizedBox(height: 24),
                          RxSkeleton(height: 260, radius: 22),
                        ],
                      );
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: RxEmptyState(
                          icon: HugeIcons.strokeRoundedAlert02,
                          title: "Couldn't load expenses",
                          message: 'Go back and try again',
                        ),
                      );
                    }

                    final rawList = (snapshot.data?.docs ?? []).map((doc) {
                      return {
                        ...doc.data() as Map<String, dynamic>,
                        'id': doc.id,
                      };
                    }).toList();
                    // Recurring entries expand into one row per past payment.
                    final expanded = ExpenseExpansionHelper.expandExpenses(
                      rawList,
                      maxDate: DateTime.now(),
                    );

                    double totalSpent = 0;
                    final items = <Map<String, dynamic>>[];
                    for (final data in expanded) {
                      if (data['isFunding'] == true) continue;
                      final title = data['Title']?.toString() ?? '';
                      final memberName =
                          data['TeamMemberName']?.toString() ?? '';
                      final rawDate =
                          data['Date'] as Timestamp? ??
                          data['date'] as Timestamp?;
                      final amt =
                          (data['Amount'] as num?)?.toDouble() ??
                          double.tryParse(data['amount']?.toString() ?? '0') ??
                          0.0;
                      totalSpent += amt;
                      items.add({
                        "id": data['id'] ?? data['expenseId'] ?? '',
                        "rawData": data,
                        "rawDate": rawDate,
                        "date": _formatDate(rawDate),
                        "amt": _formatCurrency(amt),
                        "title": title,
                        "category": (data['Category'] ?? 'others').toString(),
                        "subtitle": memberName.isNotEmpty ? memberName : null,
                      });
                    }
                    items.sort((a, b) {
                      final da = a["rawDate"] as Timestamp?;
                      final db = b["rawDate"] as Timestamp?;
                      if (da == null || db == null) return 0;
                      return db.compareTo(da);
                    });

                    if (items.isEmpty) {
                      return const Center(
                        child: RxEmptyState(
                          icon: HugeIcons.strokeRoundedInvoice01,
                          title: 'No team expenses yet',
                          message:
                              'Tag an expense with this team to see it here',
                        ),
                      );
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
                          child: _buildSummary(items.length, totalSpent),
                        ),
                        const SizedBox(height: 28),
                        RxReveal.index(
                          1,
                          child: Column(
                            children: [
                              RxSectionHeader(title: widget.teamName),
                              RxCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: Column(
                                  children: [
                                    for (var i = 0; i < items.length; i++) ...[
                                      if (i > 0) const RxDivider(indent: 52),
                                      _buildRow(items[i]),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildSummary(int count, double total) {
    final rx = context.rx;
    final budget = widget.monthlyBudget ?? 0;
    Widget half(String label, String value) => Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: RxText.label(context)),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: RxText.value(context, size: 20)),
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
            half('Total spent', _formatCurrency(total)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(width: 1, color: rx.hairline),
            ),
            budget > 0
                ? half('Monthly budget', _formatCurrency(budget))
                : half('Expenses', '$count'),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> e) {
    final category = e['category'] as String;
    final subtitle = [
      if (e['subtitle'] != null) e['subtitle'] as String,
      e['date'] as String,
    ].join(' · ');
    return RxPressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionDetailsScreen(
            transactionId: e['id'],
            transactionData: e['rawData'],
            formattedDate: e['date'],
            formattedAmount: e['amt'],
            displayTitle: e['title'],
          ),
        ),
      ),
      scale: 0.98,
      semanticLabel: '${e['title']}, $subtitle, ${e['amt']}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            RxIconTile(
              icon: RxCategory.icon(category),
              size: 40,
              iconSize: 19,
              background: RxCategory.soft(context, category),
              foreground: RxCategory.color(context, category),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (e['title'] as String).isEmpty
                        ? 'Expense'
                        : e['title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RxText.body(context),
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
            Text(e['amt'] as String, style: RxText.amount(context)),
          ],
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
