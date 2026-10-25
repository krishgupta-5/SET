import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../services/currency_preference_service.dart';
import '../../../../services/currency_formatter.dart';
import '../../../../services/bank_account_service.dart';
import '../../../../utils/expense_expansion_helper.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';

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

  void _showMinimalToast(String message, {bool isError = false}) =>
      showRxToast(context, message, isError: isError);

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
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // Which report is being generated, so only that row shows a spinner.
  String? _busyType;

  Future<void> _download(String type) async {
    if (_isDownloading) return;
    setState(() => _busyType = type);
    await _downloadReport(type);
    if (mounted) setState(() => _busyType = null);
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final now = DateTime.now();
    final month = "${_getMonthName(now.month)} ${now.year}";
    final quarter = "Q${((now.month - 1) ~/ 3) + 1} ${now.year}";
    final fyStart = now.month >= 4 ? now.year : now.year - 1;
    final fy = "FY $fyStart-${(fyStart + 1).toString().substring(2)}";

    final reports = [
      ('Monthly', HugeIcons.strokeRoundedCalendar03, 'Monthly expenses', month),
      (
        'Quarterly',
        HugeIcons.strokeRoundedCalendar01,
        'Quarterly expenses',
        quarter,
      ),
      ('Annual', HugeIcons.strokeRoundedFiles01, 'Annual summary', fy),
    ];

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Statements'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    // Document work: the default "papers" illustration.
                    RxReveal.index(
                      0,
                      child: Column(
                        children: [
                          const RxEmptyArt(
                            icon: HugeIcons.strokeRoundedFileDownload,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Download a PDF statement',
                            textAlign: TextAlign.center,
                            style: RxText.title(context).copyWith(fontSize: 22),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Every expense in the period, with category and payment method.',
                            textAlign: TextAlign.center,
                            style: RxText.caption(
                              context,
                            ).copyWith(fontSize: 14, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
                      child: Column(
                        children: [
                          const RxSectionHeader(title: 'Reports'),
                          RxCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < reports.length; i++) ...[
                                  if (i > 0) const RxDivider(indent: 64),
                                  _reportRow(
                                    type: reports[i].$1,
                                    icon: reports[i].$2,
                                    title: reports[i].$3,
                                    period: reports[i].$4,
                                    rx: rx,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportRow({
    required String type,
    required List<List<dynamic>> icon,
    required String title,
    required String period,
    required RxColors rx,
  }) {
    final busy = _busyType == type;
    return RxPressable(
      onTap: _isDownloading ? null : () => _download(type),
      semanticLabel: 'Download $title, $period',
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            RxIconTile(icon: icon, size: 38, iconSize: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: RxText.body(context)),
                  const SizedBox(height: 1),
                  Text(period, style: RxText.caption(context)),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: rx.surfaceMuted,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: rx.textPrimary,
                      ),
                    )
                  : HugeIcon(
                      icon: HugeIcons.strokeRoundedDownload04,
                      color: rx.textPrimary,
                      size: 17,
                      strokeWidth: 2,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
