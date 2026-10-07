import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:startup_expense_tracker/features/auth/services/google_sign_in_service.dart';
import 'package:startup_expense_tracker/features/company-setup/screen/company_setup_screen.dart';
import 'package:startup_expense_tracker/services/ai_service.dart';
import 'package:startup_expense_tracker/shared/utils/error_handler.dart';

import 'package:startup_expense_tracker/features/auth/auth_wrapper.dart';
import '../../../theme/app_theme.dart';
import 'login.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
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

  /// Shows a dialog when email is already registered, offering to go to login.
  void _showEmailExistsDialog(String email, List<String> providers) {
    final bool isGoogleOnly =
        providers.contains('google.com') && !providers.contains('password');
    final bool isEmailOnly =
        providers.contains('password') && !providers.contains('google.com');
    final bool isBoth =
        providers.contains('google.com') && providers.contains('password');

    String message;
    if (isGoogleOnly) {
      message =
          'This email is already linked to a Google account. Please use the "Google Sign-In" button to continue.';
    } else if (isEmailOnly) {
      message =
          'This email is already registered with a password. Would you like to log in instead?';
    } else if (isBoth) {
      message =
          'This email is already registered. Would you like to log in instead?';
    } else {
      message = 'This email is already registered. Please log in instead.';
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.borderColor),
        ),
        title: Text(
          'Email Already Registered',
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (!isGoogleOnly)
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // Navigate to login with pre-filled email
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => LoginScreen(prefillEmail: email),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.textPrimary,
                foregroundColor: context.appBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Go to Login',
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  fontWeight: FontWeight.w600,
                  color: context.appBackground,
                ),
              ),
            ),
        ],
      ),
    );
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

        AIService.syncAICollections().catchError((e) {
          debugPrint('Failed to sync AI data after signup: $e');
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
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).viewInsets.bottom -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 32),
                      _buildLabel(context, "EMAIL ADDRESS"),
                      const SizedBox(height: 8),
                      _buildInputField(
                        context: context,
                        controller: _emailController,
                        hint: "name@company.com",
                        icon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 20),
                      _buildLabel(context, "PASSWORD"),
                      const SizedBox(height: 8),
                      _buildPasswordField(context),
                      const SizedBox(height: 20),
                      _buildLabel(context, "CONFIRM PASSWORD"),
                      const SizedBox(height: 8),
                      _buildConfirmPasswordField(context),
                      const SizedBox(height: 24),
                      _buildSignUpButton(context),
                      const SizedBox(height: 24),
                      _buildDivider(context),
                      const SizedBox(height: 16),
                      _buildGoogleSignInButton(context),
                      const Spacer(),
                      _buildFooter(context),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
              boxShadow: context.cardShadow,
            ),
            child: Icon(Icons.arrow_back, color: context.textPrimary, size: 20),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Create Account",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Join us to manage your startup finances.",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: context.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildInputField({
    required BuildContext context,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textPrimary,
          fontSize: 15,
        ),
        cursorColor: context.textPrimary,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textTertiary,
          ),
          icon: Icon(icon, color: context.iconSecondary, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildConfirmPasswordField(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: TextField(
        controller: _confirmPasswordController,
        obscureText: !_isConfirmPasswordVisible,
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textPrimary,
          fontSize: 15,
        ),
        cursorColor: context.textPrimary,
        decoration: InputDecoration(
          hintText: "Confirm your password",
          hintStyle: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textTertiary,
          ),
          icon: Icon(
            Icons.lock_outline,
            color: context.iconSecondary,
            size: 20,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _isConfirmPasswordVisible
                  ? Icons.visibility
                  : Icons.visibility_off,
              color: context.iconSecondary,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
              });
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildPasswordField(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: TextField(
        controller: _passwordController,
        obscureText: !_isPasswordVisible,
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textPrimary,
          fontSize: 15,
        ),
        cursorColor: context.textPrimary,
        decoration: InputDecoration(
          hintText: "Create a password",
          hintStyle: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textTertiary,
          ),
          icon: Icon(
            Icons.lock_outline,
            color: context.iconSecondary,
            size: 20,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
              color: context.iconSecondary,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _isPasswordVisible = !_isPasswordVisible;
              });
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSignUpButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading
            ? null
            : () {
                createUserWithEmailAndPassword();
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: context.textPrimary,
          foregroundColor: context.appBackground,
          disabledBackgroundColor: context.textTertiary,
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
                  valueColor: AlwaysStoppedAnimation<Color>(
                    context.appBackground,
                  ),
                ),
              )
            : Text(
                "Sign Up",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.appBackground,
                ),
              ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: context.borderColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Or",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: context.borderColor)),
      ],
    );
  }

  Widget _buildGoogleSignInButton(BuildContext context) {
    return GestureDetector(
      onTap: () async {
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

              AIService.syncAICollections().catchError((e) {
                debugPrint('Failed to sync AI data after Google sign-up: $e');
              });

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
              AIService.syncAICollections().catchError((e) {
                debugPrint('Failed to sync AI data after Google sign-in: $e');
              });

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
      },
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: context.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
          boxShadow: context.cardShadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/google_logo.png', height: 24, width: 24),
            const SizedBox(width: 12),
            Text(
              "Google Sign-In",
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Already have an account? ",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 14,
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          },
          child: Text(
            "Login",
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: context.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
