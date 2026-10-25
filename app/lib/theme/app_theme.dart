import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'rx_colors.dart';

export 'rx_colors.dart';

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
    fontFamily: 'Geist',
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: accentWhite,
    letterSpacing: -1.0,
  );

  static TextStyle sectionTitleStyle = const TextStyle(
    fontFamily: 'Geist',
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: textGrey,
    letterSpacing: 1.5,
  );

  static TextStyle bodyStyle = const TextStyle(
    fontFamily: 'Geist',
    fontSize: 14,
    color: accentWhite,
  );

  // --- Theme Data Definitions ---

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Geist',
      scaffoldBackgroundColor: RxColors.dark.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: credBlue,
        brightness: Brightness.dark,
        surface: const Color(0xFF141416),
      ),
      useMaterial3: true,
      iconTheme: const IconThemeData(color: Colors.white),
      dividerColor: Colors.white.withValues(alpha: 0.06),
      cardColor: const Color(0xFF141416),
      extensions: const [RxColors.dark],
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: 'Geist',
      scaffoldBackgroundColor: RxColors.light.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: credBlue,
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      useMaterial3: true,
      iconTheme: const IconThemeData(color: Color(0xFF09090B)),
      dividerColor: Colors.black.withValues(alpha: 0.06),
      cardColor: Colors.white,
      extensions: const [RxColors.light],
    );
  }

  static ShadThemeData get darkShadTheme {
    return ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadSlateColorScheme.dark(),
      textTheme: ShadTextTheme(family: 'Geist'),
    );
  }

  static ShadThemeData get lightShadTheme {
    return ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
      textTheme: ShadTextTheme(family: 'Geist'),
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
  // Same paper colour as the redesign palette, so every page matches the
  // strip behind the floating tab bar.
  Color get appBackground => rx.background;

  // Legacy tokens now resolve to the redesign palette (RxColors), so screens
  // that haven't been rebuilt yet still match the new look in both modes.
  Color get cardBackground => rx.surface;
  Color get cardSecondaryBackground => rx.surfaceMuted;

  // --- BORDERS ---
  Color get borderColor => rx.hairline;
  Color get borderSubtle => rx.hairline;
  Color get borderColorStrong => rx.textPrimary.withValues(alpha: 0.14);

  // --- TYPOGRAPHY ---
  Color get textPrimary => rx.textPrimary;
  Color get textSecondary => rx.textSecondary;
  Color get textTertiary => rx.textTertiary;
  Color get textSubtle => rx.textPrimary.withValues(alpha: 0.14);

  // --- ICONS ---
  Color get iconPrimary => rx.textPrimary;
  Color get iconSecondary => rx.textSecondary;

  // --- SHADOWS ---
  List<BoxShadow> get cardShadow => rx.cardShadow;

  // --- Glass & subtle fills ---
  Color get glassBackground => rx.textPrimary.withValues(alpha: 0.05);
  Color get glassBackgroundStrong => rx.textPrimary.withValues(alpha: 0.09);

  // --- Inputs & Nav ---
  Color get inputBackground => rx.surface;
  Color get navBackground => rx.surface;
  Color get navActiveTab => rx.textPrimary;

  // --- Accents & Brand ---
  Color get primaryColor => rx.textPrimary;
  // Neutral ink accent: the old blue clashed with the ink + lime palette.
  Color get accentColor => rx.textPrimary;
}
