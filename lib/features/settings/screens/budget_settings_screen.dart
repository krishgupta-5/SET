import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/currency_formatter.dart';
import 'category_settings_screen.dart';
import '../../../theme/app_theme.dart';

class BudgetSettingsScreen extends StatefulWidget {
  const BudgetSettingsScreen({super.key});

  @override
  State<BudgetSettingsScreen> createState() => _BudgetSettingsScreenState();
}

class _BudgetSettingsScreenState extends State<BudgetSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _budgetController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingData = true;
  String _userCountryCode = '+1'; // Default to USD
  double _currentBudget = 0.0;
  int _categoryRebuildKey = 0;

  Map<String, String> _allCategories = {};
  String _selectedCategory = '';

  @override
  void initState() {
    super.initState();
    _loadUserCountryCode();
    _loadCurrentBudget();
    CurrencyPreferenceService.currencyNotifier.addListener(_onCurrencyChanged);
  }

  @override
  void dispose() {
    _budgetController.dispose();
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
      });
    }
  }

  Future<void> _loadCurrentBudget() async {
    if (!mounted) return;
    setState(() => _isLoadingData = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) return;

      final companyDoc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();

      if (companyDoc.exists) {
        final companyData = companyDoc.data() as Map<String, dynamic>;
        final budgets = companyData['budgets'] as Map<String, dynamic>? ?? {};
        final selectedCats =
            (companyData['Categories'] as List<dynamic>?)?.cast<String>() ?? [];

        final Map<String, String> fetchedCategories = {};
        for (final val in selectedCats) {
          final key = val.toLowerCase().replaceAll(' ', '_');
          fetchedCategories[key] = val;
        }
        fetchedCategories['add_new'] = '+ Add New Category';

        if (mounted) {
          setState(() {
            _allCategories = fetchedCategories;

            if (!_allCategories.containsKey(_selectedCategory)) {
              _selectedCategory = _allCategories.keys.firstWhere(
                (k) => k != 'add_new',
                orElse: () => 'add_new',
              );
            }

            _currentBudget = DataHelpers.safeParseDouble(
              budgets[_selectedCategory] ?? 0.0,
            );
            _budgetController.text = _currentBudget > 0
                ? _currentBudget.toStringAsFixed(2)
                : '';
            _isLoadingData = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading budget: $e');
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
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

  Future<void> _saveBudget() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final companyId = userDoc.data()?['companyId'];
      if (companyId == null) return;

      final budgetAmount =
          CurrencyFormatter.parse(_budgetController.text.trim()) ?? 0.0;

      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .update({
            'budgets.$_selectedCategory': budgetAmount,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        setState(() {
          _currentBudget = budgetAmount;
          _isLoading = false;
        });

        _showMinimalToast('Budget updated successfully');
      }
    } catch (e) {
      debugPrint('Error saving budget: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showMinimalToast('Failed to update budget', isError: true);
      }
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
                child: _isLoadingData
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            context.iconSecondary,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => FocusScope.of(context).unfocus(),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 16),
                                Text(
                                  "Budget Settings",
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: context.textPrimary,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1.0,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                _buildSectionLabel("EXPENSE CATEGORY"),
                                _buildCategorySelector(),
                                const SizedBox(height: 32),
                                _buildReadOnlyMetric(
                                  "CURRENT ALLOCATION",
                                  CurrencyFormatter.formatByCountryCompact(
                                    _currentBudget,
                                    _userCountryCode,
                                  ),
                                  highlight: _currentBudget > 0,
                                ),
                                const SizedBox(height: 32),
                                _buildSectionLabel("UPDATE MONTHLY LIMIT"),
                                _buildAmountInput(currencySymbol),
                                const SizedBox(height: 100),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              if (!_isLoadingData) _buildSubmitButton(),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: double.infinity),
      child: ShadSelect<String>(
        key: ValueKey('${_selectedCategory}_$_categoryRebuildKey'),
        placeholder: Text(
          'Select category',
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textTertiary,
            fontSize: 15,
          ),
        ),
        initialValue: _selectedCategory,
        onChanged: (value) {
          if (value != null) {
            if (value == 'add_new') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CategorySettingsScreen(),
                ),
              ).then((_) {
                _loadCurrentBudget();
                setState(() {
                  _categoryRebuildKey++;
                });
              });
            } else {
              setState(() {
                _selectedCategory = value;
                _budgetController.clear();
              });
              _loadCurrentBudget();
            }
          }
        },
        selectedOptionBuilder: (context, value) {
          return Text(
            _allCategories[value] ?? 'Select category',
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          );
        },
        options: _allCategories.entries.map((entry) {
          return ShadOption(
            value: entry.key,
            child: Text(
              entry.value,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 14,
              ),
            ),
          );
        }).toList(),
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
            color: highlight ? const Color(0xFF30D158) : context.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlight
                  ? const Color(0xFF30D158).withValues(alpha: 0.3)
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
                color: highlight
                    ? const Color(0xFF30D158)
                    : context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountInput(String currencySymbol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            currencySymbol,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _budgetController,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onTapOutside: (event) => FocusScope.of(context).unfocus(),
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: context.textPrimary,
              decoration: InputDecoration(
                hintText: "0.00",
                hintStyle: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textTertiary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                errorStyle: TextStyle(
                  fontFamily: 'Satoshi',
                  color: const Color(0xFFFF453A),
                  fontSize: 11,
                  height: 0.8,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Amount required';
                }
                final parsed = CurrencyFormatter.parse(value.trim());
                if (parsed == null || parsed < 0) {
                  return 'Invalid amount';
                }
                return null;
              },
            ),
          ),
        ],
      ),
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
          onPressed: _isLoading ? null : _saveBudget,
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
                  "Save Budget",
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

class DataHelpers {
  static double safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
