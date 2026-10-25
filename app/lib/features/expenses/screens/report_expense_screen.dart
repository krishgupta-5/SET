import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:startup_expense_tracker/widgets/rx_ui.dart';
import 'package:startup_expense_tracker/widgets/rx_charts.dart';
import 'package:startup_expense_tracker/widgets/rx_motion.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../utils/data_helpers.dart';
import '../../../utils/expense_expansion_helper.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/bank_account_service.dart';
import '../../../theme/app_theme.dart';

class ReportExpenseScreen extends StatefulWidget {
  const ReportExpenseScreen({super.key});

  @override
  State<ReportExpenseScreen> createState() => _ReportExpenseScreenState();
}

class _ReportExpenseScreenState extends State<ReportExpenseScreen> {
  String _selectedPeriod = "weekly";

  DateTime? _customStartDate;
  DateTime? _customEndDate;

  bool _isDownloading = false;
  String _userCountryCode = '+1'; // Default to USD
  bool _isLoadingCountry = true;

  final ScrollController _scrollController = ScrollController();
  final ScrollController _categoryScrollController = ScrollController();
  final ValueNotifier<String> _categoryNotifier = ValueNotifier<String>("all");

  @override
  void initState() {
    super.initState();
    // Get currency preference synchronously for instant display
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    // Listen for currency changes
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _loadUserCountryCode();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _categoryScrollController.dispose();
    _categoryNotifier.dispose();
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
    if (mounted) {
      setState(() {
        _userCountryCode = currencyCode;
        _isLoadingCountry = false;
      });
    }
  }

  String _formatCurrency(double amount) {
    return _isLoadingCountry
        ? CurrencyFormatter.formatByCountryCompact(amount, '+1')
        : CurrencyFormatter.formatByCountryCompact(amount, _userCountryCode);
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  String _formatShortDate(DateTime date) {
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
    return "${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}";
  }

  String _formatMonthYear(DateTime date) {
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
    return "${months[date.month - 1]} '${date.year.toString().substring(2)}";
  }

  // --- UNIFIED MINIMAL TOAST ---
  void _showMinimalToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? context.rx.negative : context.rx.positive,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Geist',
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

  void _showShadCalendar({required bool isStart}) {
    DateTime initialDate = isStart
        ? (_customStartDate ?? DateTime.now())
        : (_customEndDate ?? _customStartDate ?? DateTime.now());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        DateTime tempSelectedDate = initialDate;

        return Dialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.borderColor),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isStart ? "Select Start Date" : "Select End Date",
                      style: TextStyle(
                        fontFamily: 'Geist',
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: context.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ShadCalendar(
                  selected: tempSelectedDate,
                  fromMonth: DateTime(DateTime.now().year - 5),
                  toMonth: DateTime(DateTime.now().year + 5, 12),
                  onChanged: (DateTime? date) {
                    if (date != null) {
                      tempSelectedDate = date;
                    }
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        if (isStart) {
                          _customStartDate = tempSelectedDate;
                          if (_customEndDate != null &&
                              _customEndDate!.isBefore(_customStartDate!)) {
                            _customEndDate = null;
                          }
                        } else {
                          _customEndDate = tempSelectedDate;
                        }
                        if (_customStartDate != null &&
                            _customEndDate != null) {
                          _selectedPeriod = "custom";
                        }
                      });
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.textPrimary,
                      foregroundColor: context.appBackground,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "Done",
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- UPDATED DYNAMIC PDF EXPORT LOGIC ---
  Future<void> _exportReport() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMinimalToast("Error: User not logged in.", isError: true);
      return;
    }

    setState(() => _isDownloading = true);

    // PDF-safe currency formatter: Unicode symbols may not render in the
    // default PDF font, so we use ASCII-safe fallbacks for ALL currencies.
    String getPdfCurrencySymbol(double amount) {
      return CurrencyFormatter.formatCompactPdfSafe(amount);
    }

    // Resolve bank account display name from raw Firestore value.
    // Handles both stable-ID lookups and legacy "BankName-Last4" format.
    String resolveBankAccountDisplay(
      String rawValue,
      Map<String, String> idToName,
    ) {
      if (rawValue.isEmpty) return 'Not specified';

      // 1. Try stable ID lookup first
      if (idToName.containsKey(rawValue)) {
        return idToName[rawValue]!;
      }

      // 2. Handle Cash special values
      if (rawValue == 'Cash-' || rawValue == 'Cash') {
        return 'Cash';
      }

      // 3. Parse legacy "BankName-Last4" format
      if (rawValue.contains('-')) {
        final parts = rawValue.split('-');
        if (parts.length >= 2) {
          final bankName = parts.sublist(0, parts.length - 1).join('-');
          final rawLast4 = parts.last;
          final last4 = rawLast4.isNotEmpty
              ? BankAccountService.extractLast4(rawLast4)
              : '';
          return last4.isNotEmpty ? '$bankName ****$last4' : bankName;
        }
      }

      // 4. Return as-is (cleaned for PDF safety)
      return rawValue.replaceAll(RegExp(r'[^\w\s\-\.\*]'), '');
    }

    try {
      DateTime now = DateTime.now();
      DateTime startDate;
      DateTime endDate = now;

      // 1. Calculate matching date range
      if (_selectedPeriod == "weekly") {
        startDate = now.subtract(const Duration(days: 6));
      } else if (_selectedPeriod == "monthly") {
        startDate = now.subtract(const Duration(days: 29));
      } else if (_selectedPeriod == "quarterly") {
        startDate = now.subtract(const Duration(days: 89));
      } else if (_selectedPeriod == "yearly") {
        startDate = now.subtract(const Duration(days: 364));
      } else if (_selectedPeriod == "custom" &&
          _customStartDate != null &&
          _customEndDate != null) {
        startDate = _customStartDate!;
        endDate = _customEndDate!;
      } else {
        startDate = now.subtract(const Duration(days: 6));
      }

      // Normalize to full days
      startDate = DateTime(startDate.year, startDate.month, startDate.day);
      endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

      int daysInPeriod = endDate.difference(startDate).inDays;
      if (daysInPeriod <= 0) daysInPeriod = 1;

      final selectedCategory = _categoryNotifier.value;

      // 2. Fetch from Firestore
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

      // 3. Aggregate Data for the PDF
      List<Map<String, dynamic>> filteredData = [];
      double totalAmount = 0;
      Map<String, double> categoryBreakdown = {};

      bool isDailyChart = daysInPeriod <= 31;
      Map<String, double> trendData = {};

      // Fetch bank accounts for reference
      final bankAccounts = await BankAccountService.getBankAccounts();
      final Map<String, String> bankAccountNames = {};
      for (var account in bankAccounts) {
        final id = account['id']?.toString() ?? '';
        final name = account['name']?.toString() ?? 'Unknown Bank';
        final last4 = account['last4']?.toString() ?? '****';
        bankAccountNames[id] = '$name ****$last4';
      }

      // Initialize trend data timeline
      if (isDailyChart) {
        for (int i = 0; i <= daysInPeriod; i++) {
          DateTime d = startDate.add(Duration(days: i));
          trendData[_formatShortDate(d)] = 0.0;
        }
      } else {
        DateTime tempDate = DateTime(startDate.year, startDate.month, 1);
        while (tempDate.isBefore(endDate) ||
            tempDate.isAtSameMomentAs(
              DateTime(endDate.year, endDate.month, 1),
            )) {
          trendData[_formatMonthYear(tempDate)] = 0.0;
          tempDate = DateTime(tempDate.year, tempDate.month + 1, 1);
        }
      }

      // Sort expanded expenses descending by date
      expanded.sort((a, b) {
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

      // Filter and Sort Firestore Data
      for (final data in expanded) {
        if (data['isFunding'] == true) continue;

        final category = (data['Category']?.toString() ?? 'other')
            .toLowerCase();

        if (selectedCategory != "all" && category != selectedCategory) {
          continue;
        }

        final amount = DataHelpers.safeParseDouble(data['Amount']);
        final isFunding = data['isFunding'] == true || category == 'funding';

        final dateVal = data['Date'] ?? data['date'];
        DateTime docDate;
        if (dateVal is Timestamp) {
          docDate = dateVal.toDate();
        } else if (dateVal is DateTime) {
          docDate = dateVal;
        } else {
          docDate = now;
        }

        if (docDate.isBefore(startDate) || docDate.isAfter(endDate)) {
          continue;
        }

        // Only count expenses (not funding) in totals
        if (!isFunding) {
          totalAmount += amount;
          categoryBreakdown[category] =
              (categoryBreakdown[category] ?? 0.0) + amount;
        }

        // Add to Trend
        String trendKey = isDailyChart
            ? _formatShortDate(docDate)
            : _formatMonthYear(docDate);
        if (!isFunding && trendData.containsKey(trendKey)) {
          trendData[trendKey] = trendData[trendKey]! + amount;
        }

        // Add to List
        final bankAccountId =
            data['bankAccount']?.toString() ??
            data['BankAccount']?.toString() ??
            '';
        final bankAccountName = resolveBankAccountDisplay(
          bankAccountId,
          bankAccountNames,
        );

        filteredData.add({
          'Date': docDate,
          'Title': data['Title'] ?? 'Unknown',
          'Category': category,
          'Amount': amount,
          'BankAccount': bankAccountName,
          'isFunding': isFunding,
        });
      }

      if (filteredData.isEmpty) {
        _showMinimalToast(
          "No expenses found for this specific period and category.",
          isError: true,
        );
        setState(() => _isDownloading = false);
        return;
      }

      double averageDaily = totalAmount / daysInPeriod;

      // 4. Build PDF Layout
      final pdf = pw.Document();
      final String subtitle =
          "Period: ${_formatDate(startDate)} to ${_formatDate(endDate)} | Filter: ${selectedCategory.toUpperCase()}";

      // Prepare Category Table Data
      var sortedCategories = categoryBreakdown.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final List<List<String>> categoryTableData = sortedCategories.map((e) {
        double pct = totalAmount > 0 ? e.value / totalAmount : 0;
        String displayCat = e.key.isEmpty ? "OTHER" : e.key.toUpperCase();
        return [
          displayCat,
          getPdfCurrencySymbol(e.value),
          "${(pct * 100).toStringAsFixed(1)}%",
        ];
      }).toList();

      // Prepare Trend Table Data (Filter out 0 values to keep it clean)
      final List<List<String>> trendTableData = trendData.entries
          .where((e) => e.value > 0)
          .map((e) => [e.key, getPdfCurrencySymbol(e.value)])
          .toList();

      // Build transactions table manually for per-row funding color support

      // Helper to build a single table cell
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

      // Build transaction rows with per-row green for funding
      final List<pw.TableRow> transactionRows = [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
          children: ['Date', 'Title', 'Category', 'Bank Account', 'Amount']
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
        // Data rows
        ...filteredData.map((data) {
          final isFunding =
              data['isFunding'] == true ||
              (data['Category']?.toString().toLowerCase() == 'funding');
          final amount = DataHelpers.safeParseDouble(data['Amount']);
          final amountStr = getPdfCurrencySymbol(amount);
          final displayAmount = isFunding ? '+$amountStr' : amountStr;
          final bankAccountDisplay =
              data['BankAccount']?.toString() ?? 'Not specified';
          final rowColor = isFunding
              ? const PdfColor(0.16, 0.55, 0.25) // green700
              : PdfColors.black;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isFunding
                  ? const PdfColor(0.91, 0.98, 0.92) // light green tint
                  : null,
              border: const pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              ),
            ),
            children: [
              buildCell(_formatDate(data['Date']), textColor: rowColor),
              buildCell(data['Title'].toString(), textColor: rowColor),
              buildCell(
                data['Category'].toString().toUpperCase(),
                textColor: rowColor,
              ),
              buildCell(bankAccountDisplay, textColor: rowColor),
              buildCell(
                displayAmount,
                alignment: pw.Alignment.centerRight,
                textColor: isFunding
                    ? const PdfColor(0.13, 0.55, 0.13) // green
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
              // HEADER
              pw.Header(
                level: 0,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "EXPENSE REPORT",
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      subtitle,
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // SUMMARY SECTION
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          "TOTAL EXPENSES",
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          getPdfCurrencySymbol(totalAmount),
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red800,
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      width: 1,
                      height: 30,
                      color: PdfColors.grey400,
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          "AVERAGE DAILY",
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          getPdfCurrencySymbol(averageDaily),
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.green800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // CATEGORY BREAKDOWN SECTION
              pw.Text(
                "CATEGORY BREAKDOWN",
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey800,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ['Category', 'Amount', 'Percentage'],
                data: categoryTableData,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey600,
                ),
                cellHeight: 25,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 30),

              // TREND SECTION
              if (trendTableData.isNotEmpty) ...[
                pw.Text(
                  "SPENDING TREND",
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey800,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  headers: ['Period', 'Total Spent'],
                  data: trendTableData,
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey600,
                  ),
                  cellHeight: 25,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerRight,
                  },
                ),
                pw.SizedBox(height: 30),
              ],

              // DETAILED TRANSACTIONS SECTION
              pw.Text(
                "DETAILED TRANSACTIONS",
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey800,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                columnWidths: {
                  0: const pw.FixedColumnWidth(70),
                  1: const pw.FlexColumnWidth(2.5),
                  2: const pw.FixedColumnWidth(80),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FixedColumnWidth(100),
                },
                children: transactionRows,
              ),
            ];
          },
        ),
      );

      // 5. Present the PDF
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name:
            'Report_${_selectedPeriod}_${_formatDate(now).replaceAll('/', '-')}.pdf',
      );
    } catch (e) {
      _showMinimalToast("Error generating report: $e", isError: true);
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  // Builds a Firestore stream filtered to the currently selected period
  // so we don't download every expense document on every rebuild.
  Stream<QuerySnapshot> _buildExpenseStream(String? uid) {
    DateTime now = DateTime.now();
    DateTime startDate;
    DateTime endDate = now;

    if (_selectedPeriod == 'weekly') {
      startDate = now.subtract(const Duration(days: 6));
    } else if (_selectedPeriod == 'monthly') {
      startDate = now.subtract(const Duration(days: 29));
    } else if (_selectedPeriod == 'quarterly') {
      startDate = now.subtract(const Duration(days: 89));
    } else if (_selectedPeriod == 'yearly') {
      startDate = now.subtract(const Duration(days: 364));
    } else if (_selectedPeriod == 'custom' &&
        _customStartDate != null &&
        _customEndDate != null) {
      startDate = _customStartDate!;
      endDate = _customEndDate!;
    } else {
      startDate = now.subtract(const Duration(days: 6));
    }

    startDate = DateTime(startDate.year, startDate.month, startDate.day);
    endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    return FirebaseFirestore.instance
        .collection('expenses')
        .where('uid', isEqualTo: uid)
        .snapshots();
  }

  // --- PREMIUM SECTION LABEL HELPER ---
  // Sentence-case field labels, like the rest of the redesign.
  Widget _buildSectionLabel(String text) {
    final t = text.isEmpty
        ? text
        : text[0].toUpperCase() + text.substring(1).toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        t,
        style: RxText.label(context).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _buildExpenseStream(currentUser?.uid),
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
                              "Failed to load reports.",
                              style: TextStyle(
                                fontFamily: 'Geist',
                                color: Colors.redAccent,
                              ),
                            ),
                          );
                        }

                        DateTime now = DateTime.now();
                        DateTime startDate;
                        DateTime endDate = now;

                        if (_selectedPeriod == "weekly") {
                          startDate = now.subtract(const Duration(days: 6));
                        } else if (_selectedPeriod == "monthly") {
                          startDate = now.subtract(const Duration(days: 29));
                        } else if (_selectedPeriod == "quarterly") {
                          startDate = now.subtract(const Duration(days: 89));
                        } else if (_selectedPeriod == "yearly") {
                          startDate = now.subtract(const Duration(days: 364));
                        } else if (_selectedPeriod == "custom" &&
                            _customStartDate != null &&
                            _customEndDate != null) {
                          startDate = _customStartDate!;
                          endDate = _customEndDate!;
                        } else {
                          startDate = now.subtract(const Duration(days: 6));
                        }

                        startDate = DateTime(
                          startDate.year,
                          startDate.month,
                          startDate.day,
                        );
                        endDate = DateTime(
                          endDate.year,
                          endDate.month,
                          endDate.day,
                          23,
                          59,
                          59,
                        );

                        int daysInPeriod = endDate.difference(startDate).inDays;
                        if (daysInPeriod <= 0) daysInPeriod = 1;

                        bool isDailyChart = daysInPeriod <= 31;
                        Map<String, double> chartData = {};
                        List<String> chartLabels = [];

                        // --- FORCE ONLY LAST 7 DAYS IN DAILY CHART ---
                        if (isDailyChart) {
                          int displayDays = min(
                            daysInPeriod,
                            6,
                          ); // 0 to 6 = 7 days
                          DateTime chartStartDate = endDate.subtract(
                            Duration(days: displayDays),
                          );

                          for (int i = 0; i <= displayDays; i++) {
                            DateTime d = chartStartDate.add(Duration(days: i));
                            String key =
                                "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                            chartData[key] = 0.0;
                            chartLabels.add(_formatShortDate(d));
                          }
                        } else {
                          DateTime tempDate = DateTime(
                            startDate.year,
                            startDate.month,
                            1,
                          );
                          while (tempDate.isBefore(endDate) ||
                              tempDate.isAtSameMomentAs(
                                DateTime(endDate.year, endDate.month, 1),
                              )) {
                            String key =
                                "${tempDate.year}-${tempDate.month.toString().padLeft(2, '0')}";
                            chartData[key] = 0.0;
                            chartLabels.add(_formatMonthYear(tempDate));
                            tempDate = DateTime(
                              tempDate.year,
                              tempDate.month + 1,
                              1,
                            );
                          }
                        }

                        return ValueListenableBuilder<String>(
                          valueListenable: _categoryNotifier,
                          builder: (context, selectedCategory, child) {
                            double totalExpenses = 0.0;
                            Map<String, double> categoryBreakdown = {};
                            Map<String, double> tempChartData = Map.from(
                              chartData,
                            );

                            final docs = snapshot.data?.docs ?? [];
                            final rawList = docs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return {...data, 'id': doc.id};
                            }).toList();

                            final expanded =
                                ExpenseExpansionHelper.expandExpenses(
                                  rawList,
                                  maxDate: endDate,
                                );

                            for (final data in expanded) {
                              if (data['isFunding'] == true) continue;

                              final dateVal = data['Date'] ?? data['date'];
                              DateTime docDate;
                              if (dateVal is Timestamp) {
                                docDate = dateVal.toDate();
                              } else if (dateVal is DateTime) {
                                docDate = dateVal;
                              } else {
                                docDate = now;
                              }

                              final String category =
                                  (data['Category']?.toString() ?? 'other')
                                      .toLowerCase();

                              final double amount = DataHelpers.safeParseDouble(
                                data['Amount'],
                              );

                              if (docDate.isBefore(startDate) ||
                                  docDate.isAfter(endDate)) {
                                continue;
                              }
                              if (selectedCategory != "all" &&
                                  category != selectedCategory) {
                                continue;
                              }

                              totalExpenses += amount;
                              categoryBreakdown[category] =
                                  (categoryBreakdown[category] ?? 0.0) + amount;

                              if (isDailyChart) {
                                String key =
                                    "${docDate.year}-${docDate.month.toString().padLeft(2, '0')}-${docDate.day.toString().padLeft(2, '0')}";
                                if (tempChartData.containsKey(key)) {
                                  tempChartData[key] =
                                      tempChartData[key]! + amount;
                                }
                              } else {
                                String key =
                                    "${docDate.year}-${docDate.month.toString().padLeft(2, '0')}";
                                if (tempChartData.containsKey(key)) {
                                  tempChartData[key] =
                                      tempChartData[key]! + amount;
                                }
                              }
                            }

                            double averageDaily =
                                totalExpenses /
                                (daysInPeriod == 0 ? 1 : daysInPeriod);

                            // Changes whenever a filter does, so charts
                            // replay their entrance for the new data.
                            final filterKey =
                                '$_selectedPeriod|$selectedCategory|${startDate.millisecondsSinceEpoch}|${endDate.millisecondsSinceEpoch}';

                            return SingleChildScrollView(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 16),
                                  Text(
                                    "Expense Report",
                                    style: TextStyle(
                                      fontFamily: 'Geist',
                                      color: context.textPrimary,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  _buildPeriodSelector(),
                                  const SizedBox(height: 24),
                                  _buildDateRangePicker(),
                                  const SizedBox(height: 24),
                                  _buildCategoryFilter(),
                                  const SizedBox(height: 32),
                                  // Nothing in range: one quiet line instead
                                  // of empty ₹0 cards and a blank chart.
                                  if (totalExpenses <= 0)
                                    RxReveal(
                                      key: ValueKey('empty-$filterKey'),
                                      child: _buildNoDataNote(),
                                    )
                                  else ...[
                                    RxReveal(
                                      key: ValueKey('sum-$filterKey'),
                                      child: _buildSummaryCards(
                                        totalExpenses,
                                        averageDaily,
                                      ),
                                    ),
                                    const SizedBox(height: 32),
                                    RxReveal(
                                      key: ValueKey('chart-$filterKey'),
                                      delay: const Duration(milliseconds: 60),
                                      child: _buildChartSection(
                                        tempChartData.values.toList(),
                                        chartLabels,
                                        isDailyChart,
                                        filterKey,
                                      ),
                                    ),
                                    const SizedBox(height: 32),
                                    RxReveal(
                                      key: ValueKey('cat-$filterKey'),
                                      delay: const Duration(milliseconds: 120),
                                      child: _buildDetailedBreakdown(
                                        categoryBreakdown,
                                        totalExpenses,
                                        filterKey,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 40),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              // Loader Overlay
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
    return RxTopBar(
      title: '',
      trailing: RxCircleButton(
        icon: HugeIcons.strokeRoundedDownload04,
        semanticLabel: 'Export report',
        onTap: () => _exportReport(),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("REPORT PERIOD"),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildPeriodChip("Weekly", "weekly"),
              const SizedBox(width: 12),
              _buildPeriodChip("Monthly", "monthly"),
              const SizedBox(width: 12),
              _buildPeriodChip("Quarterly", "quarterly"),
              const SizedBox(width: 12),
              _buildPeriodChip("Yearly", "yearly"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodChip(String label, String value) {
    bool isSelected = _selectedPeriod == value;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedPeriod = value;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? context.textPrimary : context.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? context.textPrimary : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Geist',
            color: isSelected ? context.appBackground : context.textSecondary,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildDateRangePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("CUSTOM DATE RANGE"),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _showShadCalendar(isStart: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: context.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                    boxShadow: context.cardShadow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _customStartDate != null
                            ? _formatDate(_customStartDate!)
                            : "Start Date",
                        style: TextStyle(
                          fontFamily: 'Geist',
                          color: _customStartDate != null
                              ? context.textPrimary
                              : context.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Icon(
                        Icons.calendar_today,
                        color: context.textSecondary,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _showShadCalendar(isStart: false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: context.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                    boxShadow: context.cardShadow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _customEndDate != null
                            ? _formatDate(_customEndDate!)
                            : "End Date",
                        style: TextStyle(
                          fontFamily: 'Geist',
                          color: _customEndDate != null
                              ? context.textPrimary
                              : context.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Icon(
                        Icons.calendar_today,
                        color: context.textSecondary,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    final categories = [
      "All",
      "Salary",
      "Infrastructure",
      "Software",
      "Office",
      "Marketing",
      "Meals",
      "Transport",
      "Others",
    ];
    return ValueListenableBuilder<String>(
      valueListenable: _categoryNotifier,
      builder: (context, selectedCategory, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel("CATEGORY FILTER"),
            const SizedBox(height: 12),
            SingleChildScrollView(
              controller: _categoryScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: categories.map((category) {
                  bool isSelected = selectedCategory == category.toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        _categoryNotifier.value = category.toLowerCase();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? context.textPrimary
                              : context.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? context.textPrimary
                                : context.borderColor,
                          ),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            fontFamily: 'Geist',
                            color: isSelected
                                ? context.appBackground
                                : context.textSecondary,
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(double total, double averageDaily) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("SUMMARY"),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                "Total Expenses",
                _formatCurrency(total),
                Icons.account_balance_wallet,
                context.rx.negative,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                "Average Daily",
                _formatCurrency(averageDaily),
                Icons.show_chart,
                context.rx.positive,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    color: context.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // FIXED: FITTED BOX FOR LARGE NUMBERS
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Geist',
                color: context.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- NO DATA ---
  // A plain line, no card: there is nothing to box up.
  Widget _buildNoDataNote() {
    // Sits in a card under the filters, where the summary and chart would
    // be, so the page keeps its shape.
    return const RxCard(
      padding: EdgeInsets.zero,
      child: RxEmptyState(
        icon: HugeIcons.strokeRoundedChartBarLine,
        title: 'No expenses in this period',
        message: 'Try a different period, date range or category',
        padding: EdgeInsets.fromLTRB(20, 36, 20, 36),
      ),
    );
  }

  // --- TREND BARS ---
  // Bars grow up from the axis in a left-to-right cascade, and replay
  // whenever a filter changes. The tallest bar is highlighted.
  Widget _buildChartSection(
    List<double> data,
    List<String> labels,
    bool isDailyChart,
    String filterKey,
  ) {
    if (data.isEmpty) return const SizedBox.shrink();
    final maxVal = data.reduce(max);
    if (maxVal <= 0) return const SizedBox.shrink();

    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final peakColor = isDark ? rx.accent : rx.inverse;
    final peakIndex = data.indexOf(maxVal);
    const chartHeight = 130.0;
    final step = 420 ~/ data.length.clamp(6, 60);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          isDailyChart ? "EXPENSE TREND (LAST 7 DAYS)" : "EXPENSE TREND",
        ),
        const SizedBox(height: 16),
        RxCard(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(data.length, (index) {
              final value = data[index];
              final pct = (value / maxVal).clamp(0.0, 1.0);
              final isPeak = index == peakIndex;
              final labelParts = labels[index].split(' ');

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 16,
                        child: value > 0
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  CurrencyFormatter.formatByCountryCompact(
                                    value,
                                    _isLoadingCountry ? '+1' : _userCountryCode,
                                  ),
                                  style: RxText.micro(
                                    context,
                                    color: isPeak
                                        ? rx.textPrimary
                                        : rx.textTertiary,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: chartHeight,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: RxGrow(
                            key: ValueKey('rbar-$filterKey-$index'),
                            value: pct,
                            delay: Duration(milliseconds: step * index),
                            builder: (context, v) => Container(
                              constraints: const BoxConstraints(maxWidth: 30),
                              width: double.infinity,
                              // Empty days keep a stub so the axis reads.
                              height: (chartHeight * v).clamp(4.0, chartHeight),
                              decoration: BoxDecoration(
                                color: isPeak
                                    ? peakColor
                                    : rx.textPrimary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          labelParts[0],
                          style: RxText.micro(
                            context,
                            color: rx.textPrimary,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (labelParts.length > 1)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            labelParts[1],
                            style: RxText.micro(context),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // --- CATEGORY BREAKDOWN ---
  // Donut on top, rows below with a share track that fills in.
  Widget _buildDetailedBreakdown(
    Map<String, double> breakdown,
    double total,
    String filterKey,
  ) {
    final sortedEntries = breakdown.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sortedEntries.isEmpty || total <= 0) return const SizedBox.shrink();

    final rx = context.rx;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("CATEGORY BREAKDOWN"),
        const SizedBox(height: 16),
        RxCard(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
          child: Column(
            children: [
              RxDonut(
                key: ValueKey('rdonut-$filterKey'),
                size: 168,
                thickness: 16,
                segments: [
                  for (final e in sortedEntries)
                    RxDonutSegment(
                      value: e.value,
                      color: RxCategory.color(context, e.key),
                    ),
                ],
                trackColor: rx.textPrimary.withValues(alpha: 0.06),
                semanticLabel: 'Spending by category',
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total', style: RxText.caption(context)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatCurrency(total),
                        style: RxText.value(context, size: 20),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${sortedEntries.length} ${sortedEntries.length == 1 ? 'category' : 'categories'}',
                      style: RxText.micro(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < sortedEntries.length; i++) ...[
                if (i > 0) const RxDivider(indent: 22),
                _buildBreakdownRow(
                  sortedEntries[i].key,
                  _formatCurrency(sortedEntries[i].value),
                  sortedEntries[i].value / total,
                  filterKey,
                  i,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownRow(
    String categoryKey,
    String amount,
    double percentage,
    String filterKey,
    int index,
  ) {
    final rx = context.rx;
    final color = RxCategory.color(context, categoryKey);
    final name = categoryKey.isEmpty
        ? 'Other'
        : categoryKey[0].toUpperCase() + categoryKey.substring(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RxText.body(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(amount, style: RxText.amount(context)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${(percentage * 100).toStringAsFixed(1)}% of spend',
                  style: RxText.caption(context),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Container(
                          color: rx.textPrimary.withValues(alpha: 0.07),
                        ),
                        RxGrow(
                          key: ValueKey('rtrack-$filterKey-$categoryKey'),
                          value: percentage.clamp(0.02, 1.0),
                          delay: Duration(milliseconds: 150 + 60 * index),
                          builder: (context, v) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: v,
                            child: Container(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
