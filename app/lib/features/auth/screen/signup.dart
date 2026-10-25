import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:startup_expense_tracker/features/auth/services/google_sign_in_service.dart';
import 'package:startup_expense_tracker/features/company-setup/screen/company_setup_screen.dart';
import 'package:startup_expense_tracker/shared/utils/error_handler.dart';

import 'package:startup_expense_tracker/features/auth/auth_wrapper.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/widgets/rx_form.dart';
import 'package:startup_expense_tracker/widgets/rx_motion.dart';
import '../widgets/auth_kit.dart';
import 'login.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  bool _isLoading = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  Future<bool> _verifyEmail(String email) async {
    try {
      final apiKey = dotenv.env['APILAYER_EMAIL_ACCESS_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('Error: APILAYER_EMAIL_ACCESS_KEY is missing in .env.local');
        return true;
      }

      final encodedEmail = Uri.encodeComponent(email);
      final url = Uri.parse(
        'https://apilayer.net/api/check?access_key=$apiKey&email=$encodedEmail',
      );

      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data.containsKey('error')) {
          debugPrint('APILayer Error: ${data['error']['info']}');
          return true;
        }

        final bool isFormatValid = data['format_valid'] == true;
        final bool isMxFound = data['mx_found'] == true;
        final bool isDisposable = data['disposable'] == true;
        final bool isSmtpValid = data['smtp_check'] == true;
        final double score = (data['score'] ?? 0.0).toDouble();

        return isFormatValid &&
            isMxFound &&
            !isDisposable &&
            isSmtpValid &&
            score > 0.6;
      }
      return false;
    } catch (e) {
      debugPrint('Email validation exception: $e');
      return true;
    }
  }

  /// Shown when the email is already registered. Offers the right way back
  /// in: log in with the password, or continue with Google.
  Future<void> _showEmailExistsDialog(
    String email,
    List<String> providers,
  ) async {
    final bool isGoogleOnly =
        providers.contains('google.com') && !providers.contains('password');
    final bool isEmailOnly =
        providers.contains('password') && !providers.contains('google.com');
    final bool isBoth =
        providers.contains('google.com') && providers.contains('password');

    String message;
    if (isGoogleOnly) {
      message =
          'This email is already linked to a Google account. Continue with Google to sign in.';
    } else if (isEmailOnly) {
      message =
          'This email is already registered with a password. Would you like to log in instead?';
    } else if (isBoth) {
      message =
          'This email is already registered. Would you like to log in instead?';
    } else {
      message = 'This email is already registered. Please log in instead.';
    }

    final go = await showRxConfirm(
      context,
      title: 'Email already registered',
      icon: HugeIcons.strokeRoundedMailAccount01,
      message: message,
      confirmLabel: isGoogleOnly ? 'Use Google' : 'Go to login',
    );
    if (!go || !mounted) return;
    if (isGoogleOnly) {
      _signUpWithGoogle();
    } else {
      // Navigate to login with pre-filled email
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LoginScreen(prefillEmail: email)),
      );
    }
  }

  /// Looks up an email in Firestore's users collection to determine
  /// which provider (if any) owns that email address.
  Future<List<String>> _getProvidersByEmail(String email) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(1)
          .get();

      if (query.docs.isEmpty) return [];

      final data = query.docs.first.data();
      final provider = data['provider'] as String?;
      if (provider == null) return [];

      // Normalise provider field: Firestore stores 'google' or 'email'
      if (provider == 'google') return ['google.com'];
      if (provider == 'email') return ['password'];
      return [provider];
    } catch (_) {
      return [];
    }
  }

  Future<void> createUserWithEmailAndPassword() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      ErrorHandler.handleValidationError(
        context: context,
        field: 'Email',
        validationMessage: 'Enter a valid email',
      );
      return;
    }

    final password = _passwordController.text.trim();
    if (password.length < 8 ||
        !password.contains(RegExp(r'[A-Z]')) ||
        !password.contains(RegExp(r'[0-9]'))) {
      ErrorHandler.handleValidationError(
        context: context,
        field: 'Password',
        validationMessage: 'Use 8+ chars, 1 uppercase, 1 number',
      );
      return;
    }

    if (_passwordController.text.trim() !=
        _confirmPasswordController.text.trim()) {
      ErrorHandler.handleValidationError(
        context: context,
        field: 'Password',
        validationMessage: 'Passwords do not match',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Step 1: Validate email via external API
      final isEmailActiveAndValid = await _verifyEmail(email);
      if (!isEmailActiveAndValid) {
        if (mounted) {
          setState(() => _isLoading = false);
          ErrorHandler.handleValidationError(
            context: context,
            field: 'Email',
            validationMessage:
                'Please enter a valid, active real email address.',
          );
        }
        return;
      }

      // Step 2: Create the account
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final User? user = userCredential.user;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': (user.email ?? '').toLowerCase(),
          'provider': 'email',
          'companySetup': false,
          'preferredTheme': 'dark',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });


        if (mounted) {
          ErrorHandler.handleSuccess(
            context: context,
            message: 'Account created successfully! Welcome to our platform.',
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const CompanySetupScreen()),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _isLoading = false);

      if (e.code == 'email-already-in-use') {
        // Query Firestore to determine which provider owns this email
        final providers = await _getProvidersByEmail(email);
        if (mounted) {
          _showEmailExistsDialog(
            email,
            providers.isEmpty ? ['password'] : providers,
          );
        }
      } else {
        if (mounted) {
          ErrorHandler.handleAuthError(
            context: context,
            error: e,
            onRetry: createUserWithEmailAndPassword,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context: context,
          error: e,
          customMessage:
              'An error occurred while creating your account. Please try again.',
          onRetry: createUserWithEmailAndPassword,
        );
      }
    } finally {
      // Ensure loading is always reset even if something unexpected happens.
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Live password checklist.
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _confirmPasswordController.removeListener(_onPasswordChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUpWithGoogle() async {
    FocusScope.of(context).unfocus();
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final UserCredential? userCredential =
          await GoogleSignInService.signInWithGoogle();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (userCredential != null) {
        final bool isNewUser =
            userCredential.additionalUserInfo?.isNewUser ?? false;
        final User user = userCredential.user!;

        if (isNewUser) {
          // Brand new account — ensure Firestore document exists
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'uid': user.uid,
                'email': user.email ?? '',
                'provider': 'google',
                'companySetup': false,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));


          if (mounted) {
            ErrorHandler.handleSuccess(
              context: context,
              message: 'Account created successfully! Welcome.',
            );
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const CompanySetupScreen(),
              ),
            );
          }
        } else {
          // Existing account — treat as login

          if (mounted) {
            ErrorHandler.handleSuccess(
              context: context,
              message: 'Welcome back! Signed in with Google.',
            );
            // Navigate to AuthWrapper which will route to the correct screen
            // (CompanySetup or Home based on companySetup status).
            // We must navigate explicitly because the signup screen replaced
            // AuthWrapper in the stack, so it won't auto-navigate.
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const AuthWrapper()),
              (route) => false,
            );
          }
        }
      } else {
        // User cancelled Google sign-in — not an error, just reset state
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context: context,
          error: e,
          customMessage: 'Failed to sign in with Google. Please try again.',
          onRetry: () async {},
        );
      }
    }
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  static const _cfoLines = [
    'Set up in two minutes.',
    "I'll forecast your runway from day one.",
    'Track burn, payroll and funding in one place.',
    'Ask me anything about your numbers.',
  ];

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      leading: AuthBackButton(onTap: _goToLogin),
      compactText: 'Your AI CFO is saving you a seat',
      // Simple: just the robot and its line, no metric chips.
      hero: (h) => AuthHero(lines: _cfoLines, height: h, chips: const []),
      body: [
        const AuthStep(
          2,
          child: AuthTitle(
            title: 'Create your account',
            subtitle: 'Your AI CFO is free with every account.',
          ),
        ),
        const SizedBox(height: 16),
        AuthStep(3, child: _buildForm()),
        const SizedBox(height: 14),
        const AuthStep(8, child: AuthDivider(text: 'or sign up with')),
        const SizedBox(height: 12),
        AuthStep(
          8,
          child: AuthSocialRow(
            onGoogle: _isLoading ? null : _signUpWithGoogle,
            onGithub: _isLoading ? null : () => showGithubComingSoon(context),
          ),
        ),
      ],
      footer: AuthFooterLink(
        prompt: 'Already have an account?',
        action: 'Log in',
        onTap: _goToLogin,
      ),
    );
  }

  Widget _buildForm() {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();
    // Same rules as createUserWithEmailAndPassword().
    final rules = {
      'At least 8 characters': password.length >= 8,
      'One uppercase letter': password.contains(RegExp(r'[A-Z]')),
      'One number': password.contains(RegExp(r'[0-9]')),
      'Passwords match': confirm.isNotEmpty && password == confirm,
    };

    return AuthGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthStep(
            4,
            child: RxTextInput(
              controller: _emailController,
              hint: 'Work email',
              icon: HugeIcons.strokeRoundedMail01,
              keyboardType: TextInputType.emailAddress,
              textCapitalization: TextCapitalization.none,
            ),
          ),
          const SizedBox(height: 10),
          AuthStep(
            5,
            child: RxPasswordInput(
              controller: _passwordController,
              hint: 'Create a password',
            ),
          ),
          const SizedBox(height: 10),
          AuthStep(
            6,
            child: RxPasswordInput(
              controller: _confirmPasswordController,
              hint: 'Confirm password',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isLoading) createUserWithEmailAndPassword();
              },
            ),
          ),
          // Checklist shows while they're typing a password (keyboard up,
          // page can scroll). With the keyboard closed the page is fixed
          // height, so it hides; the same rules are checked on submit.
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: password.isEmpty || !typing
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: RxReveal(
                      offset: 8,
                      child: RxPasswordChecklist(rules: rules),
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          AuthStep(
            7,
            child: AuthPrimaryButton(
              label: 'Create account',
              loading: _isLoading,
              onTap: _isLoading ? null : createUserWithEmailAndPassword,
            ),
          ),
          const SizedBox(height: 10),
          const AuthFinePrint(
            text: 'By continuing you agree to our Terms and Privacy Policy.',
          ),
        ],
      ),
    );
  }
}
