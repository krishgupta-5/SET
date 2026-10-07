import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:developer';
import '../../../features/navigation/screens/main_navigation_wrapper.dart';
import '../../../services/currency_preference_service.dart';

class CompanySetupScreen extends StatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 6;
  bool _isFinishing = false;
  bool _isLoading = true;

  // --- VALIDATION STATE ---
  final Set<String> _errors = {};

  // --- CONTROLLERS & STATE ---

  // Step 1: Identity
  final _ownerNameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _mobileController = TextEditingController();
  String? _selectedCountryLocation;

  // Country Code State
  String _selectedCountryCode = "+91";
  String _selectedFlag = "🇮🇳";

  final List<Map<String, String>> _countryCodes = [
    {"code": "+1", "flag": "🇺🇸", "name": "United States"},
    {"code": "+91", "flag": "🇮🇳", "name": "India"},
    {"code": "+44", "flag": "🇬🇧", "name": "United Kingdom"},
    {"code": "+61", "flag": "🇦🇺", "name": "Australia"},
    {"code": "+81", "flag": "🇯🇵", "name": "Japan"},
    {"code": "+49", "flag": "🇩🇪", "name": "Germany"},
    {"code": "+33", "flag": "🇫🇷", "name": "France"},
    {"code": "+971", "flag": "🇦🇪", "name": "United Arab Emirates"},
    {"code": "+65", "flag": "🇸🇬", "name": "Singapore"},
  ];

  // Step 2: Legal & Loc
  final _addressController = TextEditingController();
  final _workDescController = TextEditingController();

  final companyTypes = {
    'sole_proprietorship': 'Sole Proprietorship',
    'partnership': 'Partnership',
    'llp': 'LLP',
    'pvt_ltd': 'Pvt Ltd',
  };
  String? _selectedCompanyType;

  // Step 3: Financials
  final TextEditingController _fundingController = TextEditingController();
  final TextEditingController _runwayController = TextEditingController();

  // Step 4: Bank (Dynamic List)
  final List<Map<String, TextEditingController>> _bankAccounts = [
    {"name": TextEditingController(), "number": TextEditingController()},
  ];

  // Step 5: Categories
  final List<String> _allCategories = [
    "Marketing",
    "Infrastructure",
    "Office Rent",
    "Legal",
    "Software",
    "Hardware",
    "Design",
    "Travel",
    "Meals",
    "Contractors",
    "Transport",
    "Salary",
    "Others",
  ];
  final Set<String> _selectedCategories = {};

  // Step 6: Team
  final List<Map<String, dynamic>> _teams = [
    {"name": "Engineering", "members": []},
    {"name": "Marketing", "members": []},
  ];
  final TextEditingController _teamController = TextEditingController();
  final TextEditingController _customCategoryController =
      TextEditingController();

  // --- METHODS ---

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists && userDoc.data()?['companySetup'] == true) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      log('Error checking onboarding status: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ownerNameController.dispose();
    _companyNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _workDescController.dispose();
    _fundingController.dispose();
    _runwayController.dispose();
    _teamController.dispose();
    _customCategoryController.dispose();
    for (var acc in _bankAccounts) {
      acc["name"]?.dispose();
      acc["number"]?.dispose();
    }
    super.dispose();
  }

  String _getCurrencySymbol(String dialCode) {
    switch (dialCode) {
      case "+1":
        return "\$";
      case "+91":
        return "₹";
      case "+44":
        return "£";
      case "+61":
        return "A\$";
      case "+81":
        return "¥";
      case "+49":
      case "+33":
        return "€";
      case "+971":
        return "AED";
      case "+65":
        return "S\$";
      default:
        return "\$";
    }
  }

  void _addBankAccount() {
    setState(() {
      _bankAccounts.add({
        "name": TextEditingController(),
        "number": TextEditingController(),
      });
    });
  }

  void _removeBankAccount(int index) {
    if (_bankAccounts.length > 1) {
      setState(() {
        _bankAccounts[index]["name"]?.dispose();
        _bankAccounts[index]["number"]?.dispose();
        _bankAccounts.removeAt(index);
        _errors.remove('bank_name_$index');
        _errors.remove('bank_num_$index');
      });
    }
  }

  void _clearError(String key) {
    if (_errors.contains(key)) {
      setState(() => _errors.remove(key));
    }
  }

  Future<bool> _verifyPhoneNumber(
    String countryCode,
    String mobileNumber,
  ) async {
    try {
      final apiKey = dotenv.env['APILAYER_ACCESS_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        log('Error: APILAYER_ACCESS_KEY is missing in .env.local');
        return true; // Bypass validation if env is missing
      }

      // Remove any spaces or special characters
      final cleanNumber = "$countryCode$mobileNumber".replaceAll(
        RegExp(r'\D'),
        '',
      );

      // FIXED ENDPOINT: Numverify uses /api/validate
      final url = Uri.parse(
        'https://apilayer.net/api/validate?access_key=$apiKey&number=$cleanNumber',
      );

      log('Calling Numverify API: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data.containsKey('error')) {
          log('Numverify API Error Details: ${data['error']}');
          return true; // Bypass if API limit reached or error occurs so user isn't stuck
        }

        return data['valid'] == true;
      }
      return false;
    } catch (e) {
      log('Phone validation exception: $e');
      return true; // Gracefully fallback on network error
    }
  }

  bool _validateCurrentStep() {
    setState(() {
      _errors.clear();
    });

    bool isValid = true;

    switch (_currentPage) {
      case 0: // Identity
        if (_ownerNameController.text.trim().length < 2) _errors.add('owner');
        if (_mobileController.text.trim().length < 7) _errors.add('mobile');
        if (_selectedCountryLocation == null) _errors.add('country');
        if (_companyNameController.text.trim().isEmpty) _errors.add('company');
        isValid = _errors.isEmpty;
        break;

      case 1: // Legal
        if (_selectedCompanyType == null) _errors.add('type');

        if (_workDescController.text.trim().length < 15) {
          _errors.add('work');
          if (isValid) {
            ErrorPopup.showValidation(
              context: context,
              message: "Work description must be at least 15 characters.",
            );
          }
          isValid = false;
        }

        if (_addressController.text.trim().length < 15) {
          _errors.add('address');
          if (isValid) {
            ErrorPopup.showValidation(
              context: context,
              message: "Registered address must be at least 15 characters.",
            );
          }
          isValid = false;
        }
        break;

      case 2: // Financials
        if (int.tryParse(_fundingController.text.trim()) == null) {
          _errors.add('funding');
        }
        if (int.tryParse(_runwayController.text.trim()) == null) {
          _errors.add('runway');
        }
        isValid = _errors.isEmpty;
        break;

      case 3: // Banking
        for (var i = 0; i < _bankAccounts.length; i++) {
          if (_bankAccounts[i]["name"]!.text.trim().length < 2) {
            _errors.add('bank_name_$i');
            isValid = false;
          }
          final accountNumLength = _bankAccounts[i]["number"]!.text
              .trim()
              .length;
          if (accountNumLength < 8 || accountNumLength > 18) {
            _errors.add('bank_num_$i');
            if (isValid) {
              ErrorPopup.showValidation(
                context: context,
                message: "Account Number must be between 8 and 18 digits.",
              );
            }
            isValid = false;
          }
        }
        break;

      case 4: // Categories
        if (_selectedCategories.length < 3) {
          _errors.add('categories');
          isValid = false;
          ErrorPopup.showValidation(
            context: context,
            message: "Please select at least 3 categories.",
          );
        }
        break;

      case 5: // Teams
        if (_teams.isEmpty) {
          _errors.add('teams');
          isValid = false;
          ErrorPopup.showValidation(
            context: context,
            message: "You must have at least one team.",
          );
        }
        break;
    }

    if (!isValid &&
        _currentPage < 4 &&
        _currentPage != 1 &&
        _currentPage != 3) {
      HapticFeedback.heavyImpact();
    } else if (!isValid) {
      HapticFeedback.heavyImpact();
    }

    return isValid;
  }

  bool _validateAllMandatoryFields() {
    return _validateCurrentStep();
  }

  void _showValidationErrorDialog() {
    ErrorPopup.showValidation(
      context: context,
      message: "Please fill in all mandatory fields correctly.",
    );
  }

  Future<void> createTeamsInTeamsCollection() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final batch = FirebaseFirestore.instance.batch();

      for (var team in _teams) {
        final docRef = FirebaseFirestore.instance.collection('teams').doc();
        batch.set(docRef, {
          "id": docRef.id,
          "uid": userId,
          "teamName": team["name"],
          "monthlyBudget": 0.0,
          "budget": 0,
          "color": "blue",
          "iconCodePoint": 0xe7fd,
          "iconFontFamily": "MaterialIcons",
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      log("Teams created in teams collection successfully");
    } catch (e) {
      log('Error creating teams: $e');
    }
  }

  Map<String, dynamic> _formatBankAccount(
    Map<String, TextEditingController> account,
  ) {
    final accountNumber = account["number"]!.text.trim();
    String last4 = "";
    if (accountNumber.length >= 4) {
      last4 = accountNumber.substring(accountNumber.length - 4);
    }
    return {
      "bankName": account["name"]!.text.trim(),
      "last4": last4,
      "verified": false,
      "verificationMethod": "manual",
      "verificationId": null,
    };
  }

  Future<bool> uploadCompanyData() async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final List<Map<String, dynamic>> formattedBankAccounts = _bankAccounts
          .map((account) => _formatBankAccount(account))
          .toList();

      final String fullMobileNumber =
          "$_selectedCountryCode ${_mobileController.text.trim()}";

      // FIX: Force the app to create teams FIRST
      await createTeamsInTeamsCollection();

      // NOW we update the company and trigger the navigation listener
      final result = await FirebaseFirestore.instance.runTransaction((
        transaction,
      ) async {
        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId);
        final companyRef = FirebaseFirestore.instance
            .collection('companies')
            .doc(userId);

        transaction.set(companyRef, {
          "uid": userId,
          "Owner Name": _ownerNameController.text.trim(),
          "Mobile Number": fullMobileNumber,
          "Country Location": _selectedCountryLocation,
          "Company Name": _companyNameController.text.trim(),
          "Company Type": companyTypes[_selectedCompanyType],
          "Company Work": _workDescController.text.trim(),
          "Company Address": _addressController.text.trim(),
          "Funding": int.parse(_fundingController.text.trim()),
          "Runway": int.parse(_runwayController.text.trim()),
          "Bank Accounts": formattedBankAccounts,
          "Categories": _selectedCategories.toList(),
          "Teams": _teams,
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });

        transaction.set(userRef, {
          "companySetup": true,
          "companyId": userId,
          "email": FirebaseAuth.instance.currentUser!.email,
          "preferredCurrency": _selectedCountryCode,
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return true;
      });

      CurrencyPreferenceService.currencyNotifier.value = _selectedCountryCode;

      return result;
    } catch (e) {
      log('Company setup error: $e');
      return false;
    }
  }

  Future<void> _submitSetup() async {
    FocusScope.of(context).unfocus();

    if (!_validateAllMandatoryFields()) {
      _showValidationErrorDialog();
      return;
    }

    setState(() => _isFinishing = true);

    bool success = await uploadCompanyData();

    if (!success) {
      if (!mounted) return;
      ErrorPopup.showServer(
        context: context,
        message: "Failed to setup company. Please try again.",
      );
      setState(() => _isFinishing = false);
      return;
    }

    if (!mounted) return;

    // Use pushAndRemoveUntil instead of pop().
    // pop() only works when CompanySetupScreen was explicitly pushed via
    // Navigator (signup flow). When AuthWrapper renders it directly in its
    // StreamBuilder (Google login / direct auth flow), there is nothing below
    // to pop to, which causes a black screen.
    // pushAndRemoveUntil clears the full stack and navigates to
    // MainNavigationWrapper in all cases.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigationWrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF09090B),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                'Checking setup status...',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _currentPage = page;
                        _errors.clear();
                      });
                    },
                    children: [
                      KeepAliveWrapper(child: _buildStep1Identity()),
                      KeepAliveWrapper(child: _buildStep2Legal()),
                      KeepAliveWrapper(child: _buildStep3Financials()),
                      KeepAliveWrapper(child: _buildStep4Bank()),
                      KeepAliveWrapper(child: _buildStep5Categories()),
                      KeepAliveWrapper(child: _buildStep6Team()),
                    ],
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

  /// Shows a confirmation dialog before cancelling setup and signing out.
  Future<void> _confirmCancelSetup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141416),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: Text(
          'Cancel Setup?',
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Your progress will not be saved. You will be signed out and returned to the login screen.',
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: Colors.white70,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Continue Setup',
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: Colors.white54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Sign Out',
              style: TextStyle(
                fontFamily: 'Satoshi',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Sign out from Google (if applicable) and Firebase.
      // No company/user data has been written yet so this is safe.
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Not signed in with Google — ignore
      }
      await FirebaseAuth.instance.signOut();
      // AuthWrapper's stream will automatically redirect to LoginScreen.
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Row(
            children: List.generate(_totalPages, (index) {
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: index <= _currentPage
                        ? Colors.white
                        : const Color(0xFF1F1F22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_currentPage > 0)
                GestureDetector(
                  onTap: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                )
              else
                const SizedBox(width: 38, height: 38),

              // Cancel / sign-out button — always visible, top-right
              GestureDetector(
                onTap: _confirmCancelSetup,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageContainer({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ...children,
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF09090B).withValues(alpha: 0.0),
            const Color(0xFF09090B),
          ],
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isFinishing
              ? null
              : () async {
                  FocusScope.of(context).unfocus();

                  if (_currentPage < _totalPages - 1) {
                    // 1. Run local synchronous validations first
                    if (!_validateCurrentStep()) {
                      _showValidationErrorDialog(); // Ensure popup shows if they miss fields like Country
                      return;
                    }

                    // 2. Run API validation specifically on Step 0
                    if (_currentPage == 0) {
                      setState(() => _isFinishing = true);

                      final isValidPhone = await _verifyPhoneNumber(
                        _selectedCountryCode,
                        _mobileController.text.trim(),
                      );

                      if (!mounted) return;
                      setState(() => _isFinishing = false);

                      if (!isValidPhone) {
                        setState(() => _errors.add('mobile'));
                        HapticFeedback.heavyImpact();
                        ErrorPopup.showValidation(
                          context: context,
                          message:
                              "Please enter a valid, active mobile number.",
                        );
                        return; // Stop them from advancing
                      }
                    }

                    // 3. Advance to the next page
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  } else {
                    _submitSetup();
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            disabledBackgroundColor: Colors.white70,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: _isFinishing
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : Text(
                  _currentPage == _totalPages - 1
                      ? "Finish Setup"
                      : "Next Step",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }

  // --- STEPS ---
  Widget _buildStep1Identity() {
    return _buildPageContainer(
      title: "Identity",
      subtitle: "Let's start with the basics.",
      children: [
        _buildLabel("OWNER NAME"),
        _buildInputField(
          _ownerNameController,
          "Your Full Name",
          "owner",
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
          ],
        ),
        const SizedBox(height: 24),
        _buildLabel("MOBILE NUMBER"),
        _buildPhoneInputField(_mobileController, "98765 43210", "mobile"),
        const SizedBox(height: 24),

        _buildLabel("COUNTRY LOCATION"),
        ShakeWidget(
          shake: _errors.contains('country'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: double.infinity),
            child: ShadSelect<String>(
              placeholder: Text(
                'Select your country',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: _errors.contains('country')
                      ? const Color(0xFFFF453A).withValues(alpha: 0.6)
                      : Colors.white60,
                  fontSize: 15,
                ),
              ),
              decoration: ShadDecoration(
                color: const Color(0xFF141416),
                border: ShadBorder.all(
                  color: _errors.contains('country')
                      ? const Color(0xFFFF453A)
                      : Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              options: [
                ..._countryCodes.map(
                  (country) => ShadOption(
                    value: country["name"]!,
                    child: Text(
                      "${country["flag"]}  ${country["name"]}",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
              selectedOptionBuilder: (context, value) {
                final country = _countryCodes.firstWhere(
                  (c) => c["name"] == value,
                );
                return Text(
                  "${country["flag"]}  ${country["name"]}",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: Colors.white,
                    fontSize: 15,
                  ),
                );
              },
              onChanged: (value) {
                setState(() {
                  _selectedCountryLocation = value;
                  _clearError('country');
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 24),
        _buildLabel("COMPANY NAME"),
        _buildInputField(
          _companyNameController,
          "Startup Name",
          "company",
          icon: Icons.business,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
  }

  Widget _buildStep2Legal() {
    return _buildPageContainer(
      title: "Structure",
      subtitle: "Legal details and location.",
      children: [
        _buildLabel("COMPANY TYPE"),
        ShakeWidget(
          shake: _errors.contains('type'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: double.infinity),
            child: ShadSelect<String>(
              placeholder: Text(
                'Select company type',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: _errors.contains('type')
                      ? const Color(0xFFFF453A).withValues(alpha: 0.6)
                      : Colors.white60,
                  fontSize: 15,
                ),
              ),
              decoration: ShadDecoration(
                color: const Color(0xFF141416),
                border: ShadBorder.all(
                  color: _errors.contains('type')
                      ? const Color(0xFFFF453A)
                      : Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              options: [
                ...companyTypes.entries.map(
                  (e) => ShadOption(
                    value: e.key,
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
              selectedOptionBuilder: (context, value) => Text(
                companyTypes[value]!,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _selectedCompanyType = value;
                  _clearError('type');
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 24),
        _buildLabel("WHAT IS THE WORK? (Min 15 Chars)"),
        _buildTextArea(
          _workDescController,
          "e.g. SaaS Platform for managing inventory...",
          "work",
          icon: Icons.description_outlined,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 24),
        _buildLabel("REGISTERED ADDRESS (Min 15 Chars)"),
        _buildTextArea(
          _addressController,
          "Full Complete Address...",
          "address",
          icon: Icons.location_on_outlined,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
  }

  Widget _buildStep3Financials() {
    return _buildPageContainer(
      title: "Runway",
      subtitle: "Current financial health.",
      children: [
        ShakeWidget(
          shake: _errors.contains('funding'),
          child: Center(
            child: Column(
              children: [
                Text(
                  "TOTAL FUNDS LEFT",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: _errors.contains('funding')
                        ? const Color(0xFFFF453A)
                        : Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                IntrinsicWidth(
                  child: TextField(
                    controller: _fundingController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    onChanged: (_) => _clearError('funding'),
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: _errors.contains('funding')
                          ? const Color(0xFFFF453A)
                          : Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      prefixText:
                          "${_getCurrencySymbol(_selectedCountryCode)} ",
                      prefixStyle: TextStyle(
                        fontFamily: 'Satoshi',
                        color: _errors.contains('funding')
                            ? const Color(0xFFFF453A)
                            : Colors.white70,
                        fontSize: 24,
                      ),
                      hintText: "0",
                      hintStyle: TextStyle(
                        fontFamily: 'Satoshi',
                        color: _errors.contains('funding')
                            ? const Color(0xFFFF453A).withValues(alpha: 0.4)
                            : Colors.white60,
                        fontSize: 48,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        _buildLabel("TARGET RUNWAY (MONTHS)"),
        _buildInputField(
          _runwayController,
          "e.g. 18",
          "runway",
          isNumber: true,
          icon: Icons.timeline,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
        ),
      ],
    );
  }

  Widget _buildStep4Bank() {
    return _buildPageContainer(
      title: "Banking",
      subtitle: "Add source accounts for tracking.",
      children: [
        ...List.generate(_bankAccounts.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "ACCOUNT 0${index + 1}",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (index > 0)
                      GestureDetector(
                        onTap: () => _removeBankAccount(index),
                        child: Text(
                          "REMOVE",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: const Color(0xFFFF453A),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  _bankAccounts[index]["name"]!,
                  "Bank Name (e.g. Chase)",
                  "bank_name_$index",
                  icon: Icons.account_balance_outlined,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-]')),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  _bankAccounts[index]["number"]!,
                  "Account Number (8-18 digits)",
                  "bank_num_$index",
                  icon: Icons.numbers,
                  isNumber: true,
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(18),
                  ],
                ),
              ],
            ),
          );
        }),
        GestureDetector(
          onTap: _addBankAccount,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(
                  "Add Another Account",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep5Categories() {
    return _buildPageContainer(
      title: "Categories",
      subtitle: "Setup default categories",
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _allCategories.map((cat) {
            final isSelected = _selectedCategories.contains(cat);
            return GestureDetector(
              onTap: () {
                setState(() {
                  isSelected
                      ? _selectedCategories.remove(cat)
                      : _selectedCategories.add(cat);
                  _clearError('categories');
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : const Color(0xFF141416),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected
                        ? Colors.white
                        : _errors.contains('categories')
                        ? const Color(0xFFFF453A).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                _customCategoryController,
                "Add Custom Category",
                "custom_category",
                icon: Icons.add_circle_outline,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                if (_customCategoryController.text.trim().isNotEmpty) {
                  setState(() {
                    final newCat = _customCategoryController.text.trim();
                    if (!_allCategories
                        .map((c) => c.toLowerCase())
                        .contains(newCat.toLowerCase())) {
                      _allCategories.add(newCat);
                    }
                    _selectedCategories.add(
                      _allCategories.firstWhere(
                        (c) => c.toLowerCase() == newCat.toLowerCase(),
                        orElse: () => newCat,
                      ),
                    );
                    _customCategoryController.clear();
                    _clearError('categories');
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.add, color: Colors.black, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep6Team() {
    return _buildPageContainer(
      title: "Teams",
      subtitle: "Setup initial departments",
      children: [
        ..._teams.map((team) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _errors.contains('teams')
                      ? const Color(0xFFFF453A)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.group, color: Colors.white60, size: 18),
                      const SizedBox(width: 12),
                      Text(
                        team["name"],
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _teams.remove(team)),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                _teamController,
                "Add Team (e.g. Sales)",
                "teams_input",
                icon: Icons.group_add,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                if (_teamController.text.trim().isNotEmpty) {
                  setState(() {
                    _teams.add({
                      "name": _teamController.text.trim(),
                      "members": [],
                    });
                    _teamController.clear();
                    _clearError('teams');
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.add, color: Colors.black, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- REUSABLE INPUT WIDGETS ---

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildInputField(
    TextEditingController controller,
    String hint,
    String errorKey, {
    bool isNumber = false,
    IconData? icon,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    final hasError = _errors.contains(errorKey);

    return ShakeWidget(
      shake: hasError,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasError
                ? const Color(0xFFFF453A)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          onChanged: (_) => _clearError(errorKey),
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: Colors.white,
            fontSize: 15,
          ),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'Satoshi',
              color: hasError
                  ? const Color(0xFFFF453A).withValues(alpha: 0.6)
                  : Colors.white60,
              fontSize: 15,
            ),
            icon: icon != null
                ? Icon(
                    icon,
                    color: hasError ? const Color(0xFFFF453A) : Colors.white60,
                    size: 20,
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneInputField(
    TextEditingController controller,
    String hint,
    String errorKey,
  ) {
    final hasError = _errors.contains(errorKey);

    return ShakeWidget(
      shake: hasError,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasError
                ? const Color(0xFFFF453A)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _showCountryCodePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: Colors.transparent,
                child: Row(
                  children: [
                    Text(
                      "$_selectedFlag $_selectedCountryCode",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white60,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: 24,
              width: 1,
              color: Colors.white.withValues(alpha: 0.1),
              margin: const EdgeInsets.symmetric(horizontal: 16),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                onChanged: (_) => _clearError(errorKey),
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: Colors.white,
                  fontSize: 15,
                ),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontFamily: 'Satoshi',
                    color: hasError
                        ? const Color(0xFFFF453A).withValues(alpha: 0.6)
                        : Colors.white60,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCountryCodePicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF141416),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 400),
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Select Dial Code",
                        style: TextStyle(
                          fontFamily: 'Satoshi',
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _countryCodes.length,
                    itemBuilder: (context, index) {
                      final country = _countryCodes[index];
                      final isSelected =
                          _selectedCountryCode == country["code"];

                      return ListTile(
                        onTap: () {
                          setState(() {
                            _selectedCountryCode = country["code"]!;
                            _selectedFlag = country["flag"]!;
                          });
                          Navigator.pop(context);
                        },
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        leading: Text(
                          country["flag"]!,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          country["name"]!,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: Text(
                          country["code"]!,
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: isSelected ? Colors.white : Colors.white38,
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextArea(
    TextEditingController controller,
    String hint,
    String errorKey, {
    IconData? icon,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    final hasError = _errors.contains(errorKey);

    return ShakeWidget(
      shake: hasError,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasError
                ? const Color(0xFFFF453A)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: TextField(
          controller: controller,
          maxLines: 3,
          textCapitalization: textCapitalization,
          onChanged: (_) => _clearError(errorKey),
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: Colors.white,
            fontSize: 15,
          ),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'Satoshi',
              color: hasError
                  ? const Color(0xFFFF453A).withValues(alpha: 0.6)
                  : Colors.white60,
              fontSize: 15,
            ),
            icon: icon != null
                ? Icon(
                    icon,
                    color: hasError ? const Color(0xFFFF453A) : Colors.white60,
                    size: 20,
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// UTILITY CLASSES (KeepAlive, ShakeWidget & ErrorPopup)
// ==========================================

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class ShakeWidget extends StatefulWidget {
  final Widget child;
  final bool shake;

  const ShakeWidget({super.key, required this.child, required this.shake});

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(ShakeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shake && !oldWidget.shake) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_animation.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

enum ErrorType {
  validation,
  network,
  authentication,
  server,
  general,
  success,
  warning,
  info,
}

class ErrorPopup {
  static void show({
    required BuildContext context,
    required String title,
    required String message,
    required ErrorType type,
    Duration? duration,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _ErrorPopupWidget(
        title: title,
        message: message,
        type: type,
        onDismiss: () => overlayEntry.remove(),
        duration: duration ?? _getDurationForType(type),
      ),
    );

    overlay.insert(overlayEntry);
  }

  static Duration _getDurationForType(ErrorType type) {
    switch (type) {
      case ErrorType.success:
      case ErrorType.info:
        return const Duration(seconds: 3);
      case ErrorType.warning:
        return const Duration(seconds: 4);
      case ErrorType.validation:
      case ErrorType.network:
      case ErrorType.authentication:
      case ErrorType.server:
      case ErrorType.general:
        return const Duration(seconds: 5);
    }
  }

  static void showValidation({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Validation Error',
      message: message,
      type: ErrorType.validation,
    );
  }

  static void showServer({
    required BuildContext context,
    required String message,
  }) {
    show(
      context: context,
      title: 'Server Error',
      message: message,
      type: ErrorType.server,
    );
  }
}

class _ErrorPopupWidget extends StatefulWidget {
  final String title;
  final String message;
  final ErrorType type;
  final VoidCallback onDismiss;
  final Duration duration;

  const _ErrorPopupWidget({
    required this.title,
    required this.message,
    required this.type,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_ErrorPopupWidget> createState() => _ErrorPopupWidgetState();
}

class _ErrorPopupWidgetState extends State<_ErrorPopupWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutBack,
          ),
        );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    if (widget.duration.inMilliseconds > 0) {
      Future.delayed(widget.duration, () {
        if (mounted) {
          _dismiss();
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 24,
      right: 24,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF141416),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: _getStatusColor(),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.message,
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (widget.type) {
      case ErrorType.success:
        return Colors.greenAccent;
      case ErrorType.warning:
        return Colors.orangeAccent;
      case ErrorType.info:
        return Colors.lightBlueAccent;
      case ErrorType.validation:
      case ErrorType.network:
      case ErrorType.authentication:
      case ErrorType.server:
      case ErrorType.general:
        return Colors.redAccent;
    }
  }
}
