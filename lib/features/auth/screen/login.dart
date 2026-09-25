import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:startup_expense_tracker/features/auth/screen/signup.dart';
import 'package:startup_expense_tracker/features/auth/screen/forget_password.dart';
import 'package:startup_expense_tracker/features/auth/services/google_sign_in_service.dart';
import 'package:startup_expense_tracker/features/company-setup/screen/company_setup_screen.dart';
import 'package:startup_expense_tracker/services/ai_service.dart';
import 'package:startup_expense_tracker/shared/utils/error_handler.dart';
import '../../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  /// Optional email to pre-fill (e.g. when redirected from Sign Up).
  final String? prefillEmail;

  const LoginScreen({super.key, this.prefillEmail});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill email if provided (e.g., redirected from Sign Up screen)
    if (widget.prefillEmail != null && widget.prefillEmail!.isNotEmpty) {
      _emailController.text = widget.prefillEmail!;
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

      // Normalise: Firestore stores 'google' or 'email'
      if (provider == 'google') return ['google.com'];
      if (provider == 'email') return ['password'];
      return [provider];
    } catch (_) {
      return [];
    }
  }

  Future<void> loginUserWithEmailAndPassword() async {
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

    if (_passwordController.text.trim().isEmpty) {
      ErrorHandler.handleValidationError(
        context: context,
        field: 'Password',
        validationMessage: 'Please enter your password',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        ErrorHandler.handleSuccess(
          context: context,
          message: 'Login successful! Welcome back.',
        );
      }

      AIService.syncAICollections().catchError((e) {
        debugPrint('Failed to sync AI data after login: $e');
      });
    } on FirebaseAuthException catch (e) {
      // If wrong credentials, check if account exists with a different provider
      if (e.code == 'wrong-password' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential') {
        final providers = await _getProvidersByEmail(email);
        if (providers.isNotEmpty && !providers.contains('password')) {
          // Account exists but registered via a different provider (e.g. Google)
          if (mounted) _showWrongProviderDialog(email, providers);
          return;
        }
      }

      if (mounted) {
        ErrorHandler.handleAuthError(
          context: context,
          error: e,
          onRetry: loginUserWithEmailAndPassword,
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context: context,
          error: e,
          customMessage:
              'An error occurred while logging in. Please try again.',
          onRetry: loginUserWithEmailAndPassword,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shows a dialog when the user tries to log in with email/password but
  /// their account is registered with a different provider (e.g., Google).
  void _showWrongProviderDialog(String email, List<String> providers) {
    final bool hasGoogle = providers.contains('google.com');

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
          'Different Sign-In Method',
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          hasGoogle
              ? 'This email is registered with Google Sign-In. Please use the "Google Sign-In" button below to continue.'
              : 'This email is registered with a different sign-in method. Please use the appropriate method to log in.',
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
              'OK',
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 20),
                      _buildLabel(context, "PASSWORD"),
                      const SizedBox(height: 8),
                      _buildPasswordField(context),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ForgotPasswordScreen(
                                  // Pre-fill with whatever the user typed
                                  prefillEmail: _emailController.text.trim(),
                                ),
                              ),
                            );
                          },
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              color: context.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildLoginButton(context),
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
        const SizedBox(height: 20),
        Text(
          "Welcome Back",
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
          "Sign in to access your dashboard.",
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
    TextInputAction action = TextInputAction.next,
    TextInputType keyboardType = TextInputType.text,
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
        textInputAction: action,
        keyboardType: keyboardType,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
        textInputAction: TextInputAction.done,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        style: TextStyle(
          fontFamily: 'Satoshi',
          color: context.textPrimary,
          fontSize: 15,
        ),
        cursorColor: context.textPrimary,
        decoration: InputDecoration(
          hintText: "Enter your password",
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

  Widget _buildLoginButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : loginUserWithEmailAndPassword,
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
                  color: context.appBackground,
                  strokeWidth: 2,
                ),
              )
            : Text(
                "Login",
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
              AIService.syncAICollections().catchError((e) {
                debugPrint('Failed to sync AI data after Google sign-in: $e');
              });

              if (mounted) {
                ErrorHandler.handleSuccess(
                  context: context,
                  message: 'Welcome back! Signed in with Google.',
                );
              }
            }
          }
          // If userCredential is null the user cancelled — no error needed
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
          "Don't have an account? ",
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
              MaterialPageRoute(builder: (context) => const SignUpScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              "Sign Up",
              style: TextStyle(
                fontFamily: 'Satoshi',
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
