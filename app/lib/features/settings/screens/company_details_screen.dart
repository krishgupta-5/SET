import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:developer';
import 'package:hugeicons/hugeicons.dart';

import '../../../services/currency_formatter.dart';
import '../../../services/user_country_service.dart';
import '../../../services/bank_account_service.dart';
import '../../home/screens/add_bank_account_screen.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';

class CompanyDetailsScreen extends StatefulWidget {
  const CompanyDetailsScreen({super.key});

  @override
  State<CompanyDetailsScreen> createState() => _CompanyDetailsScreenState();
}

class _CompanyDetailsScreenState extends State<CompanyDetailsScreen> {
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _targetRunwayController = TextEditingController();

  String _userCountryCode = '+1'; // Default to USD
  bool _isLoading = false;
  List<Map<String, dynamic>> _bankAccounts = [];
  List<Map<String, dynamic>> _allExpenses = [];

  // Real-time computed financial values (synced like home screen)
  double _fundingAmount = 0.0;
  double _absoluteTotalExpenses = 0.0;
  double get _availableFunds => _fundingAmount - _absoluteTotalExpenses;

  // Real-time stream subscriptions
  StreamSubscription<DocumentSnapshot>? _companySubscription;
  StreamSubscription<QuerySnapshot>? _expensesSubscription;

  @override
  void initState() {
    super.initState();
    _userCountryCode = UserCountryService.getUserCountryCodeSync();
    _setupRealtimeListeners();
    _loadAllData();
  }

  final companyTypes = {
    'sole_proprietorship': 'Sole Proprietorship',
    'partnership': 'Partnership',
    'llp': 'LLP',
    'pvt_ltd': 'Pvt Ltd',
  };

  String _selectedType = "sole_proprietorship";

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await Future.wait([
        loadCompanyData(),
        _fetchExpenses(),
        _fetchBankAccounts(),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

  void _setupRealtimeListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _companySubscription = FirebaseFirestore.instance
        .collection("companies")
        .doc(user.uid)
        .snapshots()
        .listen((docSnapshot) {
          if (docSnapshot.exists && docSnapshot.data() != null) {
            final data = docSnapshot.data()!;
            final funding =
                data["Funding"] ?? data["funding"] ?? data["FUNDING"];
            if (mounted) {
              setState(() {
                _fundingAmount = _toDouble(funding);
              });
            }
          }
        });

    _expensesSubscription = FirebaseFirestore.instance
        .collection('expenses')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            double absoluteTotal = 0.0;

            for (final doc in snapshot.docs) {
              final data = doc.data();
              if (data['isFunding'] == true) continue;
              absoluteTotal += _toDouble(data['Amount'] ?? data['amount']);
            }

            setState(() {
              _absoluteTotalExpenses = absoluteTotal;
            });
          }
        });
  }

  Future<void> _fetchExpenses() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final expensesSnapshot = await FirebaseFirestore.instance
          .collection('expenses')
          .where('uid', isEqualTo: user.uid)
          .orderBy('Date', descending: true)
          .get();

      _allExpenses = expensesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'amount':
              (data['Amount'] as num?)?.toDouble() ??
              (data['amount'] as num?)?.toDouble() ??
              0.0,
          'bankAccount':
              data['BankAccount'] ??
              data['Bank Account'] ??
              data['bankAccount'] ??
              'N/A',
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ DEBUG: Error fetching expenses: $e');
      _allExpenses = [];
    }
  }

  Future<void> _fetchBankAccounts() async {
    try {
      final accountsWithSpending =
          await BankAccountService.getBankAccountsWithSpending(_allExpenses);

      if (mounted) {
        setState(() {
          _bankAccounts = accountsWithSpending;
        });
      }
    } catch (e) {
      debugPrint('❌ DEBUG: Error fetching bank accounts: $e');
      if (mounted) {
        setState(() {
          _bankAccounts = [];
        });
      }
    }
  }

  void _showSuccessMessage(String message) => showRxToast(context, message);

  Future<void> _deleteBankAccount(Map<String, dynamic> account) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final accountId = account['id'] as String?;
      if (accountId == null) {
        _showErrorMessage('Cannot delete account: Missing account ID');
        return;
      }

      try {
        await FirebaseFirestore.instance
            .collection('companies')
            .doc(user.uid)
            .collection('bankAccounts')
            .doc(accountId)
            .delete();

        _showSuccessMessage('Bank account deleted successfully');
        await _loadAllData();
        return;
      } catch (e) {
        try {
          final companyDoc = await FirebaseFirestore.instance
              .collection('companies')
              .doc(user.uid)
              .get();

          if (companyDoc.exists && companyDoc.data() != null) {
            final data = companyDoc.data()!;
            final bankAccounts = data["Bank Accounts"] as List<dynamic>? ?? [];

            final updatedAccounts = bankAccounts.where((accountData) {
              if (accountData is Map<String, dynamic>) {
                final bankName =
                    accountData['name']?.toString() ??
                    accountData['bankName']?.toString() ??
                    accountData['bank_name']?.toString() ??
                    '';
                final last4 =
                    accountData['last4']?.toString() ??
                    accountData['number']?.toString() ??
                    '';

                final currentBankName =
                    account['name']?.toString() ??
                    account['bankName']?.toString() ??
                    account['bank_name']?.toString() ??
                    '';
                final currentLast4 =
                    account['last4']?.toString() ??
                    account['number']?.toString() ??
                    '';

                return !((bankName == currentBankName) &&
                    (last4 == currentLast4));
              }
              return true;
            }).toList();

            await FirebaseFirestore.instance
                .collection('companies')
                .doc(user.uid)
                .update({'Bank Accounts': updatedAccounts});

            _showSuccessMessage('Bank account deleted successfully');
            await _loadAllData();
          }
        } catch (fallbackError) {
          _showErrorMessage('Failed to delete bank account');
        }
      }
    } catch (e) {
      _showErrorMessage('Failed to delete bank account');
    }
  }

  void _showErrorMessage(String message) =>
      showRxToast(context, message, isError: true);

  @override
  void dispose() {
    _companySubscription?.cancel();
    _expensesSubscription?.cancel();
    _companyNameController.dispose();
    _ownerNameController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _descController.dispose();
    _targetRunwayController.dispose();
    super.dispose();
  }

  Future<void> loadCompanyData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final directDoc = await FirebaseFirestore.instance
          .collection("companies")
          .doc(user.uid)
          .get();

      DocumentSnapshot<Map<String, dynamic>>? doc;
      if (directDoc.exists) {
        doc = directDoc;
      } else {
        final snapshot = await FirebaseFirestore.instance
            .collection("companies")
            .where("uid", isEqualTo: user.uid)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          doc = snapshot.docs.first;
        }
      }

      if (doc != null && doc.exists) {
        final data = doc.data()!;
        if (!mounted) return;
        setState(() {
          _companyNameController.text = data["Company Name"] ?? "";
          _ownerNameController.text = data["Owner Name"] ?? "";
          _emailController.text = user.email ?? "";
          _addressController.text = data["Company Address"] ?? "";
          _descController.text = data["Company Work"] ?? "";
          _targetRunwayController.text =
              data["Runway"]?.toString() ??
              data["Target Runway"]?.toString() ??
              "";

          // --- FIXED: Reverse Lookup for Dropdown Key ---
          final savedType = data["Company Type"];
          if (savedType != null) {
            final key = companyTypes.keys.firstWhere(
              (k) => companyTypes[k] == savedType || k == savedType,
              orElse: () => "sole_proprietorship",
            );
            _selectedType = key;
          } else {
            _selectedType = "sole_proprietorship";
          }
        });
      }
    } catch (e) {
      log('Company details fetch error: $e');
    }
  }

  Future<void> updateCompanyData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection("companies")
          .doc(user.uid)
          .set({
            "uid": user.uid,
            "Company Name": _companyNameController.text.trim(),
            "Owner Name": _ownerNameController.text.trim(),
            "Email": _emailController.text.trim(),
            "Company Address": _addressController.text.trim(),
            "Company Work": _descController.text.trim(),
            "Runway": int.tryParse(_targetRunwayController.text.trim()) ?? 0,
            "Company Type": companyTypes[_selectedType],
          }, SetOptions(merge: true));

      await _syncOwnerNameToUsers();
    } catch (e) {
      log('Company data update error: $e');
    }
  }

  Future<void> _syncOwnerNameToUsers() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await user.updateDisplayName(_ownerNameController.text.trim());

      await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
        "name": _ownerNameController.text.trim(),
        "email": _emailController.text.trim(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      log('Owner name sync error: $e');
    }
  }

  bool _isSaving = false;

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_companyNameController.text.trim().isEmpty) {
      showRxToast(context, 'Company name cannot be empty', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    await updateCompanyData();
    if (!mounted) return;
    setState(() => _isSaving = false);
    showRxToast(context, 'Company details saved');
    Navigator.pop(context);
  }

  Future<void> _addBank() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddBankAccountScreen()),
    );
    if (result != null) {
      await _loadAllData();
      _showSuccessMessage('Bank account added');
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> account) async {
    final name =
        account['name']?.toString() ??
        account['bankName']?.toString() ??
        account['bank_name']?.toString() ??
        'this account';
    final ok = await showRxConfirm(
      context,
      title: 'Remove $name?',
      message:
          'Past expenses keep their payment method. This can\'t be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok) await _deleteBankAccount(account);
  }

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
              const RxTopBar(title: 'Company details'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    // Summary first: what you have and how long you aim for.
                    RxReveal.index(
                      0,
                      child: RxCard(
                        padding: EdgeInsets.zero,
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              _metric(
                                'Funds left',
                                CurrencyFormatter.formatByCountryCompact(
                                  _availableFunds,
                                  _userCountryCode,
                                ),
                                color: _availableFunds < 0 ? rx.negative : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Container(width: 1, color: rx.hairline),
                              ),
                              _metric(
                                'Accounts',
                                _isLoading ? '--' : '${_bankAccounts.length}',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Identity'),
                          RxTextInput(
                            controller: _companyNameController,
                            label: 'Company name',
                            hint: 'e.g. Acme Labs',
                            icon: HugeIcons.strokeRoundedBuilding03,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _ownerNameController,
                            label: 'Owner name',
                            hint: 'Your name',
                            icon: HugeIcons.strokeRoundedUser,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _emailController,
                            label: 'Official email',
                            icon: HugeIcons.strokeRoundedMail01,
                            keyboardType: TextInputType.emailAddress,
                            textCapitalization: TextCapitalization.none,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RxSectionHeader(title: 'Legal and location'),
                          RxSelectField<String>(
                            label: 'Company type',
                            value: _selectedType,
                            icon: HugeIcons.strokeRoundedLegalDocument01,
                            options: [
                              for (final e in companyTypes.entries)
                                RxOption(e.key, e.value),
                            ],
                            onChanged: (v) => setState(() => _selectedType = v),
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _descController,
                            label: 'What you do',
                            hint: 'A line about the business',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          RxTextInput(
                            controller: _addressController,
                            label: 'Registered address',
                            hint: 'Street, city, postcode',
                            maxLines: 2,
                          ),
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
                          RxTextInput(
                            controller: _targetRunwayController,
                            label: 'Target runway',
                            hint: 'e.g. 18',
                            icon: HugeIcons.strokeRoundedTarget02,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            suffix: Text(
                              'months',
                              style: RxText.caption(context),
                            ),
                            textInputAction: TextInputAction.done,
                            helper:
                                'How long you want your cash to last ($symbol)',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(4, child: _buildBankSection()),
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: 'Save changes',
                  loading: _isSaving,
                  onTap: _save,
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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: RxText.label(context)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: RxText.value(context, size: 20, color: color),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildBankSection() {
    final rx = context.rx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RxSectionHeader(
          title: 'Payment methods',
          actionLabel: 'Add',
          onAction: _addBank,
        ),
        if (_isLoading)
          const RxSkeleton(height: 132, radius: 22)
        else if (_bankAccounts.isEmpty)
          RxCard(
            child: RxEmptyState(
              icon: HugeIcons.strokeRoundedBank,
              title: 'No accounts yet',
              message: 'Add a bank account to tag where money is spent from',
              actionLabel: 'Add bank account',
              onAction: _addBank,
            ),
          )
        else
          RxCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < _bankAccounts.length; i++) ...[
                  if (i > 0) const RxDivider(indent: 52),
                  _bankRow(_bankAccounts[i], rx),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _bankRow(Map<String, dynamic> account, RxColors rx) {
    final isCash = account['isCash'] == true;
    final name =
        account['name']?.toString() ??
        account['bankName']?.toString() ??
        account['bank_name']?.toString() ??
        'Unknown bank';
    final masked =
        account['maskedNumber']?.toString() ??
        (account['last4']?.toString().isNotEmpty == true
            ? '****${account['last4']}'
            : '****');
    final spent = (account['totalSpent'] as num?)?.toDouble() ?? 0.0;
    final key = isCash ? 'meals' : 'servers';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          RxIconTile(
            icon: isCash
                ? HugeIcons.strokeRoundedCoins01
                : HugeIcons.strokeRoundedBank,
            size: 40,
            iconSize: 19,
            background: RxCategory.soft(context, key),
            foreground: RxCategory.color(context, key),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RxText.body(context),
                ),
                const SizedBox(height: 2),
                Text(
                  spent > 0
                      ? '$masked · ${CurrencyFormatter.formatByCountryCompact(spent, _userCountryCode)} spent'
                      : masked,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RxText.caption(context),
                ),
              ],
            ),
          ),
          if (account['id'] != null)
            RxPressable(
              onTap: () => _confirmDelete(account),
              semanticLabel: 'Remove $name',
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedDelete02,
                    color: rx.textTertiary,
                    size: 18,
                    strokeWidth: 1.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
