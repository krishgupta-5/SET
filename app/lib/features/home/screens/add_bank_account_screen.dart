import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../widgets/rx_ui.dart';

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
    final statusColor = isError ? context.rx.negative : context.rx.positive;

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
                style: RxText.body(context, color: textPrimary),
              ),
            ),
          ],
        ),
        backgroundColor: cardColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 0,
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
    final rx = context.rx;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: rx.background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              const RxTopBar(title: 'Add bank account'),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Link an account',
                          style: RxText.title(context).copyWith(fontSize: 24),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tag expenses to the account they were paid from.',
                          style: RxText.label(context),
                        ),
                        const SizedBox(height: 24),
                        _buildTextInput(
                          controller: _bankNameController,
                          label: 'Bank name',
                          hint: 'e.g. HDFC Bank, Chase',
                          icon: HugeIcons.strokeRoundedBank,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Bank name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextInput(
                          controller: _accountNumberController,
                          label: 'Account number',
                          hint: '8 to 18 digits',
                          icon: HugeIcons.strokeRoundedCreditCard,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
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
                        Row(
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedSecurityLock,
                              color: rx.textTertiary,
                              size: 14,
                              strokeWidth: 1.8,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Only the last 4 digits are shown in the app.',
                                style: RxText.caption(
                                  context,
                                  color: rx.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required List<List<dynamic>> icon,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.done,
    String? Function(String?)? validator,
  }) {
    final rx = context.rx;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: RxText.label(context).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onTapOutside: (event) => FocusScope.of(context).unfocus(),
          style: RxText.body(context),
          cursorColor: rx.textPrimary,
          decoration: InputDecoration(
            filled: true,
            fillColor: rx.surface,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: HugeIcon(
                icon: icon,
                color: rx.textSecondary,
                size: 20,
                strokeWidth: 1.7,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 44),
            hintText: hint,
            hintStyle: RxText.body(
              context,
              color: rx.textTertiary,
            ).copyWith(fontWeight: FontWeight.w400),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
            // Inputs keep a visible border for 3:1 boundary contrast.
            enabledBorder: border(rx.textPrimary.withValues(alpha: 0.12)),
            focusedBorder: border(rx.textPrimary, 1.5),
            errorBorder: border(rx.negative),
            focusedErrorBorder: border(rx.negative, 1.5),
            errorStyle: RxText.caption(context, color: rx.negative),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final rx = context.rx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: RxPressable(
        onTap: _isLoading
            ? null
            : () => _saveBankAccount(rx.surface, rx.hairline, rx.textPrimary),
        semanticLabel: 'Link bank account',
        child: Container(
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            color: _isLoading ? rx.inverse.withValues(alpha: 0.5) : rx.inverse,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: _isLoading
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: rx.onInverse,
                  ),
                )
              : Text(
                  'Link bank account',
                  style: RxText.body(
                    context,
                    color: rx.onInverse,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}
