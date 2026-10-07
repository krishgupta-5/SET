import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:startup_expense_tracker/features/auth/screen/login.dart';
import '../../../shared/widgets/error_popup.dart';
import '../services/auth_service.dart';
import '../../../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  /// Optional email to pre-fill (e.g. passed from login screen).
  final String? prefillEmail;

  const ForgotPasswordScreen({super.key, this.prefillEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = false;
  bool _emailSent = false;
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

  void _showGoogleAccountDialog() {
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
          'Google Account Detected',
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This email is linked to a Google account. You don\'t need a password — just use the "Google Sign-In" button on the login screen.',
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
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
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

  Future<void> _sendPasswordResetEmail() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        _buildHeader(context),
                        const SizedBox(height: 48),
                        _buildLabel(context, "EMAIL ADDRESS"),
                        const SizedBox(height: 8),
                        _buildInputField(
                          context: context,
                          controller: _emailController,
                          hint: "name@company.com",
                          action: TextInputAction.done,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
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
                          },
                        ),
                        // Show success hint after email is sent
                        if (_emailSent) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF30D158,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(
                                  0xFF30D158,
                                ).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFF30D158),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    "Check your inbox (and spam folder) for the reset link.",
                                    style: TextStyle(
                                      fontFamily: 'Satoshi',
                                      color: const Color(0xFF30D158),
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 48),
                        _buildSendButton(context),
                        const Spacer(),
                        _buildBackToLogin(context),
                        const SizedBox(height: 16),
                      ],
                    ),
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
        GestureDetector(
          onTap: () => Navigator.pop(context),
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
          "Reset Password",
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
          "Enter the email associated with your account and we'll send you a reset link.",
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: context.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
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
    TextInputAction action = TextInputAction.next,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      textInputAction: action,
      keyboardType: keyboardType,
      validator: validator,
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
        filled: true,
        fillColor: context.cardBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.textPrimary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF3B30)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFF3B30)),
        ),
        errorStyle: TextStyle(
          fontFamily: 'Satoshi',
          color: const Color(0xFFFF3B30),
        ),
      ),
    );
  }

  Widget _buildSendButton(BuildContext context) {
    final bool isButtonDisabled = _isLoading || _cooldownSeconds > 0;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isButtonDisabled ? null : _sendPasswordResetEmail,
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
                _cooldownSeconds > 0
                    ? "Resend in ${_cooldownSeconds}s"
                    : (_emailSent ? "Send Again" : "Send Reset Link"),
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isButtonDisabled
                      ? context.appBackground.withValues(alpha: 0.6)
                      : context.appBackground,
                ),
              ),
      ),
    );
  }

  Widget _buildBackToLogin(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Remembered your password? ",
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
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
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
        ),
      ],
    );
  }
}
