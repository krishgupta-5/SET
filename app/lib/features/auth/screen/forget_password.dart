import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:startup_expense_tracker/features/auth/screen/login.dart';
import '../../../shared/widgets/error_popup.dart';
import '../services/auth_service.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../widgets/rx_form.dart';
import '../widgets/auth_kit.dart';

class ForgotPasswordScreen extends StatefulWidget {
  /// Optional email to pre-fill (e.g. passed from login screen).
  final String? prefillEmail;

  const ForgotPasswordScreen({super.key, this.prefillEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = false;
  bool _emailSent = false;
  String? _emailError;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null && widget.prefillEmail!.isNotEmpty) {
      _emailController.text = widget.prefillEmail!;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldownSeconds = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds == 0) {
        timer.cancel();
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  /// Returns the provider string for a known account email, or null if not found.
  Future<String?> _getAccountProvider(String email) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;
      return query.docs.first.data()['provider'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address';
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }
    return null;
  }

  Future<void> _showGoogleAccountDialog() async {
    final go = await showRxConfirm(
      context,
      title: 'Google account detected',
      icon: HugeIcons.strokeRoundedKey01,
      message:
          'This email is linked to a Google account. You don\'t need a password, just continue with Google on the login screen.',
      confirmLabel: 'Go to login',
    );
    if (go && mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    FocusScope.of(context).unfocus();

    // Same rules the old form validator used.
    _emailError = _validateEmail(_emailController.text);
    setState(() {});
    if (_emailError != null) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();

    try {
      final provider = await _getAccountProvider(email);
      if (provider == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ErrorPopup.showAuth(
            context: context,
            message:
                'Account not found. Please check your email or sign up first.',
          );
        }
        return;
      }

      if (provider == 'google') {
        if (mounted) {
          setState(() => _isLoading = false);
          _showGoogleAccountDialog();
        }
        return;
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      await AuthService.logPasswordReset(email: email, status: 'success');

      if (mounted) {
        setState(() => _emailSent = true);
        ErrorPopup.showSuccess(
          context: context,
          message: 'Reset link sent! Please check your inbox and spam folder.',
        );
        _startCooldown();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage =
              'If an account exists with this email, a reset link has been sent.';
          if (mounted) setState(() => _emailSent = true);
          _startCooldown();
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many requests. Please try again later.';
          _startCooldown();
          break;
        case 'user-disabled':
          errorMessage =
              'This account has been disabled. Please contact support.';
          break;
        default:
          errorMessage = 'Failed to send reset link. Please try again.';
      }

      await AuthService.logPasswordReset(
        email: email,
        status: 'failed',
        error: e.code,
      );

      if (mounted) {
        ErrorPopup.showAuth(context: context, message: errorMessage);
      }
    } catch (e) {
      await AuthService.logPasswordReset(
        email: email,
        status: 'failed',
        error: 'unexpected_error',
      );

      if (mounted) {
        ErrorPopup.showError(
          context: context,
          title: 'Unexpected Error',
          message: 'An unexpected error occurred. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _cfoLines = [
    'Happens to every founder.',
    "I'll send you a secure reset link.",
    'Check spam if it hides from you.',
  ];

  @override
  Widget build(BuildContext context) {
    final bool isButtonDisabled = _isLoading || _cooldownSeconds > 0;

    return AuthPage(
      leading: AuthBackButton(onTap: () => Navigator.maybePop(context)),
      compactText: "I'll send a secure reset link",
      hero: (h) => AuthHero(
        lines: _cfoLines,
        height: h,
        chips: const [
          AuthChipData(
            HugeIcons.strokeRoundedShieldKey,
            'Reset link',
            'Secure',
            up: true,
          ),
          AuthChipData(
            HugeIcons.strokeRoundedMailSend01,
            'Delivery',
            'Under a minute',
          ),
        ],
      ),
      body: [
        const AuthStep(
          2,
          child: AuthTitle(
            title: 'Reset password',
            subtitle: "Enter your account email and we'll send you a link.",
          ),
        ),
        const SizedBox(height: 16),
        AuthStep(
          3,
          child: AuthGlassCard(
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
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                    onSubmitted: (_) {
                      if (!isButtonDisabled) _sendPasswordResetEmail();
                    },
                  ),
                ),
                AuthFieldError(text: _emailError),
                // Success hint after the email is sent.
                if (_emailSent) ...[
                  const SizedBox(height: 12),
                  const AuthNotice(
                    icon: HugeIcons.strokeRoundedMailOpen01,
                    text:
                        'Check your inbox (and spam folder) for the reset link.',
                  ),
                ],
                const SizedBox(height: 14),
                AuthStep(
                  5,
                  child: AuthPrimaryButton(
                    label: _cooldownSeconds > 0
                        ? 'Resend in ${_cooldownSeconds}s'
                        : (_emailSent ? 'Send again' : 'Send reset link'),
                    icon: _cooldownSeconds > 0
                        ? null
                        : HugeIcons.strokeRoundedMailSend01,
                    loading: _isLoading,
                    onTap: isButtonDisabled ? null : _sendPasswordResetEmail,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
      footer: AuthFooterLink(
        prompt: 'Remembered it?',
        action: 'Log in',
        onTap: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        },
      ),
    );
  }
}
