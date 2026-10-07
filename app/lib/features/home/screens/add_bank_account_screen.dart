import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../shared/widgets/custom_back_button.dart';

class AddBankAccountScreen extends StatefulWidget {
  const AddBankAccountScreen({super.key});

  @override
  State<AddBankAccountScreen> createState() => _AddBankAccountScreenState();
}

class _AddBankAccountScreenState extends State<AddBankAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _bankNameController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  void _showMinimalToast(
    String message, {
    bool isError = false,
    required Color cardColor,
    required Color borderColor,
    required Color textPrimary,
  }) {
    final statusColor = isError
        ? const Color(0xFFFF375F)
        : const Color(0xFF10B981);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: cardColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 16,
      ),
    );
  }

  Future<void> _saveBankAccount(
    Color cardColor,
    Color borderColor,
    Color textPrimary,
  ) async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated");

      await FirebaseFirestore.instance
          .collection("companies")
          .doc(user.uid)
          .update({
            "Bank Accounts": FieldValue.arrayUnion([
              {
                "name": _bankNameController.text.trim(),
                "number": _accountNumberController.text.trim(),
              },
            ]),
          });

      if (mounted) {
        _showMinimalToast(
          "Bank account linked successfully",
          cardColor: cardColor,
          borderColor: borderColor,
          textPrimary: textPrimary,
        );
        Navigator.pop(context, {
          "bankName": _bankNameController.text.trim(),
          "last4": _accountNumberController.text.trim().length >= 4
              ? _accountNumberController.text.trim().substring(
                  _accountNumberController.text.trim().length - 4,
                )
              : _accountNumberController.text.trim(),
        });
      }
    } catch (e) {
      if (mounted) {
        _showMinimalToast(
          "Error linking bank account",
          isError: true,
          cardColor: cardColor,
          borderColor: borderColor,
          textPrimary: textPrimary,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF09090B) : const Color(0xFFF9FAFB);
    final cardColor = isDark
        ? const Color(0xFF141416)
        : const Color(0xFFFFFFFF);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final shadowColor = isDark
        ? Colors.transparent
        : Colors.black.withValues(alpha: 0.04);

    final textPrimary = isDark ? Colors.white : const Color(0xFF09090B);
    final textSecondary = isDark ? Colors.white54 : const Color(0xFF71717A);
    final textTertiary = isDark ? Colors.white38 : const Color(0xFFA1A1AA);
    final accentGreen = const Color(0xFF10B981);

    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(
                context,
                textPrimary,
                textSecondary,
                cardColor,
                borderColor,
              ),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: borderColor),
                      boxShadow: shadowColor == Colors.transparent
                          ? []
                          : [
                              BoxShadow(
                                color: shadowColor,
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: accentGreen.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: accentGreen.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  "NEW LINK",
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: accentGreen,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          _buildTextInput(
                            controller: _bankNameController,
                            label: "BANK NAME",
                            hint: "e.g., HDFC Bank, Chase",
                            icon: Icons.account_balance_rounded,
                            textInputAction: TextInputAction.next,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            textTertiary: textTertiary,
                            borderColor: borderColor,
                            isDark: isDark,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Bank name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          _buildTextInput(
                            controller: _accountNumberController,
                            label: "ACCOUNT NUMBER",
                            hint: "Enter account number",
                            icon: Icons.numbers_rounded,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            textTertiary: textTertiary,
                            borderColor: borderColor,
                            isDark: isDark,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Account number is required';
                              }
                              if (value.trim().length < 8) {
                                return 'Must be at least 8 digits';
                              }
                              if (value.trim().length > 18) {
                                return 'Must be at most 18 digits';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              _buildSubmitButton(textPrimary, bgColor, cardColor, borderColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color cardColor,
    Color borderColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CustomBackButton(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "Payment Methods",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Link Account",
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
    required Color borderColor,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.done,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onTapOutside: (event) => FocusScope.of(context).unfocus(),
            style: TextStyle(
              fontFamily: 'Satoshi',
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: textPrimary,
            decoration: InputDecoration(
              icon: Icon(icon, color: textSecondary, size: 20),
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: 'Satoshi',
                color: textTertiary,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              errorStyle: const TextStyle(
                fontFamily: 'Satoshi',
                color: Color(0xFFFF375F),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
            validator: validator,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(
    Color textPrimary,
    Color bgColor,
    Color cardColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading
              ? null
              : () => _saveBankAccount(cardColor, borderColor, textPrimary),
          style: ElevatedButton.styleFrom(
            backgroundColor: textPrimary,
            foregroundColor: bgColor,
            disabledBackgroundColor: textPrimary.withValues(alpha: 0.5),
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
                    strokeWidth: 2.5,
                    color: bgColor,
                  ),
                )
              : const Text(
                  "Link Bank Account",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
        ),
      ),
    );
  }
}
