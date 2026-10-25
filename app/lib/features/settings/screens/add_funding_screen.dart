import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/expense_service.dart';
import '../../../services/financial_calculator.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';

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

  void _showMinimalToast(String message, {bool isError = false}) =>
      showRxToast(context, message, isError: isError);

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

      // Funding transaction, funding row, optional EMI schedule and the
      // company total are written in a single atomic batch.
      await ExpenseService().recordFunding(
        uid: user.uid,
        companyId: user.uid,
        amount: amount,
        previousFunding: _currentFunding,
        sourceLabel: sourceLabel,
        sourceKey: _selectedSource,
        notes: _notesController.text.trim(),
        targetRunway: _updateTargetRunway
            ? _targetRunwayController.text.trim()
            : null,
        loan: isBankLoan
            ? {
                'isBankLoan': true,
                'loanLenderBank': loanLenderBank,
                'loanInterestRate': loanInterestRate,
                'loanRateType': loanRateType,
                'loanTenureMonths': loanTenureMonths,
                'loanEmiAmount': loanEmiAmount,
                'loanEmiStartDate': Timestamp.fromDate(_selectedEmiDate),
              }
            : null,
        emiAmount: isBankLoan ? loanEmiAmount : null,
        emiStartDate: isBankLoan ? _selectedEmiDate : null,
      );

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

  static const Map<String, List<List<dynamic>>> _sourceIcons = {
    'self_funded': HugeIcons.strokeRoundedUser,
    'bank_loan': HugeIcons.strokeRoundedBank,
    'angel_investor': HugeIcons.strokeRoundedFavourite,
    'vc_funding': HugeIcons.strokeRoundedRocket01,
    'grant': HugeIcons.strokeRoundedAward01,
    'revenue': HugeIcons.strokeRoundedChartIncrease,
    'other': HugeIcons.strokeRoundedMoreHorizontal,
  };

  bool _err(String field) => _errorFields.contains(field);

  void _selectSource(String key) {
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
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final symbol = CurrencyFormatter.getCurrencySymbol(_userCountryCode);
    final hasPrefill =
        widget.prefillData != null && widget.prefillData!.isNotEmpty;

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Add funding'),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    if (hasPrefill) ...[
                      RxPill(
                        label: 'Pre-filled from your scan. Check before saving',
                        dot: true,
                        foreground: rx.textSecondary,
                        background: rx.surfaceMuted,
                      ),
                      const SizedBox(height: 16),
                    ],
                    RxReveal.index(
                      0,
                      child: Column(
                        children: [
                          RxAmountInput(
                            controller: _amountController,
                            symbol: symbol,
                            label: 'Amount',
                            onChanged: (_) {
                              if (_err("ADD FUNDING AMOUNT")) {
                                setState(
                                  () =>
                                      _errorFields.remove("ADD FUNDING AMOUNT"),
                                );
                              }
                            },
                          ),
                          if (_err("ADD FUNDING AMOUNT"))
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Enter an amount',
                                style: RxText.caption(
                                  context,
                                  color: rx.negative,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          // Before and after, so the effect is obvious.
                          RxCard(
                            padding: EdgeInsets.zero,
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  _metric(
                                    'Current funding',
                                    CurrencyFormatter.formatByCountryCompact(
                                      _currentFunding,
                                      _userCountryCode,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Container(
                                      width: 1,
                                      color: rx.hairline,
                                    ),
                                  ),
                                  _metric(
                                    'New total',
                                    CurrencyFormatter.formatByCountryCompact(
                                      _currentFunding + _inputAmount,
                                      _userCountryCode,
                                    ),
                                    color: _inputAmount > 0
                                        ? rx.positive
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Source'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final src in _fundingSources)
                                _sourceChip(src, rx),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_selectedSource == 'bank_loan') ...[
                      const SizedBox(height: 28),
                      _buildLoanSection(symbol, rx),
                    ],
                    const SizedBox(height: 28),
                    RxReveal.index(
                      2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RxTextInput(
                            controller: _notesController,
                            label: 'Notes',
                            hint: 'e.g. Seed round from XYZ Ventures',
                            maxLines: 3,
                            onChanged: (_) {
                              if (_err("NOTES")) {
                                setState(() => _errorFields.remove("NOTES"));
                              }
                            },
                          ),
                          if (_err("NOTES")) _fieldError('Add a short note'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Planning'),
                          RxCard(
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                            child: RxSwitchRow(
                              title: 'Update target runway',
                              subtitle:
                                  'Current: ${_currentTargetRunway.isNotEmpty ? '$_currentTargetRunway months' : 'not set'}',
                              value: _updateTargetRunway,
                              onChanged: (v) =>
                                  setState(() => _updateTargetRunway = v),
                            ),
                          ),
                          if (_updateTargetRunway) ...[
                            const SizedBox(height: 12),
                            RxTextInput(
                              controller: _targetRunwayController,
                              hint: 'e.g. 18',
                              icon: HugeIcons.strokeRoundedTarget02,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textInputAction: TextInputAction.done,
                              suffix: Text(
                                'months',
                                style: RxText.caption(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: 'Add funding',
                  icon: HugeIcons.strokeRoundedMoneyReceive01,
                  loading: _isLoading,
                  onTap: _validateAndSaveFunding,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {Color? color}) => Expanded(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: RxText.label(context)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: RxText.value(context, size: 18, color: color),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fieldError(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 6),
    child: Text(
      text,
      style: RxText.caption(context, color: context.rx.negative),
    ),
  );

  Widget _sourceChip(Map<String, dynamic> src, RxColors rx) {
    final key = src['key'] as String;
    final selected = _selectedSource == key;
    return Semantics(
      button: true,
      selected: selected,
      label: src['label'] as String,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _selectSource(key);
        },
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 14),
          decoration: BoxDecoration(
            color: selected ? rx.inverse : rx.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected ? Colors.transparent : rx.hairline,
            ),
            boxShadow: selected ? null : rx.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: _sourceIcons[key] ?? HugeIcons.strokeRoundedMoney01,
                color: selected ? rx.onInverse : rx.textSecondary,
                size: 16,
                strokeWidth: 1.9,
              ),
              const SizedBox(width: 6),
              Text(
                src['label'] as String,
                style: RxText.label(
                  context,
                  color: selected ? rx.onInverse : rx.textPrimary,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoanSection(String symbol, RxColors rx) {
    void clear(String f) {
      if (_err(f)) setState(() => _errorFields.remove(f));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RxSectionHeader(title: 'Loan details'),
        RxTextInput(
          controller: _lenderBankController,
          label: 'Lender',
          hint: 'e.g. HDFC Bank',
          icon: HugeIcons.strokeRoundedBank,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => clear("LENDER BANK NAME"),
        ),
        if (_err("LENDER BANK NAME")) _fieldError('Enter the lender'),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RxTextInput(
                    controller: _interestController,
                    label: 'Interest',
                    hint: '10.5',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: RxTextInput.money,
                    suffix: Text('% p.a.', style: RxText.caption(context)),
                    onChanged: (_) => clear("INTEREST RATE (% P.A.)"),
                  ),
                  if (_err("INTEREST RATE (% P.A.)")) _fieldError('Required'),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RxTextInput(
                    controller: _tenureController,
                    label: 'Tenure',
                    hint: '36',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    suffix: Text('months', style: RxText.caption(context)),
                    onChanged: (_) => clear("TENURE (MONTHS)"),
                  ),
                  if (_err("TENURE (MONTHS)")) _fieldError('Required'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Interest type',
            style: RxText.label(context).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        RxSegmented<String>(
          options: const {'reducing': 'Reducing', 'flat': 'Flat'},
          value: _loanRateType,
          onChanged: (v) {
            setState(() => _loanRateType = v);
            _recalculateEmi();
          },
        ),
        const SizedBox(height: 16),
        RxTextInput(
          controller: _emiController,
          label: 'Monthly EMI',
          hint: '0',
          prefixText: symbol,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: RxTextInput.money,
          helper: _userEditedEmi
              ? 'Edited by you'
              : 'Calculated from amount, interest and tenure',
          onChanged: (_) {
            _userEditedEmi = true;
            clear("EMI AMOUNT");
          },
        ),
        if (_err("EMI AMOUNT")) _fieldError('Enter the EMI'),
        if (_userEditedEmi)
          Align(
            alignment: Alignment.centerRight,
            child: RxPressable(
              onTap: () => setState(() {
                _userEditedEmi = false;
                _recalculateEmi();
              }),
              semanticLabel: 'Use calculated EMI',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedRefresh,
                      color: rx.textSecondary,
                      size: 14,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Use calculated EMI',
                      style: RxText.caption(
                        context,
                        color: rx.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        RxDateField(
          label: 'First EMI date',
          value: _selectedEmiDate,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
          onChanged: (d) => setState(() => _selectedEmiDate = d),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6),
          child: Text(
            'A monthly EMI expense is added from this date.',
            style: RxText.caption(context),
          ),
        ),
      ],
    );
  }
}
