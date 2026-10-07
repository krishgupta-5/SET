import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/screen/login.dart';
import '../company-setup/screen/company_setup_screen.dart';
import '../navigation/screens/main_navigation_wrapper.dart';
import '../../../services/user_country_service.dart';
import '../../../services/theme_service.dart';
import '../../../theme/app_theme.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

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

  /// Initialize user currency after successful login
  void _initializeUserCurrency() {
    // Initialize the currency cache asynchronously
    UserCountryService.initializeCache()
        .then((_) {
          debugPrint('💰 DEBUG: User currency initialized successfully');
        })
        .catchError((error) {
          debugPrint('❌ DEBUG: Failed to initialize user currency: $error');
        });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance
          .idTokenChanges(), // Better for detecting email verification changes
      builder: (context, snapshot) {
        // Show loading spinner while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen(context);
        }

        // Handle token refresh errors
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: context.appBackground,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    "Session expired",
                    style: TextStyle(color: context.textPrimary, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Please sign in again",
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      await FirebaseAuth.instance.currentUser?.reload();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.textPrimary,
                      foregroundColor: context.appBackground,
                    ),
                    child: const Text("Refresh Session"),
                  ),
                ],
              ),
            ),
          );
        }

        // User is not logged in, show login screen
        if (!snapshot.hasData || snapshot.data == null) {
          return const LoginScreen();
        }

        // User is logged in, check if they have completed company setup
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingScreen(context);
            }

            // Handle Firestore errors
            if (userSnapshot.hasError) {
              debugPrint('❌ DEBUG: User snapshot error: ${userSnapshot.error}');
              return Scaffold(
                backgroundColor: context.appBackground,
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Connection Error",
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Please check your internet connection",
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AuthWrapper(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.textPrimary,
                          foregroundColor: context.appBackground,
                        ),
                        child: const Text("Retry"),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (!userSnapshot.hasData) {
              return _buildLoadingScreen(context);
            }

            debugPrint(
              '🔍 DEBUG: User document exists: ${userSnapshot.data!.exists} (fromCache: ${userSnapshot.data!.metadata.isFromCache})',
            );
            debugPrint(
              '🔍 DEBUG: User document data: ${userSnapshot.data?.data()}',
            );

            // If the snapshot is from local cache and the document is not yet in local cache (exists == false),
            // wait for Cloud Firestore to fetch the live document from the server instead of signing out.
            if (!userSnapshot.data!.exists &&
                userSnapshot.data!.metadata.isFromCache) {
              debugPrint(
                '🔍 DEBUG: Document not found in local cache yet, waiting for server response...',
              );
              return _buildLoadingScreen(context);
            }

            // If user document doesn't exist on server (e.g. account data was deleted or currently being created),
            if (!userSnapshot.data!.exists) {
              final authUser = FirebaseAuth.instance.currentUser;
              final creationTime = authUser?.metadata.creationTime;
              // Give newly created accounts a 15-second grace period for the Firestore document creation to complete.
              if (creationTime != null &&
                  DateTime.now().difference(creationTime).inSeconds < 15) {
                debugPrint(
                  '🔍 DEBUG: Account created recently, waiting for document creation...',
                );
                return _buildLoadingScreen(context);
              }

              debugPrint(
                '🔍 DEBUG: User document does not exist on server, redirecting to login',
              );
              // Asynchronously sign out so they don't get stuck in a weird state
              WidgetsBinding.instance.addPostFrameCallback((_) {
                FirebaseAuth.instance.signOut();
              });
              return const LoginScreen();
            }

            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
            debugPrint('🔍 DEBUG: User data: $userData');
            debugPrint(
              '🔍 DEBUG: Company setup status: ${userData?['companySetup']}',
            );

            // Preload and sync theme preference instantaneously from user profile data
            ThemeService.syncFromUserData(userData);

            if (userData == null || userData['companySetup'] != true) {
              debugPrint(
                '🔍 DEBUG: Company setup not completed, going to company setup screen',
              );
              // Initialize user currency for users in setup process
              _initializeUserCurrency();
              return const CompanySetupScreen();
            }

            // User has completed setup, go to main navigation
            debugPrint(
              '🔍 DEBUG: Company setup completed, going to main navigation',
            );

            // Initialize user currency after successful login
            _initializeUserCurrency();

            return const MainNavigationWrapper();
          },
        );
      },
    );
  }
}
