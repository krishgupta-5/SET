import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:developer';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../services/currency_formatter.dart';
import '../../../services/user_country_service.dart';
import '../../../services/bank_account_service.dart';
import '../../home/screens/add_bank_account_screen.dart';
import '../../../theme/app_theme.dart';

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

  Widget _buildReadOnlyMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
            boxShadow: context.cardShadow,
          ),
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
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

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF30D158),
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

  void _showDeleteAccountDialog(Map<String, dynamic> account) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: context.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.borderColor),
          ),
          title: Text(
            'Delete Bank Account',
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "${account['name']?.toString() ?? account['bankName']?.toString() ?? account['bank_name']?.toString() ?? 'Unknown Bank'}"? This action cannot be undone.',
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteBankAccount(account);
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: const Color(0xFFFF453A),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

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

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF453A), size: 18),
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

  @override
  Widget build(BuildContext context) {
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
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        "Company Details",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: context.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildSectionLabel("IDENTITY"),
                      _buildInputGroup("COMPANY NAME", _companyNameController),
                      const SizedBox(height: 24),
                      _buildInputGroup("OWNER NAME", _ownerNameController),
                      const SizedBox(height: 24),
                      _buildInputGroup("OFFICIAL EMAIL", _emailController),
                      const SizedBox(height: 40),
                      _buildSectionLabel("LEGAL & LOCATION"),
                      _buildDropdownGroup("COMPANY TYPE"),
                      const SizedBox(height: 24),
                      _buildInputGroup(
                        "DESCRIPTION",
                        _descController,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      _buildInputGroup(
                        "REGISTERED ADDRESS",
                        _addressController,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 40),
                      _buildSectionLabel("FINANCIAL OVERVIEW"),
                      _buildReadOnlyMetric(
                        "FUNDS LEFT (${CurrencyFormatter.getCurrencySymbol(_userCountryCode)})",
                        CurrencyFormatter.formatByCountryCompact(
                          _availableFunds,
                          _userCountryCode,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInputGroup(
                        "TARGET RUNWAY (MONTHS)",
                        _targetRunwayController,
                        isNumber: true,
                      ),
                      const SizedBox(height: 40),
                      _buildBankSection(),
                      const SizedBox(height: 100),
                    ],
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

  // --- WIDGET BUILDERS ---

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
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildInputGroup(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
            boxShadow: context.cardShadow,
          ),
          child: TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            maxLines: maxLines,
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: context.textPrimary,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownGroup(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity),
          child: ShadSelect<String>(
            key: ValueKey(_selectedType),
            initialValue: _selectedType,
            placeholder: Text(
              'Select $label',
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textTertiary,
                fontSize: 15,
              ),
            ),
            options: [
              ...companyTypes.entries.map(
                (e) => ShadOption(value: e.key, child: Text(e.value)),
              ),
            ],
            selectedOptionBuilder: (context, selectedValue) => Text(
              companyTypes[selectedValue] ?? selectedValue,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedType = val);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBankSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "LINKED PAYMENT METHODS",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            GestureDetector(
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddBankAccountScreen(),
                  ),
                );
                if (result != null) {
                  await _loadAllData();
                  _showSuccessMessage('Bank account added successfully');
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.glassBackgroundStrong,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.borderColor),
                ),
                child: Icon(Icons.add, color: context.iconPrimary, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                color: context.iconSecondary,
                strokeWidth: 2,
              ),
            ),
          )
        else if (_bankAccounts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "No accounts added",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          )
        else
          ...List.generate(_bankAccounts.length, (index) {
            final account = _bankAccounts[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                  boxShadow: context.cardShadow,
                ),
                child: Row(
                  children: [
                    Builder(
                      builder: (context) {
                        final isCash = account['isCash'] == true;
                        final accentColor = isCash
                            ? const Color(0xFFFF9F0A)
                            : const Color(0xFF30D158);
                        return Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            isCash
                                ? Icons.payments_outlined
                                : Icons.account_balance,
                            color: accentColor,
                            size: 20,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (() {
                              final bankName =
                                  account['name']?.toString() ??
                                  account['bankName']?.toString() ??
                                  account['bank_name']?.toString() ??
                                  'Unknown Bank';
                              return bankName;
                            })(),
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (() {
                              final maskedNumber =
                                  account['maskedNumber']?.toString() ??
                                  (account['last4']?.toString().isNotEmpty ==
                                          true
                                      ? '****${account['last4']}'
                                      : '****');
                              return maskedNumber;
                            })(),
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          if (account['totalSpent'] != null &&
                              ((account['totalSpent'] as num?)?.toDouble() ??
                                      0.0) >
                                  0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Spent: ${CurrencyFormatter.formatByCountryCompact((account['totalSpent'] as num?)?.toDouble() ?? 0.0, _userCountryCode)}',
                              style: TextStyle(
                                fontFamily: 'Satoshi',
                                color: const Color(0xFFFF453A),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (account['id'] != null)
                      GestureDetector(
                        onTap: () => _showDeleteAccountDialog(account),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF453A,
                            ).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Color(0xFFFF453A),
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSaveButton() {
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
          onPressed: () async {
            await updateCompanyData();
            if (mounted) Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: btnBg,
            foregroundColor: btnText,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            "Save Changes",
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
