import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'package:startup_expense_tracker/services/expense_service.dart';

import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/currency_formatter.dart';
import '../../../services/bank_account_service.dart';
import '../../../services/team_member_service.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../shared/widgets/error_popup.dart';
import '../../settings/screens/category_settings_screen.dart';
import '../../../theme/app_theme.dart';

class AddExpenseScreen extends StatefulWidget {
  // ✅ Accept prefill data from scan screen
  final Map<String, String>? prefillData;
  // ✅ Accept image path from scan screen
  final String? imagePath;

  const AddExpenseScreen({super.key, this.prefillData, this.imagePath});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  int _categoryRebuildKey = 0;
  late final TextEditingController _amountController;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _dateController;
  late final ScrollController _scrollController;

  bool _isLoading = false;
  bool _isLoadingBanks = true;
  String _userCountryCode = '+1'; // Default to USD
  bool _isLoadingCountry = true;

  // ✅ Attachment file ID from Telegram
  String? _attachmentFileId;

  // ✅ File picker state
  String? _fileName;
  bool _isUploading = false;

  Map<String, String> categories = {
    'marketing': 'Marketing',
    'infrastructure': 'Infrastructure',
    'office': 'Office Rent',
    'software': 'Software',
    'hardware': 'Hardware',
    'transport': 'Transport',
    'design': 'Design',
    'others': 'Others',
    'travel': 'Travel',
    'meals': 'Meals',
    'contractors': 'Contractors',
    'legal': 'Legal',
  };

  final types = {
    'one_time': 'One-time',
    'recurring': 'Recurring',
  };

  Map<String, String> _bankAccounts = {};
  List<TeamMember> _teamMembers = [];
  List<Team> _teams = [];
  TeamMember? _selectedTeamMember;
  Team? _selectedTeam;
  String _expenseType = "team"; // "team" or "member"

  String _selectedCategory = "marketing";
  String _selectedType = "one_time";
  String? _selectedBankAccount;
  DateTime _selectedDate = DateTime.now();

  // Recurring Details State
  String _recurrenceFrequency = "monthly";
  bool _isOngoing = true;
  late TextEditingController _tenureController;

  @override
  void initState() {
    super.initState();
    _tenureController = TextEditingController();
    _loadUserCountryCode();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
    _scrollController = ScrollController();

    final p = widget.prefillData;

    // ✅ Pre-fill amount and title from scan
    _amountController = TextEditingController(text: p?['amount'] ?? '');
    _titleController = TextEditingController(text: p?['merchant'] ?? '');
    _descriptionController = TextEditingController(
      text: p?['description'] ?? '',
    );

    // ✅ Parse and apply date from scan (DD/MM/YYYY)
    if (p?['date'] != null && p!['date']!.isNotEmpty) {
      try {
        final parts = p['date']!.split('/');
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final year = int.tryParse(parts[2]);
          if (day != null && month != null && year != null) {
            final parsed = DateTime(year, month, day);
            // Only accept dates not in the future
            if (!parsed.isAfter(DateTime.now())) {
              _selectedDate = parsed;
            }
          }
        }
      } catch (_) {
        // Silently fall back to today
      }
    }

    _dateController = TextEditingController(
      text: "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
    );

    // ✅ Apply category if valid
    if (p?['category'] != null && categories.containsKey(p!['category'])) {
      _selectedCategory = p['category']!;
    }

    _fetchBankAccounts();
    _fetchTeamMembers();
    _fetchTeams();
    _fetchCompanyCategories();

    // ✅ Auto-upload image and scroll to attachment section if image path provided
    if (widget.imagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoUploadAndScroll();
      });
    }
  }

  void _loadUserCountryCode() {
    _userCountryCode = CurrencyPreferenceService.getCurrencyPreferenceSync();
    setState(() => _isLoadingCountry = false);
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
    _titleController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    _tenureController.dispose();
    _scrollController.dispose();
    super.dispose();
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
                style: GoogleFonts.inter(
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

  Future<void> _fetchBankAccounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();

      if (doc.exists && doc.data()!.containsKey('Bank Accounts')) {
        final accounts = doc.data()!['Bank Accounts'] as List<dynamic>;
        Map<String, String> loadedBanks = {};

        for (var acc in accounts) {
          final String name = acc['name'] ?? acc['bankName'] ?? 'Unknown Bank';
          final String rawLast4 =
              acc['last4']?.toString() ?? acc['number']?.toString() ?? '';
          final String last4 = rawLast4.isNotEmpty
              ? BankAccountService.extractLast4(rawLast4)
              : '';
          final String key = "$name-$last4";
          final String label = last4.isNotEmpty ? "$name (****$last4)" : name;
          loadedBanks[key] = label;
        }

        setState(() {
          // Build an ordered map: Cash first, then bank accounts
          final Map<String, String> orderedBanks = {'Cash-': 'Cash'};
          orderedBanks.addAll(loadedBanks);
          _bankAccounts = orderedBanks;
          if (_bankAccounts.isNotEmpty) {
            _selectedBankAccount = _bankAccounts.keys.first; // Cash is first
          }
        });
      } else {
        // No bank accounts found, still provide Cash option
        setState(() {
          _bankAccounts = {'Cash-': 'Cash'};
          _selectedBankAccount = 'Cash-';
        });
      }
    } catch (e) {
      debugPrint('Failed to load bank accounts: $e');
      // Fallback: always provide Cash so the form remains usable
      if (mounted) {
        setState(() {
          _bankAccounts = {'Cash-': 'Cash'};
          _selectedBankAccount = 'Cash-';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingBanks = false);
    }
  }

  Future<void> _fetchTeamMembers() async {
    try {
      final members = await TeamMemberService.getTeamMembers();
      if (mounted) {
        setState(() {
          _teamMembers = members;
        });
      }
    } catch (e) {
      debugPrint("Failed to load team members: $e");
    }
  }

  Future<void> _fetchTeams() async {
    try {
      final teams = await TeamMemberService.getTeams();
      if (mounted) {
        setState(() {
          _teams = teams;
        });
      }
    } catch (e) {
      debugPrint("Failed to load teams: $e");
    }
  }

  Future<void> _fetchCompanyCategories() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final companyId = userDoc.data()?['companyId'] as String?;
      if (companyId == null) return;

      final companyDoc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();

      if (companyDoc.exists) {
        final data = companyDoc.data()!;
        final selectedCats =
            (data['Categories'] as List<dynamic>?)?.cast<String>() ?? [];

        final Map<String, String> newCategories = {};

        // Only add the selected categories
        for (final val in selectedCats) {
          final key = val.toLowerCase().replaceAll(' ', '_');
          newCategories[key] = val;
        }

        // Add the Add New Category option
        newCategories['add_new'] = '+ Add New Category';

        if (mounted) {
          setState(() {
            categories = newCategories;
            // Update default selected category if none was prefilled
            if (widget.prefillData?['category'] == null) {
              _selectedCategory = newCategories.keys.firstWhere(
                (k) => k != 'add_new',
                orElse: () => 'add_new',
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Failed to load company categories: $e");
    }
  }


  Future<void> _uploadExpense() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    if (_amountController.text.trim().isEmpty) {
      ErrorPopup.showValidation(
        context: context,
        message: "Please enter an amount.",
      );
      return;
    }
    final double? amount = CurrencyFormatter.parse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ErrorPopup.showValidation(
        context: context,
        message: "Please enter a valid amount greater than 0.",
      );
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      ErrorPopup.showValidation(
        context: context,
        message: "Please enter a title.",
      );
      return;
    }
    if (_titleController.text.trim().length < 3) {
      ErrorPopup.showValidation(
        context: context,
        message: "Title must be at least 3 characters long.",
      );
      return;
    }
    if (_titleController.text.trim().length > 50) {
      ErrorPopup.showValidation(
        context: context,
        message: "Title must not exceed 50 characters.",
      );
      return;
    }
    if (_descriptionController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().length > 500) {
      ErrorPopup.showValidation(
        context: context,
        message: "Description must not exceed 500 characters.",
      );
      return;
    }
    final isRecurring = _selectedType == "recurring";
    if (!isRecurring && _selectedDate.isAfter(DateTime.now())) {
      ErrorPopup.showValidation(
        context: context,
        message: "Date cannot be in the future.",
      );
      return;
    }

    int? recurringTenure;
    if (isRecurring && !_isOngoing) {
      final tenureText = _tenureController.text.trim();
      if (tenureText.isEmpty) {
        _showMinimalToast(
          "Please enter a tenure for the recurring expense.",
          isError: true,
        );
        return;
      }
      recurringTenure = int.tryParse(tenureText);
      if (recurringTenure == null || recurringTenure <= 0) {
        ErrorPopup.showValidation(context: context, message: "Tenure must be a positive number.");
        return;
      }
    }

    if (_selectedBankAccount == null) {
      ErrorPopup.showValidation(
        context: context,
        message: "Please select a bank account or cash.",
      );
      return;
    }

    // ─── Pre-fetch user + companyId (reused for budget check and save) ────────
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ErrorPopup.showAuth(context: context, message: 'User not logged in');
      return;
    }
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final companyId = userDoc.data()?['companyId'] as String?;
    if (companyId == null) {
      if (!mounted) return;
      ErrorPopup.showError(context: context, title: 'System Error', message: 'Company not found');
      return;
    }

    // ─── Budget Warning Check ─────────────────────────────────────────────────
    final shouldProceed = await _checkBudgetAndWarn(
      companyId: companyId,
      userId: user.uid,
      newAmount: amount,
    );
    if (!shouldProceed) return;

    setState(() => _isLoading = true);

    try {
      final currencyCode =
          CurrencyPreferenceService.getCurrencyPreferenceSync();

      // --- Team budget validation (warn but don't block) ---
      if (_expenseType == 'team' && _selectedTeam != null) {
        final teamDoc = await FirebaseFirestore.instance
            .collection('teams')
            .doc(_selectedTeam!.id)
            .get();
        if (teamDoc.exists) {
          final tData = teamDoc.data() as Map<String, dynamic>;
          final monthlyBudget =
              (tData['monthlyBudget'] as num?)?.toDouble() ?? 0.0;

          final membersSnapshot = await FirebaseFirestore.instance
              .collection('members')
              .where('teamId', isEqualTo: _selectedTeam!.id)
              .get();
          double totalMonthlyCost = 0.0;
          for (var doc in membersSnapshot.docs) {
            final mData = doc.data();
            totalMonthlyCost +=
                (mData['monthlyCost'] as num?)?.toDouble() ?? 0.0;
          }

          if (monthlyBudget > 0 && totalMonthlyCost + amount > monthlyBudget) {
            if (!mounted) return;
            ErrorPopup.show(
              context: context,
              title: "Exceeds Team Budget",
              message:
                  "This expense exceeds the monthly budget for ${_selectedTeam!.teamName}.\n\n"
                  "Monthly Budget: ${CurrencyFormatter.formatByCountry(monthlyBudget, currencyCode)}\n"
                  "Total Monthly Cost: ${CurrencyFormatter.formatByCountry(totalMonthlyCost, currencyCode)}\n"
                  "This expense: ${CurrencyFormatter.formatByCountry(amount, currencyCode)}",
              type: ErrorType.warning,
            );
          }
        }
      }

      // --- Member salary validation (warn but don't block) ---
      if (_expenseType == 'member' && _selectedTeamMember != null) {
        final memberDoc = await FirebaseFirestore.instance
            .collection('members')
            .doc(_selectedTeamMember!.id)
            .get();
        if (memberDoc.exists) {
          final mData = memberDoc.data() as Map<String, dynamic>;
          final monthlyCost = (mData['monthlyCost'] as num?)?.toDouble() ?? 0.0;

          if (monthlyCost > 0 && amount > monthlyCost) {
            if (!mounted) return;
            ErrorPopup.show(
              context: context,
              title: "Exceeds Member Salary",
              message:
                  "This expense exceeds ${_selectedTeamMember!.fullName}'s monthly salary.\n\n"
                  "Monthly Salary: ${CurrencyFormatter.formatByCountry(monthlyCost, currencyCode)}\n"
                  "This expense: ${CurrencyFormatter.formatByCountry(amount, currencyCode)}",
              type: ErrorType.warning,
            );
          }
        }
      }

      await ExpenseService().addExpense(
        uid: user.uid,
        companyId: companyId,
        amount: amount,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        date: _selectedDate,
        category: _expenseType == 'member' ? 'salary' : _selectedCategory,
        type: _selectedType,
        bankAccount: _selectedBankAccount,
        attachmentFileId: _attachmentFileId,
        expenseType: _expenseType,
        teamId: _expenseType == 'member' ? _selectedTeamMember?.teamId : _selectedTeam?.id,
        teamName: _selectedTeam?.teamName,
        teamMemberId: _selectedTeamMember?.id,
        teamMemberName: _selectedTeamMember?.fullName,
        isRecurring: isRecurring,
        recurrenceFrequency: _recurrenceFrequency,
        recurringTenure: recurringTenure,
      );

      if (mounted) Navigator.pop(context);
    } on FirebaseException catch (e) {
      if (mounted) {
        ErrorPopup.showError(
          context: context,
          message: e.message ?? 'Failed to upload expense',
          title: "Database Error",
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Budget Warning Helpers ───────────────────────────────────────────────────
  Future<bool> _checkBudgetAndWarn({
    required String companyId,
    required String userId,
    required double newAmount,
  }) async {
    try {
      final companyDoc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();
      final budgets =
          (companyDoc.data()?['budgets'] as Map<String, dynamic>?) ?? {};
      final budget = (budgets[_selectedCategory] as num?)?.toDouble() ?? 0.0;

      if (budget <= 0) return true; // No budget set → proceed silently

      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final expensesSnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: userId)
          .where(
            'Date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
          )
          .get();

      double currentSpending = 0.0;
      for (final doc in expensesSnapshot.docs) {
        final data = doc.data();
        if (data['isFunding'] == true) continue;
        final cat = (data['Category'] as String?)?.toLowerCase().trim() ?? '';
        if (cat == _selectedCategory.toLowerCase().trim()) {
          currentSpending += (data['Amount'] as num?)?.toDouble() ?? 0.0;
        }
      }

      final projectedTotal = currentSpending + newAmount;
      if (projectedTotal <= budget) return true; // Still within budget

      if (!mounted) return false;
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _buildBudgetWarningDialog(
          budget: budget,
          currentSpending: currentSpending,
          newAmount: newAmount,
          projectedTotal: projectedTotal,
        ),
      );
      return proceed ?? false;
    } catch (e) {
      debugPrint('Budget check error: $e');
      return true; // On error, don't block the user
    }
  }

  Widget _buildBudgetWarningDialog({
    required double budget,
    required double currentSpending,
    required double newAmount,
    required double projectedTotal,
  }) {
    final symbol = CurrencyFormatter.getCurrencySymbol(_userCountryCode);
    final overBy = projectedTotal - budget;
    final categoryLabel = categories[_selectedCategory] ?? _selectedCategory;
    String fmt(double v) =>
        CurrencyFormatter.formatByCountry(v, _userCountryCode);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFFF9F0A).withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF9F0A).withValues(alpha: 0.08),
              blurRadius: 40,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF9F0A).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFFF9F0A),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Budget Exceeded',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        categoryLabel,
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFF9F0A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _dialogRow('Monthly Budget', fmt(budget), context.textSecondary),
            const SizedBox(height: 10),
            _dialogRow(
              'Spent This Month',
              fmt(currentSpending),
              context.textSecondary,
            ),
            const SizedBox(height: 10),
            _dialogRow(
              'This Expense',
              '+$symbol${newAmount.toStringAsFixed(2)}',
              const Color(0xFFFF453A),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                color: context.borderColor,
                height: 1,
              ),
            ),
            _dialogRow(
              'Projected Total',
              fmt(projectedTotal),
              context.textPrimary,
              isTotal: true,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF453A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF453A).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_upward_rounded,
                    color: Color(0xFFFF453A),
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${fmt(overBy)} over limit',
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFF453A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: context.cardBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: context.borderColor,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9F0A).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFFF9F0A).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'Add Anyway',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFF9F0A),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogRow(
    String label,
    String value,
    Color valueColor, {
    bool isTotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: isTotal ? context.textPrimary : context.textSecondary,
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: valueColor,
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildExpenseTypeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _expenseType = "team";
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _expenseType == "team"
                      ? const Color(0xFF30D158).withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Team Expense",
                  style: GoogleFonts.inter(
                    color: _expenseType == "team"
                        ? const Color(0xFF30D158)
                        : context.textSecondary,
                    fontSize: 14,
                    fontWeight: _expenseType == "team"
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _expenseType = "member";
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _expenseType == "member"
                      ? const Color(0xFF0A84FF).withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Member Expense",
                  style: GoogleFonts.inter(
                    color: _expenseType == "member"
                        ? const Color(0xFF0A84FF)
                        : context.textSecondary,
                    fontSize: 14,
                    fontWeight: _expenseType == "member"
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
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
                        const SizedBox(height: 24),

                        // ✅ Show "Pre-filled from scan" banner if data came from scan
                        if (widget.prefillData != null &&
                            widget.prefillData!.isNotEmpty)
                          _buildPrefillBanner(),

                        Center(
                          child: Column(
                            children: [
                              _buildSectionLabel("AMOUNT"),
                              const SizedBox(height: 8),
                              _buildAmountInput(),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        _buildSectionLabel("EXPENSE DETAILS"),
                        const SizedBox(height: 8),
                        _buildTextInput(
                          "Expense Title",
                          "e.g. Client Lunch / AWS Bill",
                        ),
                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(
                              child: _buildSelectField(
                                label: "Category",
                                currentValue: _selectedCategory,
                                items: categories,
                                icon: Icons.pie_chart_outline,
                                onChanged: (val) {
                                  FocusScope.of(context).unfocus();
                                  if (val == 'add_new') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const CategorySettingsScreen(),
                                      ),
                                    ).then((_) {
                                      _fetchCompanyCategories();
                                      // Force rebuild to revert the dropdown visual selection
                                      setState(() {
                                        _categoryRebuildKey++;
                                      });
                                    });
                                  } else {
                                    setState(() => _selectedCategory = val!);
                                  }
                                },
                                keySuffix: _categoryRebuildKey.toString(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildSelectField(
                                label: "Type",
                                currentValue: _selectedType,
                                items: types,
                                icon: Icons.repeat,
                                onChanged: (val) {
                                  FocusScope.of(context).unfocus();
                                  setState(() => _selectedType = val!);
                                },
                              ),
                            ),
                          ],
                        ),

                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          crossFadeState:
                              (_selectedType == 'recurring')
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: _buildRecurringDetailsCard(),
                          secondChild: const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 24),

                        if (!_isLoadingBanks && _bankAccounts.isNotEmpty) ...[
                          _buildSelectField(
                            label: "Payment Method",
                            currentValue: _selectedBankAccount ?? "",
                            items: _bankAccounts,
                            icon: Icons.account_balance,
                            onChanged: (val) {
                              FocusScope.of(context).unfocus();
                              setState(() => _selectedBankAccount = val!);
                            },
                          ),
                          const SizedBox(height: 24),
                        ],

                        _buildDateSelector(),
                        const SizedBox(height: 24),
                        _buildTextArea("Description / Notes"),
                        const SizedBox(height: 24),
                        _buildSectionLabel("EXPENSE TYPE"),
                        const SizedBox(height: 8),
                        _buildExpenseTypeSelector(),
                        const SizedBox(height: 24),
                        _buildSectionLabel(
                          _expenseType == 'member'
                              ? 'LINK MEMBER (OPTIONAL)'
                              : 'LINK TEAM (OPTIONAL)',
                        ),
                        const SizedBox(height: 16),
                        _buildTeamSelector(),
                        const SizedBox(height: 32),
                        _buildSectionLabel("ATTACHMENT"),
                        const SizedBox(height: 16),
                        _buildAttachmentZone(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Banner shown when data is pre-filled from scan
  Widget _buildPrefillBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A84FF).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF0A84FF).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF0A84FF), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Fields pre-filled from scanned receipt. Review and edit if needed.",
              style: GoogleFonts.inter(
                color: const Color(0xFF0A84FF),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(Icons.close, color: context.textPrimary, size: 20),
            ),
          ),
          Text(
            "Add Expense",
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        color: context.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildAmountInput() {
    return SizedBox(
      width: double.infinity,
      child: TextField(
        controller: _amountController,
        keyboardType: TextInputType.text,
        textAlign: TextAlign.center,
        onTapOutside: (event) => FocusScope.of(context).unfocus(),
        textInputAction: TextInputAction.next,
        style: GoogleFonts.inter(
          color: context.textPrimary,
          fontSize: 56,
          fontWeight: FontWeight.w600,
          letterSpacing: -2,
        ),
        cursorColor: const Color(0xFF30D158),
        decoration: InputDecoration(
          hintText: "0.00",
          hintStyle: GoogleFonts.inter(
            color: context.textSecondary.withValues(alpha: 0.3),
            fontSize: 56,
            fontWeight: FontWeight.w600,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          prefixText: _isLoadingCountry
              ? '₹'
              : "${CurrencyFormatter.getCurrencySymbol(_userCountryCode)} ",
          prefixStyle: GoogleFonts.inter(
            color: context.textSecondary,
            fontSize: 32,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildTextInput(String label, String placeholder) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: TextField(
        controller: _titleController,
        onTapOutside: (event) => FocusScope.of(context).unfocus(),
        textInputAction: TextInputAction.next,
        style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: context.textSecondary, fontSize: 13),
          hintText: placeholder,
          hintStyle: GoogleFonts.inter(color: context.textSecondary.withValues(alpha: 0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }

  Widget _buildSelectField({
    required String label,
    required String currentValue,
    required Map<String, String> items,
    required IconData icon,
    required Function(String?) onChanged,
    String? keySuffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity),
          child: ShadSelect<String>(
            key: ValueKey('${currentValue}_$keySuffix'),
            placeholder: Text(
              'Select $label',
              style: GoogleFonts.inter(color: context.textSecondary, fontSize: 14),
            ),
            initialValue: currentValue.isNotEmpty ? currentValue : null,
            options: [
              ...items.entries.map(
                (e) => ShadOption(value: e.key, child: Text(e.value)),
              ),
            ],
            selectedOptionBuilder: (context, value) => Text(
              items[value] ?? "Select",
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("DATE"),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: TextField(
            readOnly: true,
            controller: _dateController,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15),
            onTap: () {
              FocusScope.of(context).unfocus();
              _showShadCalendar();
            },
            decoration: InputDecoration(
              icon: Icon(
                Icons.calendar_today,
                color: context.textSecondary,
                size: 20,
              ),
              hintText: "Select date",
              hintStyle: GoogleFonts.inter(color: context.textSecondary.withValues(alpha: 0.5)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              suffixIcon: Icon(
                Icons.calendar_month,
                color: context.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showShadCalendar() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Select Date",
                          style: GoogleFonts.inter(
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
                      selected: _selectedDate,
                      fromMonth: DateTime(_selectedDate.year - 1),
                      toMonth: DateTime(_selectedDate.year + 1, 12),
                      onChanged: (DateTime? date) {
                        if (date != null) {
                          setState(() {
                            _selectedDate = date;
                            _dateController.text =
                                "${date.day}/${date.month}/${date.year}";
                          });
                          Navigator.pop(context);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
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
                          style: GoogleFonts.inter(
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
          ),
        );
      },
    );
  }

  Widget _buildTextArea(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: TextField(
            controller: _descriptionController,
            onTapOutside: (event) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.done,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15),
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: "Enter details...",
              hintStyle: GoogleFonts.inter(color: context.textSecondary.withValues(alpha: 0.5)),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // 🔥 COMPLETELY CLEANED UP: Only shows Avatars and Names
  Widget _buildTeamSelector() {
    final isTeamExpense = _expenseType == "team";
    final items = isTeamExpense ? _teams : _teamMembers;

    if (items.isEmpty) {
      return Container(
        height: 96, // Reduced height since financial data is gone
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: Center(
          child: Text(
            isTeamExpense ? "No teams available" : "No team members available",
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    return SizedBox(
      height: 96, // Reduced height for the clean UI
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length + 1, // +1 for "None" option
        itemBuilder: (context, index) {
          if (index == 0) {
            // "None" option to deselect
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTeam = null;
                    _selectedTeamMember = null;
                  });
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.borderColor,
                        ),
                        color:
                            (isTeamExpense
                                ? _selectedTeam == null
                                : _selectedTeamMember == null)
                            ? context.borderColor
                            : Colors.transparent,
                      ),
                      child: Icon(
                        isTeamExpense
                            ? Icons.group_outlined
                            : Icons.person_outline,
                        color:
                            (isTeamExpense
                                ? _selectedTeam == null
                                : _selectedTeamMember == null)
                            ? context.textPrimary
                            : context.textSecondary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "None",
                      style: GoogleFonts.inter(
                        color:
                            (isTeamExpense
                                ? _selectedTeam == null
                                : _selectedTeamMember == null)
                            ? context.textPrimary
                            : context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (isTeamExpense) {
            final team = _teams[index - 1];
            final isSelected = _selectedTeam?.id == team.id;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTeam = isSelected ? null : team;
                    _selectedTeamMember =
                        null; // Clear member selection when team is selected
                  });
                },
                child: _buildTeamAvatar(team, isSelected),
              ),
            );
          } else {
            final member = _teamMembers[index - 1];
            final isSelected = _selectedTeamMember?.id == member.id;
            final avatarUrl = TeamMemberService.getMemberAvatarUrl(member);

            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTeamMember = isSelected ? null : member;
                    _selectedTeam =
                        null; // Clear team selection when member is selected
                  });
                },
                child: _buildMemberAvatarWithName(
                  member,
                  avatarUrl,
                  isSelected,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildTeamAvatar(Team team, bool isSelected) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: context.textPrimary, width: 2)
                : Border.all(color: Colors.transparent),
          ),
          child: Stack(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _getTeamColor(team.color).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getTeamIcon(team),
                  color: _getTeamColor(team.color),
                  size: 22,
                ),
              ),
              if (isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF30D158),
                      shape: BoxShape.circle,
                      border: Border.all(color: context.appBackground, width: 2),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 70,
          child: Text(
            team.teamName,
            style: GoogleFonts.inter(
              color: isSelected ? context.textPrimary : context.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getTeamColor(String? colorName) {
    switch (colorName?.toLowerCase()) {
      case 'blue':
        return const Color(0xFF0A84FF);
      case 'orange':
        return const Color(0xFFFF9F0A);
      case 'purple':
        return const Color(0xFFA259FF);
      case 'green':
        return const Color(0xFF30D158);
      case 'red':
        return const Color(0xFFFF453A);
      default:
        return const Color(0xFF0A84FF);
    }
  }

  IconData _getTeamIcon(Team team) {
    if (team.iconCodePoint != null && team.iconFontFamily != null) {
      switch (int.tryParse(team.iconCodePoint!)) {
        case 0xe3af:
          return Icons.work;
        case 0xe0af:
          return Icons.business;
        case 0xe7fd:
          return Icons.group;
        case 0xe226:
          return Icons.code;
        case 0xe86c:
          return Icons.design_services;
        case 0xe85d:
          return Icons.computer;
        case 0xe53b:
          return Icons.build;
        case 0xe251:
          return Icons.lightbulb;
        case 0xe7f1:
          return Icons.trending_up;
        case 0xe8b6:
          return Icons.people;
        default:
          return Icons.group;
      }
    }
    return Icons.group;
  }

  // 🔥 CLEANED UP UI: Shows ONLY avatar and name
  Widget _buildMemberAvatarWithName(
    TeamMember member,
    String? avatarUrl,
    bool isSelected,
  ) {
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: context.textPrimary, width: 2)
                  : Border.all(color: Colors.transparent),
            ),
            child: Stack(
              children: [
                _buildMemberAvatarWithTelegram(
                  member.fullName,
                  52,
                  avatarUrl ?? '',
                ),
                if (isSelected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF30D158),
                        shape: BoxShape.circle,
                        border: Border.all(color: context.appBackground, width: 2),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            member.fullName,
            style: GoogleFonts.inter(
              color: isSelected ? context.textPrimary : context.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Build member avatar with Telegram photo support
  Widget _buildMemberAvatarWithTelegram(
    String name,
    double size,
    String avatarUrl,
  ) {
    // Check if it's a Telegram photo
    if (avatarUrl.startsWith('telegram:')) {
      final telegramFileId = TeamMemberService.getTelegramFileId(avatarUrl);
      if (telegramFileId != null) {
        return FutureBuilder<String>(
          future: TeamMemberService.getTelegramImageUrl(telegramFileId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // Show loading indicator while fetching Telegram photo
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: context.cardBackground,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.borderColor,
                  ),
                ),
                child: Center(
                  child: SizedBox(
                    width: size * 0.3,
                    height: size * 0.3,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              );
            } else if (snapshot.hasError || !snapshot.hasData) {
              // Fallback to generated avatar on error
              return AvatarWidget(
                name: name,
                size: size,
                imageUrl: null,
                fontSize: size * 0.4,
              );
            } else {
              // Show Telegram photo
              return AvatarWidget(
                name: name,
                size: size,
                imageUrl: snapshot.data!,
                fontSize: size * 0.4,
              );
            }
          },
        );
      }
    }

    // Handle regular avatar URL
    return AvatarWidget(
      name: name,
      size: size,
      imageUrl: avatarUrl.isNotEmpty && !avatarUrl.contains('ui-avatars.com')
          ? avatarUrl
          : null,
      fontSize: size * 0.4,
    );
  }

  Widget _buildAttachmentZone() {
    return GestureDetector(
      onTap: _isUploading ? null : _pickFile,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isUploading
                ? const Color(0xFF0A84FF).withValues(alpha: 0.3)
                : context.borderColor,
          ),
        ),
        child: Row(
          children: [
            if (_isUploading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Color(0xFF0A84FF),
                  strokeWidth: 2,
                ),
              )
            else
              Icon(
                _fileName != null
                    ? _getFileIcon(_fileName!)
                    : Icons.attach_file,
                color: context.textSecondary,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isUploading
                    ? "Uploading to Telegram..."
                    : _fileName ?? "Upload attachment (any file)",
                style: TextStyle(
                  color: _isUploading
                      ? const Color(0xFF0A84FF)
                      : context.textSecondary,
                  fontSize: _isUploading ? 12 : 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_fileName != null && !_isUploading)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                onPressed: () {
                  setState(() {
                    _fileName = null;
                    _attachmentFileId = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  // ✅ Mobile file picking using image_picker and file_picker
  Future<void> _pickFile() async {
    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: context.cardBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Select Attachment",
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.camera_alt, color: context.textPrimary),
                title: Text(
                  "Take Photo",
                  style: GoogleFonts.inter(color: context.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final XFile? image = await picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 80,
                  );
                  if (image != null) {
                    await _uploadFile(image.path, image.name);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: context.textPrimary),
                title: Text(
                  "Choose Photo / Video",
                  style: GoogleFonts.inter(color: context.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final XFile? media = await picker.pickMedia();
                  if (media != null) {
                    await _uploadFile(media.path, media.name);
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.insert_drive_file,
                  color: context.textPrimary,
                ),
                title: Text(
                  "Choose PDF / Document",
                  style: GoogleFonts.inter(color: context.textPrimary),
                ),
                subtitle: Text(
                  "PDF, Word, Excel, and more",
                  style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: [
                      'pdf',
                      'doc',
                      'docx',
                      'xls',
                      'xlsx',
                      'txt',
                      'csv',
                    ],
                    allowMultiple: false,
                  );
                  if (result != null && result.files.single.path != null) {
                    await _uploadFile(
                      result.files.single.path!,
                      result.files.single.name,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open, color: Colors.white),
                title: Text(
                  "Any File",
                  style: GoogleFonts.inter(color: Colors.white),
                ),
                subtitle: Text(
                  "Browse all file types",
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.any,
                    allowMultiple: false,
                  );
                  if (result != null && result.files.single.path != null) {
                    await _uploadFile(
                      result.files.single.path!,
                      result.files.single.name,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint("File pick error: $e");
      if (mounted) {
        ErrorPopup.showError(
          context: context,
          title: "File Picker Error",
          message: "Could not open file picker.",
        );
      }
    }
  }

  // ✅ Get file icon based on file type
  IconData _getFileIcon(String name) {
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (name.endsWith('.doc') || name.endsWith('.docx')) {
      return Icons.description;
    }
    if (name.endsWith('.xls') || name.endsWith('.xlsx')) {
      return Icons.table_chart;
    }
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif')) {
      return Icons.image;
    }
    if (name.endsWith('.mp4') ||
        name.endsWith('.avi') ||
        name.endsWith('.mov')) {
      return Icons.video_file;
    }
    if (name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.flac')) {
      return Icons.audio_file;
    }
    if (name.endsWith('.zip') ||
        name.endsWith('.rar') ||
        name.endsWith('.tar')) {
      return Icons.archive;
    }
    return Icons.insert_drive_file;
  }

  // ✅ Upload file to Telegram
  Future<String?> uploadToTelegram(String filePath) async {
    try {
      await dotenv.load(fileName: ".env.local");
      final botToken = dotenv.env['TELEGRAM_BOT_TOKEN'];

      if (botToken == null) {
        throw Exception('Telegram bot token not found in environment');
      }

      // Check if it's an image or document
      final isImage =
          filePath.toLowerCase().endsWith('.jpg') ||
          filePath.toLowerCase().endsWith('.jpeg') ||
          filePath.toLowerCase().endsWith('.png') ||
          filePath.toLowerCase().endsWith('.gif');

      final uri = Uri.parse(
        "https://api.telegram.org/bot$botToken/${isImage ? 'sendPhoto' : 'sendDocument'}",
      );

      var request = http.MultipartRequest('POST', uri);
      request.fields['chat_id'] = '-1003885930746';

      if (isImage) {
        request.files.add(await http.MultipartFile.fromPath('photo', filePath));
      } else {
        request.files.add(
          await http.MultipartFile.fromPath('document', filePath),
        );
      }

      final response = await request.send();

      if (response.statusCode == 200) {
        final res = await http.Response.fromStream(response);
        final data = jsonDecode(res.body);

        if (isImage) {
          // 🔥 IMPORTANT: take highest quality image
          return data['result']['photo'].last['file_id'];
        } else {
          return data['result']['document']['file_id'];
        }
      } else {
        throw Exception("Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('Error uploading to Telegram: $e');
      return null;
    }
  }

  // ✅ Upload file and update state
  Future<void> _uploadFile(String filePath, String fileName) async {
    try {
      setState(() {
        _isUploading = true;
        _fileName = fileName;
      });

      final fileId = await uploadToTelegram(filePath);

      if (fileId == null) {
        throw Exception('Failed to upload file to Telegram');
      }

      setState(() {
        _isUploading = false;
        _attachmentFileId = fileId;
      });

      if (!mounted) return;
      ErrorPopup.showSuccess(
        context: context,
        message: "File uploaded successfully!",
      );
    } catch (e) {
      debugPrint('Error uploading file: $e');
      setState(() {
        _isUploading = false;
        _fileName = null;
      });

      if (mounted) {
        ErrorPopup.showError(
          context: context,
          title: "Upload Failed",
          message: "Failed to upload file: $e",
        );
      }
    }
  }

  // ✅ Auto-upload image from scan and scroll to attachment section
  Future<void> _autoUploadAndScroll() async {
    if (widget.imagePath == null) return;

    // Auto-upload the scanned image so the user doesn't have to re-pick it
    final imageName = widget.imagePath!.split('/').last;
    await _uploadFile(widget.imagePath!, imageName);

    // Wait a moment for the widget to settle after upload
    await Future.delayed(const Duration(milliseconds: 300));

    // Scroll to attachment section so user sees the uploaded receipt
    if (mounted && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildSaveButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appBackground,
        border: Border(
          top: BorderSide(color: context.borderColor),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _uploadExpense,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.textPrimary,
            foregroundColor: context.appBackground,
            disabledBackgroundColor: context.textSecondary.withValues(alpha: 0.3),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.appBackground,
                  ),
                )
              : Text(
                  "Save Expense",
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildRecurringDetailsCard() {
    final Map<String, String> frequencies = {
      'daily': 'Daily',
      'weekly': 'Weekly',
      'monthly': 'Monthly',
      'yearly': 'Yearly',
    };

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBackground, // Glassy background
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.repeat_on_outlined,
                color: Color(0xFF0A84FF),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                "RECURRENCE DETAILS",
                style: GoogleFonts.inter(
                  color: const Color(0xFF0A84FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Frequency selector row & Ongoing switch row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel("FREQUENCY"),
                    const SizedBox(height: 8),
                    ShadSelect<String>(
                      placeholder: Text(
                        'Select Frequency',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      initialValue: _recurrenceFrequency,
                      options: [
                        ...frequencies.entries.map(
                          (e) => ShadOption(value: e.key, child: Text(e.value)),
                        ),
                      ],
                      selectedOptionBuilder: (context, value) => Text(
                        frequencies[value] ?? "Monthly",
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _recurrenceFrequency = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel("ONGOING EXPENSE"),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Switch(
                          value: _isOngoing,
                          activeThumbColor: const Color(0xFF30D158),
                          activeTrackColor: const Color(
                            0xFF30D158,
                          ).withValues(alpha: 0.2),
                          inactiveThumbColor: context.textSecondary,
                          inactiveTrackColor: context.borderColor,
                          onChanged: (val) {
                            setState(() {
                              _isOngoing = val;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isOngoing ? "Ongoing" : "Fixed Term",
                          style: GoogleFonts.inter(
                            color: context.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // If not ongoing, show tenure field
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: !_isOngoing
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: _buildRecurringInputField(
                label: "TENURE (MONTHS / OCCURRENCES)",
                placeholder: "e.g. 12",
                controller: _tenureController,
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringInputField({
    required String label,
    required String placeholder,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: GoogleFonts.inter(color: context.textSecondary.withValues(alpha: 0.5), fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
