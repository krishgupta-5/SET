import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/financial_calculator.dart';
import '../../../theme/app_theme.dart';

class AddFundingScreen extends StatefulWidget {
  final Map<String, String>? prefillData;
  final String? imagePath;

  const AddFundingScreen({super.key, this.prefillData, this.imagePath});

  @override
  State<AddFundingScreen> createState() => _AddFundingScreenState();
}

class _AddFundingScreenState extends State<AddFundingScreen> {
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  late final ScrollController _scrollController;

  bool _isLoading = false;
  String _userCountryCode = '+1';

  final TextEditingController _targetRunwayController = TextEditingController();
  final TextEditingController _lenderBankController = TextEditingController();
  final TextEditingController _interestController = TextEditingController();
  final TextEditingController _tenureController = TextEditingController();
  final TextEditingController _emiController = TextEditingController();

  String _loanRateType = 'reducing';
  bool _userEditedEmi = false;
  DateTime _selectedEmiDate = DateTime.now().add(const Duration(days: 30));

  bool _updateTargetRunway = false;
  String _selectedSource = 'self_funded';

  double _currentFunding = 0.0;
  double _inputAmount = 0.0;
  String _currentTargetRunway = '';

  final Set<String> _errorFields = {};

  final List<Map<String, dynamic>> _fundingSources = [
    {
      'key': 'self_funded',
      'label': 'Self Funded',
      'icon': Icons.person_outline,
    },
    {
      'key': 'bank_loan',
      'label': 'Bank Loan',
      'icon': Icons.account_balance_outlined,
    },
    {
      'key': 'angel_investor',
      'label': 'Angel Investor',
      'icon': Icons.favorite_outline,
    },
    {
      'key': 'vc_funding',
      'label': 'VC Funding',
      'icon': Icons.rocket_launch_outlined,
    },
    {
      'key': 'grant',
      'label': 'Grant',
      'icon': Icons.workspace_premium_outlined,
    },
    {'key': 'revenue', 'label': 'Revenue', 'icon': Icons.trending_up},
    {'key': 'other', 'label': 'Other', 'icon': Icons.more_horiz},
  ];

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _loadUserCountryCode();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _scrollController = ScrollController();
    _loadCurrentData();

    final p = widget.prefillData;
    _amountController = TextEditingController(text: p?['amount'] ?? '');
    _notesController.text = p?['description'] ?? '';

    _amountController.addListener(() {
      setState(() {
        _inputAmount =
            double.tryParse(
              _amountController.text.replaceAll(RegExp(r'[^\d.]'), ''),
            ) ??
            0.0;
      });
      if (_selectedSource == 'bank_loan') _recalculateEmi();
    });

    _interestController.addListener(() {
      if (_selectedSource == 'bank_loan') _recalculateEmi();
    });

    _tenureController.addListener(() {
      if (_selectedSource == 'bank_loan') _recalculateEmi();
    });
  }

  void _loadUserCountryCode() {
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
  }

  void _onCurrencyChanged() {
    if (mounted) {
      setState(() {
        _userCountryCode =
            CurrencyPreferenceService.getCurrencyPreferenceSync();
      });
    }
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _amountController.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    _targetRunwayController.dispose();
    _interestController.dispose();
    _tenureController.dispose();
    _emiController.dispose();
    _lenderBankController.dispose();
    super.dispose();
  }

  void _recalculateEmi() {
    if (_userEditedEmi) return;

    final principal = _inputAmount;
    final rate = double.tryParse(_interestController.text) ?? 0.0;
    final tenure = int.tryParse(_tenureController.text) ?? 0;

    double emi = 0.0;
    if (_loanRateType == 'flat') {
      emi = FinancialCalculator.calculateFlatRateEmi(principal, rate, tenure);
    } else {
      emi = FinancialCalculator.calculateReducingRateEmi(
        principal,
        rate,
        tenure,
      );
    }

    if (emi > 0) {
      _emiController.text = emi.toStringAsFixed(2);
    } else {
      _emiController.text = '';
    }
  }

  Future<void> _loadCurrentData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(user.uid)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _currentFunding = _toDouble(data['Funding'] ?? data['funding'] ?? 0);
          _currentTargetRunway = data['Target Runway']?.toString() ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading current data: $e');
    }
  }

  double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(RegExp(r'[^\d.-]'), '')) ??
          fallback;
    }
    return fallback;
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
        duration: const Duration(seconds: 4),
        elevation: 0,
      ),
    );
  }

  Future<void> _validateAndSaveFunding() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _errorFields.clear();
      if (_inputAmount <= 0) _errorFields.add("ADD FUNDING AMOUNT");
      if (_notesController.text.trim().isEmpty) _errorFields.add("NOTES");

      if (_selectedSource == 'bank_loan') {
        final rateVal = double.tryParse(_interestController.text) ?? 0.0;
        final tenureVal = int.tryParse(_tenureController.text) ?? 0;
        final emiVal =
            double.tryParse(
              _emiController.text.replaceAll(RegExp(r'[^\d.]'), ''),
            ) ??
            0.0;

        if (_lenderBankController.text.trim().isEmpty) {
          _errorFields.add("LENDER BANK NAME");
        }
        if (rateVal <= 0) _errorFields.add("INTEREST RATE (% P.A.)");
        if (tenureVal <= 0) _errorFields.add("TENURE (MONTHS)");
        if (emiVal <= 0) _errorFields.add("EMI AMOUNT");
      }
    });

    if (_errorFields.isNotEmpty) {
      _showMinimalToast("Please fill out all required fields", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final amount = _inputAmount;
      final sourceMap = _fundingSources.firstWhere(
        (s) => s['key'] == _selectedSource,
      );
      final sourceLabel = sourceMap['label'] as String;
      final newTotalFunding = _currentFunding + amount;
      final now = DateTime.now();

      final isBankLoan = _selectedSource == 'bank_loan';
      final loanLenderBank = isBankLoan
          ? _lenderBankController.text.trim()
          : null;
      final loanInterestRate = isBankLoan
          ? (double.tryParse(_interestController.text) ?? 0.0)
          : null;
      final loanRateType = isBankLoan ? _loanRateType : null;
      final loanTenureMonths = isBankLoan
          ? (int.tryParse(_tenureController.text) ?? 0)
          : null;
      final loanEmiAmount = isBankLoan
          ? (double.tryParse(
                  _emiController.text.replaceAll(RegExp(r'[^\d.]'), ''),
                ) ??
                0.0)
          : null;

      await FirebaseFirestore.instance.collection('funding_transactions').add({
        'uid': user.uid,
        'amount': amount,
        'source': sourceLabel,
        'sourceKey': _selectedSource,
        'notes': _notesController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'previousFunding': _currentFunding,
        'newTotalFunding': newTotalFunding,
        if (isBankLoan) ...{
          'isBankLoan': true,
          'loanLenderBank': loanLenderBank,
          'loanInterestRate': loanInterestRate,
          'loanRateType': loanRateType,
          'loanTenureMonths': loanTenureMonths,
          'loanEmiAmount': loanEmiAmount,
          'loanEmiStartDate': Timestamp.fromDate(_selectedEmiDate),
        },
      });

      final expenseId = const Uuid().v4();
      await FirebaseFirestore.instance
          .collection('expenses')
          .doc(expenseId)
          .set({
            'uid': user.uid,
            'Amount': amount,
            'Title': 'Funding: $sourceLabel',
            'Description': _notesController.text.trim(),
            'Date': Timestamp.fromDate(now),
            'Category': 'funding',
            'Type': 'one_time',
            'BankAccount': null,
            'AttachmentFileId': '',
            'ExpenseType': 'funding',
            'isFunding': true,
            'fundingSource': sourceLabel,
            'fundingSourceKey': _selectedSource,
            'Time': FieldValue.serverTimestamp(),
            if (isBankLoan) ...{
              'isBankLoan': true,
              'loanLenderBank': loanLenderBank,
              'loanInterestRate': loanInterestRate,
              'loanRateType': loanRateType,
              'loanTenureMonths': loanTenureMonths,
              'loanEmiAmount': loanEmiAmount,
              'loanEmiStartDate': Timestamp.fromDate(_selectedEmiDate),
            },
          });

      if (isBankLoan && loanEmiAmount != null && loanEmiAmount > 0) {
        final emiExpenseId = const Uuid().v4();
        await FirebaseFirestore.instance
            .collection('expenses')
            .doc(emiExpenseId)
            .set({
              'uid': user.uid,
              'companyId': user.uid,
              'Amount': loanEmiAmount,
              'Title': 'EMI: $loanLenderBank Loan Repayment',
              'Description':
                  'Monthly EMI repayment for $loanLenderBank loan of amount $amount',
              'Date': Timestamp.fromDate(_selectedEmiDate),
              'Category': 'others',
              'Type': 'recurring',
              'BankAccount': null,
              'AttachmentFileId': '',
              'ExpenseType': 'others',
              'isFunding': false,
              'isEmiRepayment': true,
              'loanLenderBank': loanLenderBank,
              'loanInterestRate': loanInterestRate,
              'loanRateType': loanRateType,
              'loanTenureMonths': loanTenureMonths,
              'loanEmiStartDate': Timestamp.fromDate(_selectedEmiDate),
              'Time': FieldValue.serverTimestamp(),
            });
      }

      final Map<String, dynamic> updateData = {'Funding': newTotalFunding};

      if (_updateTargetRunway &&
          _targetRunwayController.text.trim().isNotEmpty) {
        updateData['Target Runway'] = _targetRunwayController.text.trim();
      }

      await FirebaseFirestore.instance
          .collection('companies')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      if (mounted) {
        _showMinimalToast("Funding added successfully!");
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showMinimalToast(
          "Error adding funding: ${e.toString()}",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = CurrencyFormatter.getCurrencySymbol(
      _userCountryCode,
    );

    return Scaffold(
      backgroundColor: context.appBackground,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          "Add Funding",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(height: 32),

                        if (widget.prefillData != null &&
                            widget.prefillData!.isNotEmpty)
                          _buildPrefillBanner(),

                        Row(
                          children: [
                            Expanded(
                              child: _buildReadOnlyMetric(
                                "CURRENT FUNDING",
                                CurrencyFormatter.formatByCountryCompact(
                                  _currentFunding,
                                  _userCountryCode,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildReadOnlyMetric(
                                "NEW TOTAL",
                                CurrencyFormatter.formatByCountryCompact(
                                  _currentFunding + _inputAmount,
                                  _userCountryCode,
                                ),
                                highlight: _inputAmount > 0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),

                        _buildAmountInput(currencySymbol),
                        const SizedBox(height: 40),

                        _buildSectionLabel("FUNDING SOURCE"),
                        _buildSourceSelector(),
                        const SizedBox(height: 40),

                        if (_selectedSource == 'bank_loan')
                          _buildBankLoanDetailsSection(),

                        _buildInputGroup(
                          "NOTES",
                          "e.g., Seed round from XYZ Ventures",
                          _notesController,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 40),

                        _buildSectionLabel("PLANNING"),
                        _buildTargetRunwaySection(),

                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildPrefillBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: context.textPrimary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Fields pre-filled from scanned receipt. Review and edit if needed.",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
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
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text, {bool hasError = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: hasError ? const Color(0xFFFF453A) : context.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildMiniSectionLabel(String text) {
    final bool hasError = _errorFields.contains(text);
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: hasError ? const Color(0xFFFF453A) : context.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildReadOnlyMetric(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: highlight ? context.textPrimary : context.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlight
                  ? context.borderColorStrong
                  : context.borderColor,
            ),
            boxShadow: context.cardShadow,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: highlight ? context.textPrimary : context.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountInput(String currencySymbol) {
    final String label = "ADD FUNDING AMOUNT";
    final bool hasError = _errorFields.contains(label);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label, hasError: hasError),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFFF453A).withValues(alpha: 0.5)
                  : context.borderColor,
            ),
            boxShadow: context.cardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                currencySymbol,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: hasError
                      ? const Color(0xFFFF453A)
                      : context.textSecondary,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onTapOutside: (event) => FocusScope.of(context).unfocus(),
                  onChanged: (_) {
                    if (hasError) setState(() => _errorFields.remove(label));
                  },
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                  cursorColor: context.textPrimary,
                  decoration: InputDecoration(
                    hintText: "0",
                    hintStyle: TextStyle(
                      fontFamily: 'Satoshi',
                      color: hasError
                          ? const Color(0xFFFF453A).withValues(alpha: 0.5)
                          : context.textTertiary,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourceSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _fundingSources.map((data) {
        final key = data['key'] as String;
        final isSelected = _selectedSource == key;
        final selectedBg = context.isDarkMode
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.08);

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedSource = key;
              if (key != 'bank_loan') {
                _userEditedEmi = false;
                _lenderBankController.clear();
                _interestController.clear();
                _tenureController.clear();
                _emiController.clear();
              } else {
                _recalculateEmi();
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? context.borderColorStrong
                    : context.borderColor,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  data['icon'] as IconData,
                  color: isSelected
                      ? context.textPrimary
                      : context.iconSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  data['label'] as String,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: isSelected
                        ? context.textPrimary
                        : context.textSecondary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBankLoanDetailsSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Container(
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
                Icon(
                  Icons.account_balance_outlined,
                  color: context.iconSecondary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  "LOAN DETAILS",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildBankLoanInputField(
              "LENDER BANK NAME",
              "e.g. HDFC Bank, Chase",
              _lenderBankController,
              isText: true,
            ),
            const SizedBox(height: 20),
            _buildEmiDatePickerRow(),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildBankLoanInputField(
                    "INTEREST RATE (% P.A.)",
                    "e.g. 10.5",
                    _interestController,
                    isDouble: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMiniSectionLabel("RATE TYPE"),
                      const SizedBox(height: 8),
                      _buildRateTypeSelector(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildBankLoanInputField(
                    "TENURE (MONTHS)",
                    "e.g. 24",
                    _tenureController,
                    isInteger: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildBankLoanInputField(
                    "EMI AMOUNT",
                    "Auto-calculated",
                    _emiController,
                    isDouble: true,
                    onChanged: (val) {
                      setState(() => _userEditedEmi = true);
                    },
                  ),
                ),
              ],
            ),
            if (_userEditedEmi) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _userEditedEmi = false;
                      _recalculateEmi();
                    });
                  },
                  icon: Icon(
                    Icons.refresh,
                    size: 14,
                    color: context.iconSecondary,
                  ),
                  label: Text(
                    "Reset to calculated EMI",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBankLoanInputField(
    String label,
    String hint,
    TextEditingController controller, {
    bool isInteger = false,
    bool isDouble = false,
    bool isText = false,
    ValueChanged<String>? onChanged,
  }) {
    final bool hasError = _errorFields.contains(label);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMiniSectionLabel(label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.appBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFFF453A).withValues(alpha: 0.5)
                  : context.borderColor,
            ),
          ),
          child: TextField(
            controller: controller,
            keyboardType: isText
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            onChanged: (val) {
              if (hasError) setState(() => _errorFields.remove(label));
              if (onChanged != null) onChanged(val);
            },
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: context.textPrimary,
            inputFormatters: [
              if (isInteger) FilteringTextInputFormatter.digitsOnly,
              if (isDouble) FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textTertiary,
                fontSize: 13,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRateTypeSelector() {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.appBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(child: _buildRateTypeButton('reducing', 'Reducing')),
          Expanded(child: _buildRateTypeButton('flat', 'Flat / Fixed')),
        ],
      ),
    );
  }

  Widget _buildRateTypeButton(String type, String label) {
    final isSelected = _loanRateType == type;
    final selectedBg = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    return GestureDetector(
      onTap: () {
        setState(() {
          _loanRateType = type;
          _recalculateEmi();
        });
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: isSelected ? context.textPrimary : context.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmiDatePickerRow() {
    final formattedDate =
        "${_selectedEmiDate.day}/${_selectedEmiDate.month}/${_selectedEmiDate.year}";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMiniSectionLabel("EMI REPAYMENT START DATE"),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showEmiDatePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: context.appBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: context.iconSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Icon(
                  Icons.edit_outlined,
                  color: context.iconSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showEmiDatePicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedEmiDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: context.isDarkMode
                ? const ColorScheme.dark(
                    primary: Colors.white,
                    onPrimary: Colors.black,
                    surface: Color(0xFF141416),
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: Colors.black,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: context.textPrimary),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedEmiDate) {
      setState(() => _selectedEmiDate = picked);
    }
  }

  Widget _buildInputGroup(
    String label,
    String hint,
    TextEditingController controller, {
    int maxLines = 1,
    bool isNumber = false,
  }) {
    final bool hasError = _errorFields.contains(label);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label, hasError: hasError),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFFF453A).withValues(alpha: 0.5)
                  : context.borderColor,
            ),
            boxShadow: context.cardShadow,
          ),
          child: TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            maxLines: maxLines,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: (_) {
              if (hasError) setState(() => _errorFields.remove(label));
            },
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: context.textPrimary,
            decoration: InputDecoration(
              hintText: hasError ? "This field is required" : hint,
              hintStyle: TextStyle(
                fontFamily: 'Satoshi',
                color: hasError
                    ? const Color(0xFFFF453A).withValues(alpha: 0.5)
                    : context.textTertiary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetRunwaySection() {
    final thumbColor = _updateTargetRunway
        ? (context.isDarkMode ? Colors.black : Colors.white)
        : context.textPrimary;
    final trackColor = _updateTargetRunway
        ? (context.isDarkMode ? Colors.white : Colors.black)
        : context.borderColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _updateTargetRunway = !_updateTargetRunway),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
              boxShadow: context.cardShadow,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Update Target Runway",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Current Target: ${_currentTargetRunway.isNotEmpty ? '$_currentTargetRunway months' : 'Not set'}",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 44,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: trackColor,
                  ),
                  child: Align(
                    alignment: _updateTargetRunway
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: thumbColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_updateTargetRunway)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
                boxShadow: context.cardShadow,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetRunwayController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: context.textPrimary,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        hintText: "Enter months (e.g., 18)",
                        hintStyle: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textTertiary,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    "months",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final btnBg = context.isDarkMode ? Colors.white : Colors.black;
    final btnText = context.isDarkMode ? Colors.black : Colors.white;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appBackground,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _validateAndSaveFunding,
          style: ElevatedButton.styleFrom(
            backgroundColor: btnBg,
            foregroundColor: btnText,
            disabledBackgroundColor: context.textTertiary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: btnText,
                  ),
                )
              : Text(
                  "Add Funding",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
