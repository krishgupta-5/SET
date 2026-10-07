import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppTheme {
  // Colors (Preserved legacy dark constants)
  static const Color background = Color(0xFF09090B);
  static const Color cardDark = Color(0xFF141416);
  static const Color accentWhite = Colors.white;
  static const Color textGrey = Color(0xFFA1A1AA);

  // Brand Colors (Neon Fintech Accents)
  static const Color greenSafe = Color(0xFF10B981);
  static const Color yellowWarning = Color(0xFFF59E0B);
  static const Color redCritical = Color(0xFFFF375F);
  static const Color credBlue = Color(0xFF3B82F6);

  // Fonts
  static const String fontSerif = 'Times New Roman';
  static const String fontSans = 'Satoshi';

  // Text Styles
  static TextStyle headerStyle = const TextStyle(
    fontFamily: 'Satoshi',
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: accentWhite,
    letterSpacing: -1.0,
  );

  static TextStyle sectionTitleStyle = const TextStyle(
    fontFamily: 'Satoshi',
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: textGrey,
    letterSpacing: 1.5,
  );

  static TextStyle bodyStyle = const TextStyle(
    fontFamily: 'Satoshi',
    fontSize: 14,
    color: accentWhite,
  );

  // --- Theme Data Definitions ---

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Satoshi',
      scaffoldBackgroundColor: const Color(0xFF09090B),
      colorScheme: ColorScheme.fromSeed(
        seedColor: credBlue,
        brightness: Brightness.dark,
        surface: const Color(0xFF141416),
      ),
      useMaterial3: true,
      iconTheme: const IconThemeData(color: Colors.white),
      dividerColor: Colors.white.withValues(alpha: 0.06),
      cardColor: const Color(0xFF141416),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: 'Satoshi',
      scaffoldBackgroundColor: const Color(
        0xFFF9FAFB,
      ), // Crisp, modern cool-gray
      colorScheme: ColorScheme.fromSeed(
        seedColor: credBlue,
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      useMaterial3: true,
      iconTheme: const IconThemeData(color: Color(0xFF09090B)),
      dividerColor: Colors.black.withValues(alpha: 0.06),
      cardColor: Colors.white,
    );
  }

  static ShadThemeData get darkShadTheme {
    return ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadSlateColorScheme.dark(),
      textTheme: ShadTextTheme(family: 'Satoshi'),
    );
  }

  static ShadThemeData get lightShadTheme {
    return ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
      textTheme: ShadTextTheme(family: 'Satoshi'),
    );
  }
}

/// Adaptive theme colors extension on BuildContext
/// Provides instant access to vibrant, high-contrast colors depending on current theme mode
extension AppThemeColors on BuildContext {
  // --- CORE THEME CHECK ---
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  // --- BACKGROUNDS ---
  // The light mode background is now a deeper cool-grey, making pure white cards POP.
  Color get appBackground =>
      isDarkMode ? const Color(0xFF09090B) : const Color(0xFFF1F3F5);

  // Cards remain pure white in light mode for maximum contrast.
  Color get cardBackground =>
      isDarkMode ? const Color(0xFF141416) : const Color(0xFFFFFFFF);
  Color get cardSecondaryBackground =>
      isDarkMode ? const Color(0xFF1E1E20) : const Color(0xFFFAFAFA);

  // --- BORDERS ---
  // Sharper borders in light mode define the edges of the floating components.
  Color get borderColor => isDarkMode
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFE5E7EB);
  Color get borderSubtle => isDarkMode
      ? Colors.white.withValues(alpha: 0.04)
      : const Color(0xFFF3F4F6);
  Color get borderColorStrong => isDarkMode
      ? Colors.white.withValues(alpha: 0.15)
      : const Color(0xFFD1D5DB);

  // --- TYPOGRAPHY ---
  Color get textPrimary => isDarkMode ? Colors.white : const Color(0xFF09090B);
  Color get textSecondary =>
      isDarkMode ? Colors.white54 : const Color(0xFF71717A);
  Color get textTertiary =>
      isDarkMode ? Colors.white38 : const Color(0xFFA1A1AA);
  Color get textSubtle => isDarkMode ? Colors.white24 : const Color(0xFFE4E4E7);

  // --- ICONS ---
  Color get iconPrimary => isDarkMode ? Colors.white : const Color(0xFF09090B);
  Color get iconSecondary =>
      isDarkMode ? Colors.white54 : const Color(0xFF71717A);

  // --- THE "POP" SHADOWS ---
  // Apply this to the boxShadow property of your Bottom Nav, FAB, and Cards!
  List<BoxShadow> get cardShadow => isDarkMode
      ? [] // No shadows in dark mode (relies on borders)
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ];

  // --- Glass & subtle fills ---
  Color get glassBackground => isDarkMode
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.black.withValues(alpha: 0.04);
  Color get glassBackgroundStrong => isDarkMode
      ? Colors.white.withValues(alpha: 0.1)
      : Colors.black.withValues(alpha: 0.08);

  // --- Inputs & Nav ---
  Color get inputBackground =>
      isDarkMode ? const Color(0xFF1C1C1E) : Colors.white;
  Color get navBackground =>
      isDarkMode ? const Color(0xFF141416) : Colors.white;
  Color get navActiveTab => isDarkMode ? Colors.white : const Color(0xFF09090B);

  // --- Accents & Brand ---
  Color get primaryColor => isDarkMode ? Colors.white : const Color(0xFF09090B);
  Color get accentColor => const Color(0xFF3B82F6);
}
