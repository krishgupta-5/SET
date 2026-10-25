import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:startup_expense_tracker/features/auth/screen/signup.dart';
import 'package:startup_expense_tracker/features/auth/screen/forget_password.dart';
import 'package:startup_expense_tracker/features/auth/services/google_sign_in_service.dart';
import 'package:startup_expense_tracker/features/company-setup/screen/company_setup_screen.dart';
import 'package:startup_expense_tracker/services/ai_service.dart';
import 'package:startup_expense_tracker/shared/utils/error_handler.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/widgets/rx_form.dart';
import '../widgets/auth_kit.dart';

class LoginScreen extends StatefulWidget {
  /// Optional email to pre-fill (e.g. when redirected from Sign Up).
  final String? prefillEmail;

  const LoginScreen({super.key, this.prefillEmail});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

  /// Shown when the email/password login fails but the email belongs to an
  /// account created with another provider (e.g. Google). Offers to sign
  /// in with Google straight away.
  Future<void> _showWrongProviderDialog(
    String email,
    List<String> providers,
  ) async {
    final bool hasGoogle = providers.contains('google.com');
    final useGoogle = await showRxConfirm(
      context,
      title: 'Different sign-in method',
      icon: HugeIcons.strokeRoundedKey01,
      message: hasGoogle
          ? '$email is registered with Google. Continue with Google to sign in.'
          : 'This email is registered with a different sign-in method. Please use that method to log in.',
      confirmLabel: hasGoogle ? 'Use Google' : 'OK',
      cancelLabel: hasGoogle ? 'Not now' : 'Close',
    );
    if (useGoogle && hasGoogle && mounted) _signInWithGoogle();
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();

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
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static const _cfoLines = [
    "Hi, I'm your AI CFO.",
    'I watch your runway while you build.',
    'Ask me where the money goes.',
    'Forecasts in seconds, not spreadsheets.',
  ];

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      compactText: 'Your AI CFO is ready when you are',
      hero: (h) => AuthHero(lines: _cfoLines, height: h),
      body: [
        const AuthStep(
          2,
          child: AuthTitle(
            title: 'Welcome back',
            subtitle: 'Sign in to see your runway, burn and team.',
          ),
        ),
        const SizedBox(height: 16),
        AuthStep(3, child: _buildForm()),
        const SizedBox(height: 14),
        const AuthStep(7, child: AuthDivider(text: 'or continue with')),
        const SizedBox(height: 12),
        AuthStep(
          7,
          child: AuthSocialRow(
            onGoogle: _isLoading ? null : _signInWithGoogle,
            onGithub: _isLoading ? null : () => showGithubComingSoon(context),
          ),
        ),
      ],
      footer: AuthFooterLink(
        prompt: 'New to RunwayX?',
        action: 'Create account',
        onTap: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SignUpScreen()),
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    return AuthGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthStep(
            4,
            child: RxTextInput(
              controller: _emailController,
              hint: 'Email address',
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
              hint: 'Password',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isLoading) loginUserWithEmailAndPassword();
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AuthTextLink(
              label: 'Forgot password?',
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
            ),
          ),
          const SizedBox(height: 4),
          AuthStep(
            6,
            child: AuthPrimaryButton(
              label: 'Log in',
              loading: _isLoading,
              onTap: _isLoading ? null : loginUserWithEmailAndPassword,
            ),
          ),
        ],
      ),
    );
  }
}
