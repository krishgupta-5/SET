import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:developer';
import '../../../features/navigation/screens/main_navigation_wrapper.dart';
import '../../../services/currency_preference_service.dart';
import '../../../shared/widgets/error_popup.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_logo.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_pickers.dart';
import '../../../widgets/rx_ui.dart';
import '../../auth/widgets/auth_kit.dart';
import '../widgets/setup_widgets.dart';

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

  // --- UI ---
  // Everything below is presentation. Validation, the phone check and the
  // Firestore writes above are unchanged.

  static const _stepNames = [
    'Identity',
    'Structure',
    'Runway',
    'Banking',
    'Categories',
    'Teams',
  ];

  static const _scenes = [
    SetupScene(
      HugeIcons.strokeRoundedUserCircle,
      "Hi, I'm your AI CFO. Let's start with you and your company.",
    ),
    SetupScene(
      HugeIcons.strokeRoundedBuilding03,
      "Tell me how you're set up so I read your numbers right.",
    ),
    SetupScene(
      HugeIcons.strokeRoundedCoins01,
      "How much cash is left? I'll turn it into a runway forecast.",
    ),
    SetupScene(
      HugeIcons.strokeRoundedBank,
      'Add the accounts money leaves from. Only the last 4 digits are saved.',
    ),
    SetupScene(
      HugeIcons.strokeRoundedTag01,
      "Pick at least 3. I'll sort every expense into these.",
    ),
    SetupScene(
      HugeIcons.strokeRoundedUserGroup,
      "Add your departments and I'll track each team's spend.",
    ),
  ];

  /// Inline messages for the keys [_validateCurrentStep] puts in [_errors].
  String? _err(String key) {
    if (!_errors.contains(key)) return null;
    if (key.startsWith('bank_name_')) return 'Enter the bank name';
    if (key.startsWith('bank_num_')) return 'Use 8 to 18 digits';
    return switch (key) {
      'owner' => 'Enter your full name',
      'mobile' => 'Enter a valid mobile number',
      'country' => 'Pick your country',
      'company' => 'Enter your company name',
      'type' => 'Pick a company type',
      'work' => 'Use at least 15 characters',
      'address' => 'Use at least 15 characters',
      'funding' => 'Enter the funds you have left',
      'runway' => 'Enter a number of months',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;

    if (_isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.rxOverlayStyle,
        child: Scaffold(
          backgroundColor: rx.background,
          body: const SetupLoading(),
        ),
      );
    }

    final finishing = _isFinishing && _currentPage == _totalPages - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: rx.background,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: SafeArea(
                bottom: false,
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
            // "Building your workspace" while the final save runs.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !finishing,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: finishing
                      ? SetupFinishing(companyName: _companyNameController.text)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a confirmation dialog before cancelling setup and signing out.
  Future<void> _confirmCancelSetup() async {
    final confirmed = await showRxConfirm(
      context,
      title: 'Cancel setup?',
      message:
          'Your progress will not be saved. You will be signed out and returned to the login screen.',
      confirmLabel: 'Sign out',
      cancelLabel: 'Keep going',
      destructive: true,
      icon: HugeIcons.strokeRoundedLogout03,
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _currentPage > 0
                        ? RxCircleButton(
                            key: const ValueKey('back'),
                            icon: HugeIcons.strokeRoundedArrowLeft01,
                            semanticLabel: 'Previous step',
                            onTap: () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            ),
                          )
                        : const Center(
                            key: ValueKey('logo'),
                            child: RxLogo(size: 28),
                          ),
                  ),
                ),
                // The step name is the page title below, so the bar only
                // shows where you are.
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        'Step ${_currentPage + 1} of $_totalPages',
                        key: ValueKey(_currentPage),
                        style: RxText.label(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                // Cancel / sign-out, always available.
                RxPressable(
                  onTap: _confirmCancelSetup,
                  semanticLabel: 'Cancel setup',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Text(
                      'Cancel',
                      style: RxText.label(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SetupProgress(step: _currentPage, total: _totalPages),
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
    final step = _stepNames.indexOf(title).clamp(0, _scenes.length - 1);
    var i = 0;
    Widget next(Widget w) => RxReveal.index(i++, child: w);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          next(SetupGuide(scene: _scenes[step], step: step)),
          const SizedBox(height: 20),
          next(
            Text(title, style: RxText.title(context).copyWith(fontSize: 30)),
          ),
          const SizedBox(height: 4),
          next(
            Text(
              subtitle,
              style: RxText.label(context).copyWith(fontSize: 14.5),
            ),
          ),
          const SizedBox(height: 22),
          for (final c in children) next(c),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final last = _currentPage == _totalPages - 1;
    return RxBottomBar(
      child: AuthPrimaryButton(
        label: last ? 'Finish setup' : 'Continue',
        icon: last
            ? HugeIcons.strokeRoundedTick02
            : HugeIcons.strokeRoundedArrowRight02,
        loading: _isFinishing,
        onTap: _isFinishing
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
                        message: "Please enter a valid, active mobile number.",
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
      ),
    );
  }

  // --- STEPS ---
  Widget _buildStep1Identity() {
    return _buildPageContainer(
      title: "Identity",
      subtitle: "Let's start with the basics.",
      children: [
        _buildInputField(
          _ownerNameController,
          "Your full name",
          "owner",
          label: 'Owner name',
          icon: HugeIcons.strokeRoundedUser,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
          ],
        ),
        const SizedBox(height: 16),
        _buildPhoneInputField(_mobileController, "98765 43210", "mobile"),
        const SizedBox(height: 16),
        ShakeWidget(
          shake: _errors.contains('country'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RxSelectField<String>(
                label: 'Country',
                sheetTitle: 'Where is your company based?',
                placeholder: 'Select your country',
                icon: HugeIcons.strokeRoundedGlobe02,
                value: _selectedCountryLocation,
                options: [
                  for (final c in _countryCodes)
                    RxOption(c["name"]!, "${c["flag"]}  ${c["name"]}"),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedCountryLocation = value;
                    _clearError('country');
                  });
                },
              ),
              AuthFieldError(text: _err('country')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildInputField(
          _companyNameController,
          "Startup name",
          "company",
          label: 'Company name',
          icon: HugeIcons.strokeRoundedBuilding03,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
  }

  static const _typeMeta = {
    'sole_proprietorship': (HugeIcons.strokeRoundedUser, 'Single owner'),
    'partnership': (
      HugeIcons.strokeRoundedUserMultiple,
      'Two or more partners',
    ),
    'llp': (HugeIcons.strokeRoundedShield01, 'Limited liability partners'),
    'pvt_ltd': (HugeIcons.strokeRoundedBuilding06, 'Private limited company'),
  };

  Widget _buildStep2Legal() {
    final entries = companyTypes.entries.toList();
    final typeError = _errors.contains('type');

    Widget card(MapEntry<String, String> e) => SetupChoiceCard(
      icon: _typeMeta[e.key]?.$1 ?? HugeIcons.strokeRoundedBuilding03,
      title: e.value,
      subtitle: _typeMeta[e.key]?.$2 ?? '',
      selected: _selectedCompanyType == e.key,
      error: typeError,
      onTap: () {
        setState(() {
          _selectedCompanyType = e.key;
          _clearError('type');
        });
      },
    );

    return _buildPageContainer(
      title: "Structure",
      subtitle: "Legal details and location.",
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Company type',
            style: RxText.label(context).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ShakeWidget(
          shake: typeError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var r = 0; r < entries.length; r += 2) ...[
                if (r > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: card(entries[r])),
                      const SizedBox(width: 10),
                      Expanded(
                        child: r + 1 < entries.length
                            ? card(entries[r + 1])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
              AuthFieldError(text: _err('type')),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _buildTextArea(
          _workDescController,
          "e.g. SaaS platform for managing inventory",
          "work",
          label: 'What does the company do?',
          icon: HugeIcons.strokeRoundedBriefcase01,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),
        _buildTextArea(
          _addressController,
          "Full registered address",
          "address",
          label: 'Registered address',
          icon: HugeIcons.strokeRoundedLocation01,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
  }

  Widget _buildStep3Financials() {
    final rx = context.rx;
    final symbol = _getCurrencySymbol(_selectedCountryCode);
    final fundingError = _errors.contains('funding');

    return _buildPageContainer(
      title: "Runway",
      subtitle: "Current financial health.",
      children: [
        ShakeWidget(
          shake: fundingError,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            decoration: BoxDecoration(
              color: rx.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: fundingError
                    ? rx.negative
                    : Theme.of(context).brightness == Brightness.dark
                    ? rx.hairline
                    : Colors.transparent,
              ),
              boxShadow: rx.cardShadow,
            ),
            child: Column(
              children: [
                Text(
                  'Total funds left',
                  style: RxText.label(
                    context,
                    color: fundingError ? rx.negative : null,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fundingController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  onChanged: (_) => setState(() => _clearError('funding')),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  cursorColor: rx.textPrimary,
                  style: RxText.hero(
                    context,
                    size: 44,
                    color: fundingError ? rx.negative : null,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0',
                    hintStyle: RxText.hero(
                      context,
                      size: 44,
                      color: rx.textTertiary,
                    ),
                    prefixText: '$symbol ',
                    prefixStyle: RxText.value(
                      context,
                      size: 24,
                      color: rx.textSecondary,
                    ),
                  ),
                ),
                AuthFieldError(text: _err('funding')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _buildInputField(
          _runwayController,
          "e.g. 18",
          "runway",
          label: 'Target runway (months)',
          isNumber: true,
          icon: HugeIcons.strokeRoundedCalendar03,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 10),
        // One-tap presets.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in const [6, 12, 18, 24])
              SetupChip(
                label: '$m mo',
                selected: _runwayController.text.trim() == '$m',
                onTap: () => setState(() {
                  _runwayController.text = '$m';
                  _clearError('runway');
                }),
              ),
          ],
        ),
        _buildBurnPreview(symbol),
      ],
    );
  }

  /// "That's about X a month to spend." Shown once both numbers are in.
  Widget _buildBurnPreview(String symbol) {
    final rx = context.rx;
    final funds = int.tryParse(_fundingController.text.trim());
    final months = int.tryParse(_runwayController.text.trim());
    final show = funds != null && funds > 0 && months != null && months > 0;
    final perMonth = show ? (funds / months).round() : 0;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: RxReveal(
                offset: 8,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: rx.positiveSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedSparkles,
                        color: rx.positive,
                        size: 18,
                        strokeWidth: 1.9,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "That's about $symbol${_group(perMonth)} a month to spend.",
                          style: RxText.caption(
                            context,
                            color: rx.positive,
                          ).copyWith(fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// 1234567 -> "1,234,567".
  String _group(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _buildStep4Bank() {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return _buildPageContainer(
      title: "Banking",
      subtitle: "Add source accounts for tracking.",
      children: [
        ...List.generate(_bankAccounts.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: rx.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: dark ? rx.hairline : Colors.transparent,
                ),
                boxShadow: rx.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const RxIconTile(
                        icon: HugeIcons.strokeRoundedBank,
                        size: 32,
                        iconSize: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Account ${index + 1}',
                          style: RxText.heading(context),
                        ),
                      ),
                      if (index > 0)
                        RxPressable(
                          onTap: () => _removeBankAccount(index),
                          semanticLabel: 'Remove account ${index + 1}',
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedDelete02,
                              color: rx.negative,
                              size: 18,
                              strokeWidth: 1.9,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInputField(
                    _bankAccounts[index]["name"]!,
                    "Bank name (e.g. Chase)",
                    "bank_name_$index",
                    icon: HugeIcons.strokeRoundedBank,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z\s\-]'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildInputField(
                    _bankAccounts[index]["number"]!,
                    "Account number (8-18 digits)",
                    "bank_num_$index",
                    icon: HugeIcons.strokeRoundedCreditCard,
                    isNumber: true,
                    textCapitalization: TextCapitalization.none,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(18),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        SetupDashedButton(label: 'Add another account', onTap: _addBankAccount),
        const SizedBox(height: 14),
        Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedSquareLock02,
              color: rx.textTertiary,
              size: 15,
              strokeWidth: 1.9,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Only the bank name and last 4 digits are stored.',
                style: RxText.micro(context).copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _addCustomCategory() {
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
  }

  Widget _buildStep5Categories() {
    return _buildPageContainer(
      title: "Categories",
      subtitle: "Set up default categories.",
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SetupCounter(
            count: _selectedCategories.length,
            min: 3,
            noun: 'categories',
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _allCategories.map((cat) {
            final isSelected = _selectedCategories.contains(cat);
            return SetupChip(
              label: cat,
              selected: isSelected,
              error: _errors.contains('categories'),
              onTap: () {
                setState(() {
                  isSelected
                      ? _selectedCategories.remove(cat)
                      : _selectedCategories.add(cat);
                  _clearError('categories');
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                _customCategoryController,
                "Add a custom category",
                "custom_category",
                icon: HugeIcons.strokeRoundedTag01,
                textCapitalization: TextCapitalization.words,
                onSubmitted: _addCustomCategory,
              ),
            ),
            const SizedBox(width: 10),
            SetupAddButton(label: 'Add category', onTap: _addCustomCategory),
          ],
        ),
      ],
    );
  }

  static const _teamSuggestions = [
    'Sales',
    'Design',
    'Operations',
    'Finance',
    'Product',
    'Support',
  ];

  void _addTeam(String name) {
    if (name.trim().isNotEmpty) {
      setState(() {
        _teams.add({"name": name.trim(), "members": []});
        _teamController.clear();
        _clearError('teams');
      });
    }
  }

  Widget _buildStep6Team() {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final existing = _teams
        .map((t) => (t["name"] as String).toLowerCase())
        .toSet();
    final suggestions = _teamSuggestions
        .where((s) => !existing.contains(s.toLowerCase()))
        .toList();

    return _buildPageContainer(
      title: "Teams",
      subtitle: "Set up your first departments.",
      children: [
        if (_teams.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: rx.negativeSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              'Add at least one team to continue.',
              style: RxText.caption(context, color: rx.negative),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: rx.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _errors.contains('teams')
                    ? rx.negative
                    : dark
                    ? rx.hairline
                    : Colors.transparent,
              ),
              boxShadow: rx.cardShadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < _teams.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 60, color: rx.hairline),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      children: [
                        const RxIconTile(
                          icon: HugeIcons.strokeRoundedUserGroup,
                          size: 34,
                          iconSize: 17,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _teams[i]["name"],
                            style: RxText.body(context),
                          ),
                        ),
                        Builder(
                          builder: (_) {
                            final team = _teams[i];
                            return RxPressable(
                              onTap: () => setState(() => _teams.remove(team)),
                              semanticLabel: 'Remove ${team["name"]}',
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: HugeIcon(
                                  icon: HugeIcons.strokeRoundedCancel01,
                                  color: rx.textTertiary,
                                  size: 16,
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                _teamController,
                "Add a team (e.g. Sales)",
                "teams_input",
                icon: HugeIcons.strokeRoundedUserAdd01,
                textCapitalization: TextCapitalization.words,
                onSubmitted: () => _addTeam(_teamController.text),
              ),
            ),
            const SizedBox(width: 10),
            SetupAddButton(
              label: 'Add team',
              onTap: () => _addTeam(_teamController.text),
            ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in suggestions)
                SetupChip(
                  label: s,
                  selected: false,
                  icon: HugeIcons.strokeRoundedAdd01,
                  onTap: () => _addTeam(s),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // --- REUSABLE INPUT WIDGETS ---

  Widget _buildInputField(
    TextEditingController controller,
    String hint,
    String errorKey, {
    String? label,
    bool isNumber = false,
    List<List<dynamic>>? icon,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    VoidCallback? onChanged,
    VoidCallback? onSubmitted,
  }) {
    return ShakeWidget(
      shake: _errors.contains(errorKey),
      child: RxTextInput(
        controller: controller,
        label: label,
        hint: hint,
        icon: icon,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        errorText: _err(errorKey),
        onChanged: (_) {
          _clearError(errorKey);
          onChanged?.call();
        },
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      ),
    );
  }

  Widget _buildPhoneInputField(
    TextEditingController controller,
    String hint,
    String errorKey,
  ) {
    final rx = context.rx;
    final error = _err(errorKey);

    return ShakeWidget(
      shake: _errors.contains(errorKey),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Mobile number',
              style: RxText.label(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 6, right: 14),
            decoration: BoxDecoration(
              color: rx.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: error != null
                    ? rx.negative
                    : rx.textPrimary.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                RxPressable(
                  onTap: _showCountryCodePicker,
                  semanticLabel: 'Dial code $_selectedCountryCode',
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: rx.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "$_selectedFlag $_selectedCountryCode",
                          style: RxText.body(
                            context,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowDown01,
                          color: rx.textSecondary,
                          size: 16,
                          strokeWidth: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(15),
                    ],
                    onChanged: (_) => _clearError(errorKey),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    cursorColor: rx.textPrimary,
                    style: RxText.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                      hintText: hint,
                      hintStyle: RxText.body(
                        context,
                        color: rx.textTertiary,
                      ).copyWith(fontWeight: FontWeight.w400),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AuthFieldError(text: error),
        ],
      ),
    );
  }

  Future<void> _showCountryCodePicker() async {
    FocusScope.of(context).unfocus();
    final picked = await showRxSelectSheet<String>(
      context,
      title: 'Dial code',
      selected: _selectedCountryCode,
      options: [
        for (final c in _countryCodes)
          RxOption(
            c["code"]!,
            "${c["flag"]}  ${c["name"]}",
            subtitle: c["code"],
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final country = _countryCodes.firstWhere((c) => c["code"] == picked);
    setState(() {
      _selectedCountryCode = country["code"]!;
      _selectedFlag = country["flag"]!;
    });
  }

  Widget _buildTextArea(
    TextEditingController controller,
    String hint,
    String errorKey, {
    String? label,
    List<List<dynamic>>? icon,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return ShakeWidget(
      shake: _errors.contains(errorKey),
      child: RxTextInput(
        controller: controller,
        label: label,
        hint: hint,
        icon: icon,
        maxLines: 3,
        textCapitalization: textCapitalization,
        errorText: _err(errorKey),
        onChanged: (_) => _clearError(errorKey),
      ),
    );
  }
}

// ==========================================
// UTILITY CLASSES (KeepAlive & ShakeWidget)
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
