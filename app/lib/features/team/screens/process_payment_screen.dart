import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../services/bank_account_service.dart';
import '../../../services/expense_service.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';

class ProcessPaymentScreen extends StatefulWidget {
  final String memberId;
  final String memberName;
  final String teamId;
  final String teamName;
  final double defaultAmount;
  final bool isAdvance;

  const ProcessPaymentScreen({
    super.key,
    required this.memberId,
    required this.memberName,
    required this.teamId,
    required this.teamName,
    required this.defaultAmount,
    required this.isAdvance,
  });

  @override
  State<ProcessPaymentScreen> createState() => _ProcessPaymentScreenState();
}

class _ProcessPaymentScreenState extends State<ProcessPaymentScreen> {
  late final TextEditingController _amountController;
  late final TextEditingController _reasonController;

  bool _isLoading = false;
  String _userCountryCode = '+1';

  Map<String, String> _bankAccounts = {};
  String? _selectedBankAccount;
  String _selectedPaymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _amountController = TextEditingController(
      text: widget.defaultAmount.toStringAsFixed(2),
    );
    _reasonController = TextEditingController();
    _fetchBankAccounts();
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _amountController.dispose();
    _reasonController.dispose();
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

  void _error(String message) => showRxToast(context, message, isError: true);

  Future<void> _fetchBankAccounts() async {
    try {
      final accounts = await BankAccountService.getBankAccounts();
      final Map<String, String> loaded = {};
      for (final acc in accounts) {
        final String name = acc['name'] as String? ?? 'Unknown Bank';
        String last4 = acc['last4'] as String? ?? '';
        if (last4.isEmpty || last4 == '****') {
          final rawNum = acc['number']?.toString() ?? '';
          if (rawNum.isNotEmpty) {
            last4 = rawNum.length <= 4
                ? rawNum
                : rawNum.substring(rawNum.length - 4);
          }
        }
        loaded["$name-$last4"] = last4.isNotEmpty && last4 != '****'
            ? "$name (****$last4)"
            : name;
      }
      if (mounted) {
        setState(() {
          _bankAccounts = loaded;
          if (_bankAccounts.isNotEmpty) {
            _selectedBankAccount = _bankAccounts.keys.first;
            _selectedPaymentMethod = 'bank';
          }
        });
      }
    } catch (e) {
      debugPrint("Failed to load bank accounts: $e");
    }
  }

  // --- FIREBASE LOGIC (unchanged) ---

  Future<void> _processPayment() async {
    FocusScope.of(context).unfocus();
    final amount = CurrencyFormatter.parse(_amountController.text.trim());

    if (amount == null || amount <= 0) {
      return _error("Please enter a valid amount.");
    }
    if (widget.isAdvance && _reasonController.text.trim().isEmpty) {
      return _error("Please provide a reason for the advance.");
    }
    if (_selectedPaymentMethod == 'bank' && _selectedBankAccount == null) {
      return _error("Please select a bank account to pay from.");
    }

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User is not logged in.");

      final title = widget.isAdvance
          ? "Advance Salary - ${widget.memberName}"
          : "Salary - ${widget.memberName}";
      final desc = widget.isAdvance
          ? "Advance reason: ${_reasonController.text.trim()}"
          : "Regular monthly salary payout for ${widget.memberName}";
      final account = _selectedPaymentMethod == 'bank'
          ? (_selectedBankAccount ?? 'Cash-')
          : 'Cash-';

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final companyId =
          (userDoc.data()?['companyId'] as String?) ?? user.uid;

      // Expense row + company/member counters in one atomic batch.
      await ExpenseService().recordSalaryPayment(
        uid: user.uid,
        companyId: companyId,
        memberId: widget.memberId,
        memberName: widget.memberName,
        teamId: widget.teamId,
        teamName: widget.teamName,
        amount: amount,
        title: title,
        description: desc,
        // Bank key (BankName-last4) or 'Cash-' for cash payments.
        bankAccount: account,
        paymentMethod: _selectedPaymentMethod,
      );

      if (mounted) {
        showRxToast(
          context,
          widget.isAdvance ? "Advance recorded" : "Salary payment recorded",
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Payment failed: $e");
      if (mounted) _error("Payment failed. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final symbol = CurrencyFormatter.getCurrencySymbol(_userCountryCode);

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              RxTopBar(title: widget.isAdvance ? 'Advance pay' : 'Pay salary'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    RxReveal.index(
                      0,
                      child: Column(
                        children: [
                          RxAmountInput(
                            controller: _amountController,
                            symbol: symbol,
                            label: widget.isAdvance
                                ? 'Advance amount'
                                : 'Amount',
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'To ${widget.memberName}${widget.teamName.isNotEmpty ? ' · ${widget.teamName}' : ''}',
                            textAlign: TextAlign.center,
                            style: RxText.caption(context),
                          ),
                          if (widget.isAdvance) ...[
                            const SizedBox(height: 12),
                            RxPill(
                              label: 'Paid before the due date',
                              dot: true,
                              foreground: rx.warning,
                              background: rx.warningSoft,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    RxReveal.index(
                      1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8),
                            child: Text(
                              'Pay with',
                              style: RxText.label(
                                context,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          RxSegmented<String>(
                            options: const {'bank': 'Bank', 'cash': 'Cash'},
                            value: _selectedPaymentMethod,
                            onChanged: (v) =>
                                setState(() => _selectedPaymentMethod = v),
                          ),
                          if (_selectedPaymentMethod == 'bank') ...[
                            const SizedBox(height: 16),
                            if (_bankAccounts.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  'No bank accounts yet. Add one in Funds, or pay with cash.',
                                  style: RxText.caption(context),
                                ),
                              )
                            else
                              RxSelectField<String>(
                                label: 'From account',
                                value: _selectedBankAccount,
                                icon: HugeIcons.strokeRoundedBank,
                                options: [
                                  for (final e in _bankAccounts.entries)
                                    RxOption(e.key, e.value),
                                ],
                                onChanged: (v) =>
                                    setState(() => _selectedBankAccount = v),
                              ),
                          ],
                          if (widget.isAdvance) ...[
                            const SizedBox(height: 16),
                            RxTextInput(
                              controller: _reasonController,
                              label: 'Reason for advance',
                              hint: 'e.g. Medical emergency',
                              maxLines: 3,
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
                  label: widget.isAdvance ? 'Record advance' : 'Record payment',
                  icon: HugeIcons.strokeRoundedMoneySend01,
                  loading: _isLoading,
                  onTap: _processPayment,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
