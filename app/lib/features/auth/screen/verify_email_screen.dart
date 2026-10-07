import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../theme/app_theme.dart';

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
          setState(() {});
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF30D158),
              content: Text(
                'Verification email sent!',
                style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF3B30),
            content: Text(
              'Failed to send verification email',
              style: TextStyle(fontFamily: 'Satoshi', color: Colors.white),
            ),
          ),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Email Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: context.cardBackground,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.borderColor),
                    boxShadow: context.cardShadow,
                  ),
                  child: Icon(
                    Icons.email_outlined,
                    color: context.textPrimary,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                Text(
                  "Verify Your Email",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Description
                Text(
                  "We've sent a verification link to your email address. Please check your inbox and click the link to continue.",
                  style: TextStyle(
                    fontFamily: 'Satoshi',
                    color: context.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Resend Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isResending ? null : _resendVerificationEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.textPrimary,
                      foregroundColor: context.appBackground,
                      disabledBackgroundColor: context.textTertiary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isResending
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                context.appBackground,
                              ),
                            ),
                          )
                        : Text(
                            "Resend Email",
                            style: TextStyle(
                              fontFamily: 'Satoshi',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // I've Verified Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        _isResending = true; // Use loading state
                      });

                      // Capture messenger before async gap
                      final messenger = ScaffoldMessenger.of(context);

                      try {
                        // Force reload multiple times to ensure we get latest status
                        await FirebaseAuth.instance.currentUser?.reload();
                        await Future.delayed(
                          const Duration(milliseconds: 500),
                        ); // Small delay
                        await FirebaseAuth.instance.currentUser?.reload();

                        // Check if email is now verified
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null && user.emailVerified) {
                          // Email is verified, AuthWrapper will handle navigation
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF30D158),
                                content: Text(
                                  'Email verified! Redirecting...',
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: Colors.white,
                                  ),
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        } else {
                          // Email not verified yet
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFFFF3B30),
                                content: Text(
                                  'Email not verified yet. Please check your inbox (including spam folder) and try again.',
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: Colors.white,
                                  ),
                                ),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFFFF3B30),
                              content: Text(
                                'Error checking verification status. Please try again.',
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isResending = false;
                          });
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF30D158),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      "I've Verified",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Force Refresh Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        _isResending = true;
                      });

                      // Capture messenger before async gap
                      final messenger = ScaffoldMessenger.of(context);

                      try {
                        // Force sign out and sign back in to trigger token refresh
                        final user = FirebaseAuth.instance.currentUser;
                        final email = user?.email;

                        if (email != null) {
                          await FirebaseAuth.instance.signOut();

                          // Small delay then sign back in
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );

                          // This will trigger AuthWrapper to show login screen
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF30D158),
                                content: Text(
                                  'Please sign in again to refresh your verification status.',
                                  style: TextStyle(
                                    fontFamily: 'Satoshi',
                                    color: Colors.white,
                                  ),
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFFFF3B30),
                              content: Text(
                                'Error refreshing session. Please try again.',
                                style: TextStyle(
                                  fontFamily: 'Satoshi',
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isResending = false;
                          });
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      "Force Refresh",
                      style: TextStyle(
                        fontFamily: 'Satoshi',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sign Out Button
                TextButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                  child: Text(
                    "Sign Out",
                    style: TextStyle(
                      fontFamily: 'Satoshi',
                      color: context.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
