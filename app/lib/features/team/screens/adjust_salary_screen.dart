import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../services/currency_formatter.dart';
import '../../../services/currency_preference_service.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';

class AdjustSalaryScreen extends StatefulWidget {
  final String memberId;
  final double currentSalary;

  const AdjustSalaryScreen({
    super.key,
    required this.memberId,
    required this.currentSalary,
  });

  @override
  State<AdjustSalaryScreen> createState() => _AdjustSalaryScreenState();
}

class _AdjustSalaryScreenState extends State<AdjustSalaryScreen> {
  late TextEditingController _salaryController;
  late TextEditingController _reasonController;

  DateTime _effectiveDate = DateTime.now();
  bool _isLoading = false;
  String _userCountryCode = '+1';

  static const _reasons = [
    'Performance raise',
    'Promotion',
    'Annual review',
    'Market adjustment',
    'Role change',
  ];

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _salaryController = TextEditingController(
      text: widget.currentSalary.toStringAsFixed(0),
    )..addListener(() => setState(() {}));
    _reasonController = TextEditingController(text: "Performance raise")
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    CurrencyPreferenceService.currencyNotifier.removeListener(
      _onCurrencyChanged,
    );
    _salaryController.dispose();
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

  void _toast(String message, {bool isError = false}) =>
      showRxToast(context, message, isError: isError);

  Future<void> _updateSalary() async {
    FocusScope.of(context).unfocus();

    if (_salaryController.text.trim().isEmpty) {
      return _toast("Please enter a salary amount.", isError: true);
    }
    final double? newSalary = CurrencyFormatter.parse(
      _salaryController.text.trim(),
    );
    if (newSalary == null) {
      return _toast("Please enter a valid salary amount.", isError: true);
    }
    if (newSalary < 0) {
      return _toast("Salary cannot be negative.", isError: true);
    }
    if (newSalary > 999999.99) {
      return _toast("Salary amount is too high.", isError: true);
    }
    // Skip the write (and a spurious history entry) when nothing changed.
    if (newSalary == widget.currentSalary) {
      return _toast("Salary is already this amount.");
    }

    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final effectiveDay = DateTime(
        _effectiveDate.year,
        _effectiveDate.month,
        _effectiveDate.day,
      );
      final isFuture = effectiveDay.isAfter(
        DateTime(now.year, now.month, now.day),
      );
      final reason = _reasonController.text.trim().isNotEmpty
          ? _reasonController.text.trim()
          : 'No reason provided';

      final Map<String, dynamic> updateData = isFuture
          ? {
              // Scheduled; applied when the date arrives.
              'futureSalary': newSalary,
              'futureSalaryDate': _effectiveDate,
              'futureSalaryReason': reason,
            }
          : {
              'monthlyCost': newSalary,
              'salary': newSalary,
              'lastSalaryUpdateDate': _effectiveDate,
              'lastSalaryUpdateReason': reason,
              'futureSalary': FieldValue.delete(),
              'futureSalaryDate': FieldValue.delete(),
              'futureSalaryReason': FieldValue.delete(),
            };

      final memberRef = FirebaseFirestore.instance
          .collection('members')
          .doc(widget.memberId);
      await memberRef.update(updateData);

      // Future changes are logged when they activate.
      if (!isFuture) {
        await memberRef.collection('salary_history').add({
          'previousSalary': widget.currentSalary,
          'newSalary': newSalary,
          'delta': newSalary - widget.currentSalary,
          'reason': reason,
          'effectiveDate': _effectiveDate,
          'changedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pop(context);
        _toast(isFuture ? "Salary change scheduled" : "Salary updated");
      }
    } on FirebaseException catch (e) {
      if (mounted) _toast(e.message ?? "Failed to update", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final symbol = CurrencyFormatter.getCurrencySymbol(_userCountryCode);
    final newSalary = CurrencyFormatter.parse(_salaryController.text.trim());
    final delta = newSalary == null ? 0.0 : newSalary - widget.currentSalary;
    final pct = widget.currentSalary > 0
        ? delta / widget.currentSalary * 100
        : 0.0;
    final isToday = DateUtils.isSameDay(_effectiveDate, DateTime.now());
    final isFuture = _effectiveDate.isAfter(DateTime.now()) && !isToday;

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Adjust salary'),
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
                            controller: _salaryController,
                            symbol: symbol,
                            label: 'New monthly salary',
                          ),
                          const SizedBox(height: 12),
                          // Change versus today's salary.
                          if (newSalary != null && delta != 0)
                            RxPill(
                              label:
                                  '${delta > 0 ? '+' : '−'}${CurrencyFormatter.formatByCountryCompact(delta.abs(), _userCountryCode)}'
                                  '${widget.currentSalary > 0 ? ' · ${pct.abs().toStringAsFixed(pct.abs() >= 10 ? 0 : 1)}%' : ''}',
                              foreground: delta > 0 ? rx.positive : rx.negative,
                              background: delta > 0
                                  ? rx.positiveSoft
                                  : rx.negativeSoft,
                            )
                          else
                            Text(
                              'Currently ${CurrencyFormatter.formatByCountryCompact(widget.currentSalary, _userCountryCode)}',
                              style: RxText.caption(context),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    RxReveal.index(
                      1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RxDateField(
                            label: 'Effective from',
                            value: _effectiveDate,
                            firstDate: DateTime(DateTime.now().year - 1),
                            lastDate: DateTime(DateTime.now().year + 2, 12, 31),
                            onChanged: (d) =>
                                setState(() => _effectiveDate = d),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 6),
                            child: Text(
                              isFuture
                                  ? 'Scheduled. It applies automatically on this date'
                                  : 'Applies now',
                              style: RxText.caption(context),
                            ),
                          ),
                          const SizedBox(height: 18),
                          RxTextInput(
                            controller: _reasonController,
                            label: 'Reason',
                            hint: 'e.g. Annual review',
                            icon: HugeIcons.strokeRoundedNote,
                            textInputAction: TextInputAction.done,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final r in _reasons)
                                _reasonChip(
                                  r,
                                  _reasonController.text.trim() == r,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: isFuture ? 'Schedule change' : 'Save salary',
                  loading: _isLoading,
                  onTap: _updateSalary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reasonChip(String label, bool selected) {
    final rx = context.rx;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () => _reasonController.text = label,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? rx.inverse : rx.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected ? Colors.transparent : rx.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: RxText.caption(
              context,
              color: selected ? rx.onInverse : rx.textPrimary,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
