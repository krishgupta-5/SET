import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  final TextEditingController _oldPassController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasNumberOrSymbol = false;

  @override
  void initState() {
    super.initState();
    _newPassController.addListener(_validatePassword);
  }

  @override
  void dispose() {
    _newPassController.removeListener(_validatePassword);
    _oldPassController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  void _validatePassword() {
    final pass = _newPassController.text;
    setState(() {
      _hasMinLength = pass.length >= 8;
      _hasUppercase = pass.contains(RegExp(r'[A-Z]'));
      _hasNumberOrSymbol = pass.contains(RegExp(r'[0-9!@#\$&*~]'));
    });
  }

  void _showMinimalToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError
                  ? const Color(0xFFFF453A)
                  : const Color(0xFF30D158),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.cardBackground,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        duration: const Duration(seconds: 3),
        elevation: 0,
      ),
    );
  }

  Future<void> _changePassword() async {
    FocusScope.of(context).unfocus();

    final oldPass = _oldPassController.text.trim();
    final newPass = _newPassController.text.trim();
    final confirmPass = _confirmPassController.text.trim();

    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      _showMinimalToast("Please fill in all fields.", isError: true);
      return;
    }
    if (newPass != confirmPass) {
      _showMinimalToast("New passwords do not match.", isError: true);
      return;
    }
    if (!_hasMinLength || !_hasUppercase || !_hasNumberOrSymbol) {
      _showMinimalToast(
        "New password does not meet all requirements.",
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception("No authenticated user found.");
      }

      final AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: oldPass,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPass);

      if (mounted) {
        Navigator.pop(context);
        _showMinimalToast("Password updated successfully!");
      }
    } on FirebaseAuthException catch (e) {
      String message = "Failed to update password.";
      if (e.code == 'wrong-password') {
        message = "The current password you entered is incorrect.";
      } else if (e.code == 'weak-password') {
        message = "The new password provided is too weak.";
      } else {
        message = e.message ?? message;
      }
      _showMinimalToast(message, isError: true);
    } catch (e) {
      _showMinimalToast("An unexpected error occurred.", isError: true);
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
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          "Change Password",
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            color: context.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _buildSectionLabel("CURRENT PASSWORD"),
                        const SizedBox(height: 8),
                        _buildPasswordField(
                          controller: _oldPassController,
                          hint: "Enter current password",
                          obscureText: _obscureOld,
                          textInputAction: TextInputAction.next,
                          onToggle: () =>
                              setState(() => _obscureOld = !_obscureOld),
                        ),
                        const SizedBox(height: 32),
                        _buildSectionLabel("NEW PASSWORD"),
                        const SizedBox(height: 8),
                        _buildPasswordField(
                          controller: _newPassController,
                          hint: "Enter new password",
                          obscureText: _obscureNew,
                          textInputAction: TextInputAction.next,
                          onToggle: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionLabel("CONFIRM NEW PASSWORD"),
                        const SizedBox(height: 8),
                        _buildPasswordField(
                          controller: _confirmPassController,
                          hint: "Re-enter new password",
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          onToggle: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                        const SizedBox(height: 40),
                        _buildRequirements(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_back,
                    color: context.textSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Back",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Satoshi',
        color: context.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscureText,
    required VoidCallback onToggle,
    TextInputAction textInputAction = TextInputAction.next,
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
        obscureText: obscureText,
        textInputAction: textInputAction,
        onTapOutside: (event) => FocusScope.of(context).unfocus(),
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
          prefixIcon: Icon(
            Icons.lock_outline,
            color: context.iconSecondary,
            size: 20,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: IconButton(
            icon: Icon(
              obscureText
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: context.iconSecondary,
              size: 20,
            ),
            onPressed: onToggle,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildRequirements() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel("PASSWORD REQUIREMENTS"),
          const SizedBox(height: 20),
          _buildRequirementRow("At least 8 characters", _hasMinLength),
          const SizedBox(height: 16),
          _buildRequirementRow("One uppercase character", _hasUppercase),
          const SizedBox(height: 16),
          _buildRequirementRow("One number or symbol", _hasNumberOrSymbol),
        ],
      ),
    );
  }

  Widget _buildRequirementRow(String text, bool isMet) {
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: Icon(
            isMet ? Icons.check_circle : Icons.circle_outlined,
            key: ValueKey<bool>(isMet),
            color: isMet ? const Color(0xFF30D158) : context.textTertiary,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(
            fontFamily: 'Satoshi',
            color: isMet ? context.textPrimary : context.textSecondary,
            fontSize: 13,
            fontWeight: isMet ? FontWeight.w500 : FontWeight.w400,
          ),
          child: Text(text),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    final btnBg = context.isDarkMode ? Colors.white : Colors.black;
    final btnText = context.isDarkMode ? Colors.black : Colors.white;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appBackground,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _changePassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: btnBg,
            foregroundColor: btnText,
            disabledBackgroundColor: context.textTertiary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: btnText,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  "Update Password",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
