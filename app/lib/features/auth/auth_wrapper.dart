import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/screen/login.dart';
import '../company-setup/screen/company_setup_screen.dart';
import '../navigation/screens/main_navigation_wrapper.dart';
import '../../../services/ai_cache_service.dart';
import '../../../services/ai_context_manager.dart';
import '../../../services/user_country_service.dart';
import '../../../services/theme_service.dart';
import '../../../theme/app_theme.dart';

/// Routes between login, company setup and the main app.
///
/// Streams are created once per signed-in user (not on every rebuild), and
/// side effects (currency + theme sync) run only when the user or their
/// profile data actually changes.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  /// How long to wait for a brand-new account's user document before
  /// offering the user a way out. Nothing is signed out automatically.
  static const _missingDocTimeout = Duration(seconds: 30);

  late final Stream<User?> _authStream = FirebaseAuth.instance
      .idTokenChanges();

  String? _uid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;
  String? _currencyInitForUid;
  Map<String, dynamic>? _lastSyncedUserData;

  Timer? _missingDocTimer;
  bool _missingDocTimedOut = false;

  @override
  void dispose() {
    _missingDocTimer?.cancel();
    super.dispose();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocFor(String uid) {
    // Switching accounts without a visible sign-out also clears AI data.
    if (_uid != null && _uid != uid) AiCacheService.clearAllForSignOut();
    if (_uid != uid || _userDocStream == null) {
      _uid = uid;
      _userDocStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots();
      _currencyInitForUid = null;
      _lastSyncedUserData = null;
      _resetMissingDocTimer();
    }
    return _userDocStream!;
  }

  void _resetMissingDocTimer() {
    _missingDocTimer?.cancel();
    _missingDocTimer = null;
    _missingDocTimedOut = false;
  }

  void _startMissingDocTimer() {
    if (_missingDocTimer != null || _missingDocTimedOut) return;
    _missingDocTimer = Timer(_missingDocTimeout, () {
      if (mounted) setState(() => _missingDocTimedOut = true);
    });
  }

  /// Runs after the frame so we never trigger listeners during build.
  void _runSideEffects(String uid, Map<String, dynamic>? userData) {
    final needsCurrency = _currencyInitForUid != uid;
    final needsTheme =
        userData != null &&
        userData['preferredTheme'] != _lastSyncedUserData?['preferredTheme'];
    if (!needsCurrency && !needsTheme) return;

    if (needsCurrency) _currencyInitForUid = uid;
    if (needsTheme) _lastSyncedUserData = userData;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (needsTheme) ThemeService.syncFromUserData(userData);
      if (needsCurrency) {
        UserCountryService.initializeCache().catchError((Object error) {
          debugPrint('Failed to initialize user currency: $error');
        });
      }
    });
  }

  Widget _buildLoadingScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(context.textPrimary),
            ),
            const SizedBox(height: 16),
            Text('Loading...', style: TextStyle(color: context.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String primaryLabel,
    required VoidCallback onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textPrimary, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.textPrimary,
                  foregroundColor: context.appBackground,
                ),
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _retryUserDoc() {
    setState(() {
      _userDocStream = null; // forces a fresh subscription on next build
      _resetMissingDocTimer();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen(context);
        }

        if (snapshot.hasError) {
          return _buildMessage(
            context,
            title: 'Session expired',
            subtitle: 'Please sign in again',
            primaryLabel: 'Refresh Session',
            onPrimary: () => FirebaseAuth.instance.currentUser?.reload(),
            secondaryLabel: 'Sign out',
            onSecondary: () => FirebaseAuth.instance.signOut(),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          // Signed out (any path: settings, session expiry, setup cancel):
          // wipe cached AI insights and chat history from this device.
          if (_uid != null) {
            AiCacheService.clearAllForSignOut();
            AiContextManager().reset();
          }
          _uid = null;
          _userDocStream = null;
          _resetMissingDocTimer();
          return const LoginScreen();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userDocFor(user.uid),
          builder: (context, userSnapshot) {
            if (userSnapshot.hasError) {
              debugPrint('User snapshot error: ${userSnapshot.error}');
              return _buildMessage(
                context,
                title: 'Connection Error',
                subtitle: 'Please check your internet connection',
                primaryLabel: 'Retry',
                onPrimary: _retryUserDoc,
              );
            }

            final doc = userSnapshot.data;
            if (doc == null) return _buildLoadingScreen(context);

            if (!doc.exists) {
              // Not in local cache yet, or a new account whose profile is
              // still being written. Keep waiting on the live stream; only
              // after a generous timeout offer a choice instead of silently
              // signing the user out (slow networks hit this otherwise).
              if (doc.metadata.isFromCache || !_missingDocTimedOut) {
                _startMissingDocTimer();
                return _buildLoadingScreen(context);
              }
              return _buildMessage(
                context,
                title: 'Profile not found',
                subtitle:
                    "We couldn't load your account profile. Check your connection and try again.",
                primaryLabel: 'Retry',
                onPrimary: _retryUserDoc,
                secondaryLabel: 'Sign out',
                onSecondary: () => FirebaseAuth.instance.signOut(),
              );
            }

            _resetMissingDocTimer();
            final userData = doc.data();
            _runSideEffects(user.uid, userData);

            if (userData == null || userData['companySetup'] != true) {
              return const CompanySetupScreen();
            }
            return const MainNavigationWrapper();
          },
        );
      },
    );
  }
}
