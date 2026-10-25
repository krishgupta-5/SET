import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../services/currency_preference_service.dart';
import '../../../services/currency_formatter.dart';
import 'category_settings_screen.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';

class BudgetSettingsScreen extends StatefulWidget {
  const BudgetSettingsScreen({super.key});

  @override
  State<BudgetSettingsScreen> createState() => _BudgetSettingsScreenState();
}

class _BudgetSettingsScreenState extends State<BudgetSettingsScreen> {
  final _budgetController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingData = true;
  String _userCountryCode = '+1'; // Default to USD
  double _currentBudget = 0.0;

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

  void _showMinimalToast(String message, {bool isError = false}) =>
      showRxToast(context, message, isError: isError);

  Future<void> _saveBudget() async {
    final raw = _budgetController.text.trim();
    final parsedAmount = CurrencyFormatter.parse(raw);
    if (raw.isEmpty || parsedAmount == null || parsedAmount < 0) {
      _showMinimalToast('Enter a valid amount', isError: true);
      return;
    }

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

  void _onCategoryPicked(String value) {
    if (value == 'add_new') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CategorySettingsScreen()),
      ).then((_) => _loadCurrentBudget());
      return;
    }
    setState(() {
      _selectedCategory = value;
      _budgetController.clear();
    });
    _loadCurrentBudget();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final symbol = CurrencyFormatter.getCurrencySymbol(_userCountryCode);
    final name = _allCategories[_selectedCategory] ?? 'this category';

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Budgets'),
              Expanded(
                child: _isLoadingData
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: const [
                          RxSkeleton(height: 52, radius: 14),
                          SizedBox(height: 24),
                          RxSkeleton(height: 120, radius: 22),
                        ],
                      )
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        children: [
                          RxReveal.index(
                            0,
                            child: RxSelectField<String>(
                              label: 'Category',
                              value: _selectedCategory,
                              icon: RxCategory.icon(_selectedCategory),
                              sheetTitle: 'Choose a category',
                              options: [
                                for (final e in _allCategories.entries)
                                  e.key == 'add_new'
                                      ? const RxOption(
                                          'add_new',
                                          'Add a new category',
                                          icon: HugeIcons.strokeRoundedAdd01,
                                        )
                                      : RxOption(
                                          e.key,
                                          e.value,
                                          icon: RxCategory.icon(e.key),
                                        ),
                              ],
                              onChanged: _onCategoryPicked,
                            ),
                          ),
                          const SizedBox(height: 24),
                          RxReveal.index(
                            1,
                            child: RxCard(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                18,
                                18,
                                18,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    _currentBudget > 0
                                        ? 'Current limit for $name'
                                        : 'No limit set for $name',
                                    textAlign: TextAlign.center,
                                    style: RxText.label(context),
                                  ),
                                  const SizedBox(height: 14),
                                  RxAmountInput(
                                    controller: _budgetController,
                                    symbol: symbol,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'per month',
                                    style: RxText.caption(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          RxReveal.index(
                            2,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                "We'll warn you before an expense takes this category over its limit.",
                                style: RxText.caption(context),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (!_isLoadingData)
                RxBottomBar(
                  child: RxButton(
                    label: 'Save budget',
                    loading: _isLoading,
                    onTap: _selectedCategory == 'add_new' ? null : _saveBudget,
                  ),
                ),
            ],
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
