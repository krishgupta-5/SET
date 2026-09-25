import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../services/currency_preference_service.dart';
import '../../../../services/currency_formatter.dart';
import '../../../../services/bank_account_service.dart';
import '../../../../utils/expense_expansion_helper.dart';
import '../../../../theme/app_theme.dart';

class ExpensesExportScreen extends StatefulWidget {
  const ExpensesExportScreen({super.key});

  @override
  State<ExpensesExportScreen> createState() => _ExpensesExportScreenState();
}

class _ExpensesExportScreenState extends State<ExpensesExportScreen> {
  bool _isDownloading = false;

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
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

    return 'N/A';
  }

  void _showMinimalToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError
                  ? const Color(0xFFFF453A)
                  : const Color(0xFF30D158),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.cardBackground,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 0,
      ),
    );
  }

  Future<void> _downloadReport(String reportType) async {
    setState(() => _isDownloading = true);

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

      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate;
      String reportTitle = "";

      if (reportType == "Monthly") {
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        reportTitle =
            "Monthly Expenses - ${_getMonthName(now.month)} ${now.year}";
      } else if (reportType == "Quarterly") {
        final currentQuarter = ((now.month - 1) ~/ 3) + 1;
        final startMonth = (currentQuarter - 1) * 3 + 1;
        startDate = DateTime(now.year, startMonth, 1);
        final endMonth = startMonth + 2;
        final endYear = endMonth > 12 ? now.year + 1 : now.year;
        final safeEndMonth = endMonth > 12 ? endMonth - 12 : endMonth;
        endDate = DateTime(endYear, safeEndMonth + 1, 0, 23, 59, 59);
        reportTitle = "Quarterly Expenses - Q$currentQuarter ${now.year}";
      } else {
        final isNewFY = now.month >= 4;
        final startYear = isNewFY ? now.year : now.year - 1;
        startDate = DateTime(startYear, 4, 1);
        endDate = DateTime(startYear + 1, 3, 31, 23, 59, 59);
        reportTitle =
            "Annual Expenses - FY $startYear-${(startYear + 1).toString().substring(2)}";
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .get();

      final mappedExpenses = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id};
      }).toList();

      final expanded = ExpenseExpansionHelper.expandExpenses(
        mappedExpenses,
        maxDate: endDate,
      );

      final expenses = expanded.where((data) {
        final dateVal = data['Date'] ?? data['date'];
        DateTime? dt;
        if (dateVal is Timestamp) {
          dt = dateVal.toDate();
        } else if (dateVal is DateTime) {
          dt = dateVal;
        }
        if (dt == null) return false;
        return dt.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();

      expenses.sort((a, b) {
        final aDateVal = a['Date'] ?? a['date'];
        final bDateVal = b['Date'] ?? b['date'];
        DateTime? aDt = aDateVal is Timestamp
            ? aDateVal.toDate()
            : aDateVal as DateTime?;
        DateTime? bDt = bDateVal is Timestamp
            ? bDateVal.toDate()
            : bDateVal as DateTime?;
        if (aDt == null && bDt == null) return 0;
        if (aDt == null) return 1;
        if (bDt == null) return -1;
        return bDt.compareTo(aDt);
      });

      if (expenses.isEmpty) {
        _showMinimalToast("No expenses found for this period.", isError: true);
        setState(() => _isDownloading = false);
        return;
      }

      final pdf = pw.Document();
      double totalAmount = 0;

      pw.Widget buildCell(
        String text, {
        pw.Alignment alignment = pw.Alignment.centerLeft,
        PdfColor? textColor,
        pw.FontWeight fontWeight = pw.FontWeight.normal,
      }) {
        return pw.Container(
          height: 30,
          alignment: alignment,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 10,
              color: textColor ?? PdfColors.black,
              fontWeight: fontWeight,
            ),
          ),
        );
      }

      final List<pw.TableRow> tableRows = [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
          children: ['Date', 'Title', 'Category', 'Account', 'Amount']
              .asMap()
              .entries
              .map((entry) {
                return buildCell(
                  entry.value,
                  alignment: entry.key == 4
                      ? pw.Alignment.centerRight
                      : pw.Alignment.centerLeft,
                  textColor: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                );
              })
              .toList(),
        ),
        ...expenses.map((data) {
          final amount = double.tryParse(data['Amount'].toString()) ?? 0.0;
          final category = data['Category']?.toString().toLowerCase() ?? '';
          final isFunding = data['isFunding'] == true || category == 'funding';
          if (!isFunding) {
            totalAmount += amount;
          }

          final dateVal = data['Date'] ?? data['date'];
          final DateTime date = dateVal is Timestamp
              ? dateVal.toDate()
              : dateVal as DateTime;
          final dateStr = "${date.day}/${date.month}/${date.year}";
          final amountStr = getPdfCurrencySymbol(amount);
          final displayAmount = isFunding ? '+$amountStr' : amountStr;
          final rowColor = isFunding
              ? const PdfColor(0.16, 0.55, 0.25)
              : PdfColors.black;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isFunding ? const PdfColor(0.91, 0.98, 0.92) : null,
              border: const pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              ),
            ),
            children: [
              buildCell(dateStr, textColor: rowColor),
              buildCell(
                data['Title']?.toString() ?? 'Unknown',
                textColor: rowColor,
              ),
              buildCell(
                data['Category']?.toString().toUpperCase() ?? 'N/A',
                textColor: rowColor,
              ),
              buildCell(_getBankAccountDisplay(data), textColor: rowColor),
              buildCell(
                displayAmount,
                alignment: pw.Alignment.centerRight,
                textColor: isFunding
                    ? const PdfColor(0.13, 0.55, 0.13)
                    : PdfColors.black,
                fontWeight: isFunding
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ],
          );
        }),
      ];

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "EXPENSE REPORT",
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      reportTitle,
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Table(
                columnWidths: {
                  0: const pw.FixedColumnWidth(70),
                  1: const pw.FlexColumnWidth(2.5),
                  2: const pw.FixedColumnWidth(80),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FixedColumnWidth(100),
                },
                children: tableRows,
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  "Total: ${getPdfCurrencySymbol(totalAmount)}",
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: '${reportTitle.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      _showMinimalToast("Error generating report.", isError: true);
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();

    final String currentMonthYear = "${_getMonthName(now.month)} ${now.year}";
    final int currentQuarter = ((now.month - 1) ~/ 3) + 1;
    final String currentQuarterStr = "Q$currentQuarter ${now.year}";
    final bool isNewFY = now.month >= 4;
    final int startYear = isNewFY ? now.year : now.year - 1;
    final String currentFY =
        "FY $startYear-${(startYear + 1).toString().substring(2)}";

    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
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
                            "Downloads",
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
                            "Download and manage your expense reports",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 40),

                          _buildSectionLabel("AVAILABLE EXPENSE REPORTS"),

                          _buildStatementCard(
                            title: "Monthly Expenses",
                            period: currentMonthYear,
                            description:
                                "Download detailed expense breakdown for $currentMonthYear",
                            icon: Icons.receipt_long,
                            onTap: () => _downloadReport("Monthly"),
                          ),
                          const SizedBox(height: 16),

                          _buildStatementCard(
                            title: "Quarterly Expenses",
                            period: currentQuarterStr,
                            description:
                                "Comprehensive quarterly spending analysis",
                            icon: Icons.pie_chart_outline,
                            onTap: () => _downloadReport("Quarterly"),
                          ),
                          const SizedBox(height: 16),

                          _buildStatementCard(
                            title: "Annual Expense Summary",
                            period: currentFY,
                            description:
                                "Complete annual overview of all expenses",
                            icon: Icons.summarize,
                            onTap: () => _downloadReport("Annual"),
                          ),

                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              if (_isDownloading)
                Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
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
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildStatementCard({
    required String title,
    required String period,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final iconBg = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
          boxShadow: context.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Icon(icon, color: context.iconSecondary, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        period,
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Icon(
                    Icons.download,
                    color: context.textPrimary,
                    size: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              description,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
