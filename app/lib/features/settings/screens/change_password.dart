import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
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

  void _showMinimalToast(String message, {bool isError = false}) =>
      showRxToast(context, message, isError: isError);

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
      if (mounted) _showMinimalToast(message, isError: true);
    } catch (e) {
      if (!mounted) return;
      _showMinimalToast("An unexpected error occurred.", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Change password'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    RxReveal.index(
                      0,
                      child: RxPasswordInput(
                        controller: _oldPassController,
                        label: 'Current password',
                        hint: 'Enter current password',
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RxPasswordInput(
                            controller: _newPassController,
                            label: 'New password',
                            hint: 'Enter new password',
                          ),
                          const SizedBox(height: 16),
                          RxPasswordInput(
                            controller: _confirmPassController,
                            label: 'Confirm new password',
                            hint: 'Re-enter new password',
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _changePassword(),
                          ),
                          const SizedBox(height: 16),
                          RxPasswordChecklist(
                            rules: {
                              'At least 8 characters': _hasMinLength,
                              'One uppercase letter': _hasUppercase,
                              'One number or symbol': _hasNumberOrSymbol,
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: 'Update password',
                  loading: _isLoading,
                  onTap: _changePassword,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
