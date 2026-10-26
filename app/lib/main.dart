import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:startup_expense_tracker/features/auth/auth_wrapper.dart';
import 'package:startup_expense_tracker/firebase_options.dart';
import 'package:startup_expense_tracker/services/ai_cache_service.dart';
import 'package:startup_expense_tracker/services/ai_context_manager.dart';
import 'package:startup_expense_tracker/services/financial_data_service.dart';
import 'package:startup_expense_tracker/services/file_proxy_http.dart';
import 'package:startup_expense_tracker/services/user_country_service.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';
import 'package:startup_expense_tracker/services/theme_service.dart';
import 'theme/app_theme.dart';

void main() async {
  // Must run before any plugin access.
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Image.network / NetworkImage for stored files hit the backend file
  // proxy, which needs the user's Firebase token (the bot token no longer
  // ships in the app). Attach it automatically.
  HttpOverrides.global = FileProxyHttpOverrides();
  FileProxyHttpOverrides.startTokenRefresh();

  // Initialize decoupled domain event listeners
  AiContextManager().initListeners();

  // Initialize country code cache early for instant currency display
  await UserCountryService.initializeCache();

  // Initialize currency preference service
  CurrencyPreferenceService.initialize();

  // Initialize theme preference from local disk cache BEFORE runApp
  // This ensures the app boots instantly in the exact cached theme (zero flash!)
  await ThemeService.initializeCache();

  // Make status bar transparent globally so it blends with backgrounds
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // Default fallback
    ),
  );

  // Enable edge-to-edge mode (standard for modern apps like Zomato, Google Apps, etc.)
  // This keeps the status bar visible but fully transparent so the app draws underneath it.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const FinancialDashboardApp());
}

class FinancialDashboardApp extends StatefulWidget {
  const FinancialDashboardApp({super.key});

  @override
  State<FinancialDashboardApp> createState() => _FinancialDashboardAppState();
}

class _FinancialDashboardAppState extends State<FinancialDashboardApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<User?>? _authSub;

  // uid seen on the last auth event; '' until the first event arrives.
  String? _lastUid = '';

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// On any account change (sign-out, sign-in, switch), drop every
  /// per-user in-memory cache and rebuild the whole screen stack from a
  /// fresh AuthWrapper. Some flows (sign-up, company setup) replace
  /// AuthWrapper in the stack, so without this the previous account's
  /// screens and data stayed alive until a manual refresh.
  Future<void> _onAuthChanged(User? user) async {
    final uid = user?.uid;
    final isFirstEvent = _lastUid == '';
    final changed = _lastUid != uid;
    _lastUid = uid;
    if (isFirstEvent || !changed) return;

    UserCountryService.reset();
    FinancialDataService.clearAllCache();
    AiContextManager().reset();
    await AiCacheService.clearAllForSignOut();
    if (uid != null) {
      CurrencyPreferenceService.reloadForCurrentUser();
    }

    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (context, themeMode, child) {
        final isDark = themeMode == ThemeMode.dark;
        return ShadTheme(
          data: isDark ? AppTheme.darkShadTheme : AppTheme.lightShadTheme,
          child: MaterialApp(
            navigatorKey: _navigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'RunwayX',
            themeMode: themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const AuthWrapper(),
          ),
        );
      },
    );
  }
}
