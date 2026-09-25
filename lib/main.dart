import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:startup_expense_tracker/features/auth/auth_wrapper.dart';
import 'package:startup_expense_tracker/firebase_options.dart';
import 'package:startup_expense_tracker/services/ai_context_manager.dart';
import 'package:startup_expense_tracker/services/user_country_service.dart';
import 'package:startup_expense_tracker/services/currency_preference_service.dart';
import 'package:startup_expense_tracker/services/theme_service.dart';
import 'theme/app_theme.dart';

void main() async {
  await dotenv.load(fileName: ".env.local");
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize decoupled domain event listeners
  AiContextManager().initListeners();

  // Initialize country code cache early for instant currency display
  await UserCountryService.initializeCache();

  // Initialize currency preference service
  CurrencyPreferenceService.initialize();

  // Initialize theme preference from local disk cache BEFORE runApp
  // This ensures the app boots instantly in the exact cached theme (zero flash!)
  await ThemeService.initializeCache();

  runApp(const FinancialDashboardApp());
}

class FinancialDashboardApp extends StatelessWidget {
  const FinancialDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (context, themeMode, child) {
        final isDark = themeMode == ThemeMode.dark;
        return ShadTheme(
          data: isDark ? AppTheme.darkShadTheme : AppTheme.lightShadTheme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Financial Dashboard',
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
