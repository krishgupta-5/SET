import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && currentUser.email != null) {
      _emailController.text = currentUser.email!;
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

  void _showMinimalToast(String message, {bool isError = false}) =>
      showRxToast(context, message, isError: isError);

  Future<void> _sendPasswordResetEmail() async {
    FocusScope.of(context).unfocus();

    if (_emailController.text.trim().isEmpty) {
      _showMinimalToast('Email address is required', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );

      if (mounted) {
        _showMinimalToast('Secure link sent! Please check your inbox.');
        _startCooldown();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'too-many-requests':
          errorMessage = 'Too many requests. Try again later.';
          _startCooldown();
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        default:
          errorMessage = 'Failed to send link: ${e.message}';
      }

      if (mounted) {
        _showMinimalToast(errorMessage, isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showMinimalToast(
          'An unexpected error occurred. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final email = _emailController.text;
    final disabled = _isLoading || _cooldownSeconds > 0 || email.isEmpty;

    return Scaffold(
      backgroundColor: rx.background,
      body: AnnotatedRegion(
        value: context.rxOverlayStyle,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const RxTopBar(title: 'Set password'),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    RxReveal.index(
                      0,
                      child: Column(
                        children: [
                          const RxEmptyArt(
                            icon: HugeIcons.strokeRoundedMail01,
                            scene: RxArtScene.mail,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'We\'ll email you a secure link',
                            textAlign: TextAlign.center,
                            style: RxText.title(context).copyWith(fontSize: 22),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Open it to set a password, so you can also sign in with email instead of Google.',
                            textAlign: TextAlign.center,
                            style: RxText.caption(
                              context,
                            ).copyWith(fontSize: 14, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    RxReveal.index(
                      1,
                      child: RxCard(
                        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                        child: Row(
                          children: [
                            const RxIconTile(
                              icon: HugeIcons.strokeRoundedMail01,
                              size: 38,
                              iconSize: 19,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sent to',
                                    style: RxText.caption(context),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    email.isEmpty
                                        ? 'No email on this account'
                                        : email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: RxText.body(context),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              RxBottomBar(
                child: RxButton(
                  label: _cooldownSeconds > 0
                      ? 'Resend in ${_cooldownSeconds}s'
                      : 'Send secure link',
                  icon: _cooldownSeconds > 0
                      ? null
                      : HugeIcons.strokeRoundedSent,
                  loading: _isLoading,
                  onTap: disabled ? null : _sendPasswordResetEmail,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
