import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// RunwayX redesign palette, taken from the landing site mockups
/// (runwayx-landing/src/components/Mockups.tsx) and extended with a dark mode.
///
/// Registered on both ThemeData objects in [AppTheme], so every widget reads
/// the right values through `context.rx` and flips with the theme.
@immutable
class RxColors extends ThemeExtension<RxColors> {
  const RxColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.sheet,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.inverse,
    required this.onInverse,
    required this.accent,
    required this.positive,
    required this.positiveSoft,
    required this.negative,
    required this.negativeSoft,
    required this.warning,
    required this.warningSoft,
    required this.cardShadow,
    required this.raisedShadow,
    required this.barrier,
    required this.navGlass,
    required this.navBorder,
    required this.navIndicator,
    required this.navShadow,
  });

  /// Page background ("paper").
  final Color background;

  /// Cards, tab bar, grouped lists.
  final Color surface;

  /// Chips, segmented controls, pressed rows, icon tiles.
  final Color surfaceMuted;

  /// Bottom sheets and dialogs.
  final Color sheet;

  /// 1px dividers and structural borders.
  final Color hairline;

  final Color textPrimary;
  final Color textSecondary;

  /// Inactive tabs, captions, placeholders. Kept at >= 3:1 on [surface].
  final Color textTertiary;

  /// High-emphasis fill: primary buttons, the add button, selected chips.
  final Color inverse;
  final Color onInverse;

  /// Brand lime from the logo chevron. Use sparingly: live dots, chart lines.
  final Color accent;

  final Color positive;
  final Color positiveSoft;
  final Color negative;
  final Color negativeSoft;
  final Color warning;
  final Color warningSoft;

  /// Resting elevation for cards (very faint, light mode only).
  final List<BoxShadow> cardShadow;

  /// Elevation for floating controls such as the add button.
  final List<BoxShadow> raisedShadow;

  /// Modal scrim.
  final Color barrier;

  /// Floating tab bar: translucent fill laid over a backdrop blur.
  final Color navGlass;

  /// Floating tab bar: 1px edge so the pill reads on any content.
  final Color navBorder;

  /// Floating tab bar: capsule behind the active tab.
  final Color navIndicator;

  /// Floating tab bar and add button: lift off the content.
  final List<BoxShadow> navShadow;

  static const light = RxColors(
    background: Color(0xFFF4F4F2),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFEFEC),
    sheet: Color(0xFFF4F4F2),
    hairline: Color(0x0F000000), // black 6%
    textPrimary: Color(0xFF0D0E0F),
    textSecondary: Color(0xFF6B6C6E),
    textTertiary: Color(0xFF8A8B8D),
    inverse: Color(0xFF0D0E0F),
    onInverse: Color(0xFFFFFFFF),
    accent: Color(0xFF9BE15D),
    positive: Color(0xFF1C7A3D),
    positiveSoft: Color(0xFFE8F6EC),
    negative: Color(0xFFC2352F),
    negativeSoft: Color(0xFFFDECEC),
    warning: Color(0xFF8A5D00),
    warningSoft: Color(0xFFFFF6E0),
    cardShadow: [
      BoxShadow(color: Color(0x0D101828), blurRadius: 2, offset: Offset(0, 1)),
    ],
    raisedShadow: [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 14,
        spreadRadius: -4,
        offset: Offset(0, 6),
      ),
    ],
    barrier: Color(0x66000000),
    navGlass: Color(0xD9FFFFFF), // white 85%
    navBorder: Color(0x0F000000), // black 6%
    navIndicator: Color(0x0D0D0E0F), // ink 5%
    navShadow: [
      BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x1F0C1220),
        blurRadius: 32,
        spreadRadius: -8,
        offset: Offset(0, 12),
      ),
    ],
  );

  static const dark = RxColors(
    background: Color(0xFF0B0B0C),
    surface: Color(0xFF151517),
    surfaceMuted: Color(0xFF1F1F22),
    // Deeper than surface so cards, chips and selected rows read on sheets.
    sheet: Color(0xFF0F0F11),
    hairline: Color(0x14FFFFFF), // white 8%
    textPrimary: Color(0xFFF4F4F0),
    textSecondary: Color(0xFFA3A3A6),
    textTertiary: Color(0xFF7E7E82),
    inverse: Color(0xFFF4F4F0),
    onInverse: Color(0xFF0D0E0F),
    accent: Color(0xFF9BE15D),
    positive: Color(0xFF5FD38A),
    positiveSoft: Color(0xFF15281C),
    negative: Color(0xFFFF7A70),
    negativeSoft: Color(0xFF2E1616),
    warning: Color(0xFFFFC566),
    warningSoft: Color(0xFF2B2213),
    cardShadow: [],
    raisedShadow: [],
    barrier: Color(0x99000000),
    navGlass: Color(0xD91C1C1F), // #1C1C1F at 85%
    navBorder: Color(0x1AFFFFFF), // white 10%
    navIndicator: Color(0x1AFFFFFF), // white 10%
    navShadow: [
      BoxShadow(
        color: Color(0x80000000),
        blurRadius: 28,
        spreadRadius: -6,
        offset: Offset(0, 10),
      ),
    ],
  );

  @override
  RxColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? sheet,
    Color? hairline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? inverse,
    Color? onInverse,
    Color? accent,
    Color? positive,
    Color? positiveSoft,
    Color? negative,
    Color? negativeSoft,
    Color? warning,
    Color? warningSoft,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? raisedShadow,
    Color? barrier,
    Color? navGlass,
    Color? navBorder,
    Color? navIndicator,
    List<BoxShadow>? navShadow,
  }) {
    return RxColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      sheet: sheet ?? this.sheet,
      hairline: hairline ?? this.hairline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      inverse: inverse ?? this.inverse,
      onInverse: onInverse ?? this.onInverse,
      accent: accent ?? this.accent,
      positive: positive ?? this.positive,
      positiveSoft: positiveSoft ?? this.positiveSoft,
      negative: negative ?? this.negative,
      negativeSoft: negativeSoft ?? this.negativeSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      cardShadow: cardShadow ?? this.cardShadow,
      raisedShadow: raisedShadow ?? this.raisedShadow,
      barrier: barrier ?? this.barrier,
      navGlass: navGlass ?? this.navGlass,
      navBorder: navBorder ?? this.navBorder,
      navIndicator: navIndicator ?? this.navIndicator,
      navShadow: navShadow ?? this.navShadow,
    );
  }

  @override
  RxColors lerp(ThemeExtension<RxColors>? other, double t) {
    if (other is! RxColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return RxColors(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      sheet: c(sheet, other.sheet),
      hairline: c(hairline, other.hairline),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      inverse: c(inverse, other.inverse),
      onInverse: c(onInverse, other.onInverse),
      accent: c(accent, other.accent),
      positive: c(positive, other.positive),
      positiveSoft: c(positiveSoft, other.positiveSoft),
      negative: c(negative, other.negative),
      negativeSoft: c(negativeSoft, other.negativeSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? [],
      raisedShadow:
          BoxShadow.lerpList(raisedShadow, other.raisedShadow, t) ?? [],
      barrier: c(barrier, other.barrier),
      navGlass: c(navGlass, other.navGlass),
      navBorder: c(navBorder, other.navBorder),
      navIndicator: c(navIndicator, other.navIndicator),
      navShadow: BoxShadow.lerpList(navShadow, other.navShadow, t) ?? [],
    );
  }
}

extension RxColorsContext on BuildContext {
  /// Status bar and Android navigation bar style for every page.
  ///
  /// Use this instead of `SystemUiOverlayStyle.light/.dark`: those presets
  /// paint the Android navigation bar solid black, which shows as a black
  /// strip under the floating tab bar.
  SystemUiOverlayStyle get rxOverlayStyle {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    final icons = isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Redesign palette for the current theme.
  RxColors get rx =>
      Theme.of(this).extension<RxColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? RxColors.dark
          : RxColors.light);
}
