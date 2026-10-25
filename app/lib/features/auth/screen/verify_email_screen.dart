import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:async';

import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_ui.dart';
import '../widgets/auth_kit.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isResending = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Start periodic refresh to check verification status
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (mounted) {
        try {
          await FirebaseAuth.instance.currentUser?.reload();
          if (mounted) setState(() {});
        } catch (e) {
          // Ignore errors during periodic refresh
        }
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        if (mounted) showRxToast(context, 'Verification email sent!');
      }
    } catch (e) {
      if (mounted) {
        showRxToast(
          context,
          'Failed to send verification email',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  Future<void> _checkVerified() async {
    setState(() {
      _isResending = true; // Use loading state
    });

    try {
      // Force reload multiple times to ensure we get latest status
      await FirebaseAuth.instance.currentUser?.reload();
      await Future.delayed(const Duration(milliseconds: 500)); // Small delay
      await FirebaseAuth.instance.currentUser?.reload();

      // Check if email is now verified
      final user = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      if (user != null && user.emailVerified) {
        // Email is verified, AuthWrapper will handle navigation
        showRxToast(context, 'Email verified! Redirecting...');
      } else {
        // Email not verified yet
        showRxToast(
          context,
          'Email not verified yet. Please check your inbox (including spam folder) and try again.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        showRxToast(
          context,
          'Error checking verification status. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  Future<void> _forceRefresh() async {
    setState(() {
      _isResending = true;
    });

    try {
      // Force sign out and sign back in to trigger token refresh
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;

      if (email != null) {
        await FirebaseAuth.instance.signOut();

        // Small delay then sign back in
        await Future.delayed(const Duration(milliseconds: 500));

        // This will trigger AuthWrapper to show login screen
        if (mounted) {
          showRxToast(
            context,
            'Please sign in again to refresh your verification status.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showRxToast(
          context,
          'Error refreshing session. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  static const _cfoLines = [
    'One quick step before your numbers.',
    'Tap the link I just emailed you.',
    "I'll notice the moment you verify.",
  ];

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email;

    return AuthPage(
      compactText: "I'll notice the moment you verify",
      hero: (h) => AuthHero(
        lines: _cfoLines,
        height: h,
        chips: const [
          AuthChipData(
            HugeIcons.strokeRoundedMailValidation01,
            'Verification',
            'Sent',
            up: true,
          ),
          AuthChipData(
            HugeIcons.strokeRoundedRefresh,
            'Auto check',
            'Every 5s',
          ),
        ],
      ),
      body: [
        AuthStep(
          2,
          child: AuthTitle(
            title: 'Check your inbox',
            subtitle: email == null
                ? 'We sent you a verification link. Open it to continue.'
                : 'We sent a verification link to $email.',
          ),
        ),
        const SizedBox(height: 16),
        AuthStep(
          3,
          child: AuthGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthNotice(
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  tone: AuthNoticeTone.neutral,
                  text:
                      "Can't find it? Look in spam. This page updates on its own once you verify.",
                ),
                const SizedBox(height: 14),
                AuthStep(
                  4,
                  child: AuthPrimaryButton(
                    label: "I've verified",
                    icon: HugeIcons.strokeRoundedTick02,
                    loading: _isResending,
                    onTap: _isResending ? null : _checkVerified,
                  ),
                ),
                const SizedBox(height: 10),
                AuthStep(
                  5,
                  child: RxButton(
                    label: 'Resend email',
                    icon: HugeIcons.strokeRoundedMailSend01,
                    style: RxButtonStyle.secondary,
                    onTap: _isResending ? null : _resendVerificationEmail,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AuthTextLink(
            label: 'Refresh session',
            onTap: _isResending ? () {} : _forceRefresh,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('·', style: RxText.label(context)),
          ),
          AuthTextLink(
            label: 'Sign out',
            onTap: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
    );
  }
}
