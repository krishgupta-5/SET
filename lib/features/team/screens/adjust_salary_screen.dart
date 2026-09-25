import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../services/currency_formatter.dart';
import '../../../../services/currency_preference_service.dart';
import '../../../../theme/app_theme.dart';

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
  String _userCountryCode = '+1'; // Default to USD

  @override
  void initState() {
    super.initState();
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _salaryController = TextEditingController(
      text: widget.currentSalary.toStringAsFixed(0),
    );
    _reasonController = TextEditingController(text: "Performance Raise");
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

  // --- UNIFIED MINIMAL TOAST ---
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
                  color: context.appBackground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.textPrimary,
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

  Future<void> _updateSalary() async {
    FocusScope.of(context).unfocus();

    if (_salaryController.text.trim().isEmpty) {
      _showMinimalToast("Please enter a salary amount.", isError: true);
      return;
    }

    final double? newSalary = CurrencyFormatter.parse(
      _salaryController.text.trim(),
    );

    if (newSalary == null) {
      _showMinimalToast("Please enter a valid salary amount.", isError: true);
      return;
    }

    if (newSalary < 0) {
      _showMinimalToast("Salary cannot be negative.", isError: true);
      return;
    }

    if (newSalary > 999999.99) {
      _showMinimalToast("Salary amount is too high.", isError: true);
      return;
    }

    // T-16: Skip write when the user hasn't changed the salary amount.
    // Prevents a pointless Firestore write and a spurious salary_history entry.
    if (newSalary == widget.currentSalary) {
      _showMinimalToast("No changes detected — salary is already this amount.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final effectiveDateOnly = DateTime(
        _effectiveDate.year,
        _effectiveDate.month,
        _effectiveDate.day,
      );
      final todayOnly = DateTime(now.year, now.month, now.day);
      final isFuture = effectiveDateOnly.isAfter(todayOnly);

      final String reason = _reasonController.text.trim().isNotEmpty
          ? _reasonController.text.trim()
          : 'No reason provided';

      final Map<String, dynamic> updateData = {};

      if (isFuture) {
        // Schedule for future (Lazy Cron pattern)
        updateData['futureSalary'] = newSalary;
        updateData['futureSalaryDate'] = _effectiveDate;
        updateData['futureSalaryReason'] = reason;
      } else {
        // Apply immediately and clear any pending future updates
        updateData['monthlyCost'] = newSalary;
        updateData['salary'] = newSalary;
        updateData['lastSalaryUpdateDate'] = _effectiveDate;
        updateData['lastSalaryUpdateReason'] = reason;
        updateData['futureSalary'] = FieldValue.delete();
        updateData['futureSalaryDate'] = FieldValue.delete();
        updateData['futureSalaryReason'] = FieldValue.delete();
      }

      // Update the member document
      await FirebaseFirestore.instance
          .collection('members')
          .doc(widget.memberId)
          .update(updateData);

      // Only log history immediately if the change is active today.
      // Future updates will be logged by the cron when they activate.
      if (!isFuture) {
        await FirebaseFirestore.instance
            .collection('members')
            .doc(widget.memberId)
            .collection('salary_history')
            .add({
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
        _showMinimalToast("Salary updated successfully");
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        _showMinimalToast(e.message ?? "Failed to update", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format date for display
    // T-17: DateUtils.isSameDay compares calendar day correctly regardless
    // of time-of-day. The old difference().inDays == 0 could return 0 for
    // dates that differ only by a few minutes spanning midnight.
    String dateStr = DateUtils.isSameDay(_effectiveDate, DateTime.now())
        ? "Immediately"
        : "${_effectiveDate.day}/${_effectiveDate.month}/${_effectiveDate.year}";

    return Scaffold(
      backgroundColor: context.appBackground,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: context.isDarkMode
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                          "Adjust Salary",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 28, // Compact Hero
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            "NEW MONTHLY COST",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // HERO INPUT
                        Center(
                          child: IntrinsicWidth(
                            child: TextField(
                              controller: _salaryController,
                              keyboardType: TextInputType.text,
                              textAlign: TextAlign.center,
                              cursorColor: context.textPrimary,
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: context.textPrimary,
                                fontSize: 56,
                                fontWeight: FontWeight.w600, // Upgraded weight
                                height: 1.0,
                                letterSpacing: -2,
                              ),
                              decoration: InputDecoration(
                                prefixText:
                                    "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)} ",
                                prefixStyle: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: context.textSecondary,
                                  fontSize: 56,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 60),

                        _buildDetailRow(
                          "Effective Date",
                          dateStr,
                          Icons.calendar_today_outlined,
                          onTap: _showDatePicker,
                        ),
                        const SizedBox(height: 16),
                        _buildDetailRow(
                          "Reason",
                          _reasonController.text.isEmpty
                              ? "None"
                              : _reasonController.text,
                          Icons.edit_note_outlined,
                          onTap: _showReasonEditor,
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
                _buildFooter(),
              ],
            ),
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

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.appBackground.withValues(alpha: 0.0),
            context.appBackground,
          ],
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _updateSalary,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0A84FF),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(
              0xFF0A84FF,
            ).withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  "Save Compensation",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
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
                Icon(icon, color: context.textSecondary, size: 20),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDatePicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: context.borderColor),
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Effective Date",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(
                          Icons.close,
                          color: context.textSecondary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ShadCalendar(
                    selected: _effectiveDate,
                    fromMonth: DateTime(DateTime.now().year - 1),
                    toMonth: DateTime(DateTime.now().year + 2, 12),
                    onChanged: (DateTime? date) {
                      if (date != null) {
                        setState(() {
                          _effectiveDate = date;
                        });
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _effectiveDate = DateTime.now();
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.appBackground,
                        foregroundColor: context.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: context.borderColor),
                        ),
                      ),
                      child: Text(
                        "Set to Immediately",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showReasonEditor() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: context.borderColor),
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Update Reason",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(
                          Icons.close,
                          color: context.textSecondary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.appBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: TextField(
                      controller: _reasonController,
                      autofocus: true,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: context.textPrimary,
                        fontSize: 15,
                      ),
                      cursorColor: context.textPrimary,
                      decoration: InputDecoration(
                        hintText: "e.g. Annual Review, Promotion...",
                        hintStyle: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textTertiary,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {});
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Save Reason",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
