import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/theme/rx_colors.dart';

export 'package:startup_expense_tracker/theme/rx_colors.dart';

/// Shared building blocks for the redesign. Visual only: no data or logic.
///
/// Values follow the landing-site mockups (22px cards, tight tracking,
/// tabular numbers) and the better-ui rules (press scale 0.96 / 150ms
/// ease-out, gated on reduced motion; no animation on frequent actions).

// ---------------------------------------------------------------------------
// Typography
// ---------------------------------------------------------------------------

class RxText {
  RxText._();

  /// Geist: the landing site's typeface. Clear, neutral, great numerals.
  static const String family = 'Geist';
  static const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

  static TextStyle _t(
    double size,
    FontWeight weight,
    double tracking,
    Color color, {
    double height = 1.3,
    bool tabular = false,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height,
    fontWeight: weight,
    // Tracking as a fraction of size, like the site's em-based values.
    letterSpacing: size * tracking,
    color: color,
    fontFeatures: tabular ? _tnum : null,
  );

  /// Screen title, e.g. "Overview". 28 / semibold / -0.035em.
  static TextStyle title(BuildContext c) =>
      _t(28, FontWeight.w600, -0.035, c.rx.textPrimary, height: 1.15);

  /// Pushed-screen title in the top bar. 17 / semibold.
  static TextStyle navTitle(BuildContext c) =>
      _t(17, FontWeight.w600, -0.02, c.rx.textPrimary, height: 1.2);

  /// Hero number. Tabular so values don't jitter when they update.
  static TextStyle hero(BuildContext c, {double size = 56, Color? color}) => _t(
    size,
    FontWeight.w600,
    -0.05,
    color ?? c.rx.textPrimary,
    height: 1.0,
    tabular: true,
  );

  /// Stat value inside a card. 22 / semibold.
  static TextStyle value(BuildContext c, {double size = 22, Color? color}) =>
      _t(
        size,
        FontWeight.w600,
        -0.03,
        color ?? c.rx.textPrimary,
        height: 1.15,
        tabular: true,
      );

  /// Card heading. 15 / semibold.
  static TextStyle heading(BuildContext c) =>
      _t(15, FontWeight.w600, -0.01, c.rx.textPrimary, height: 1.25);

  /// Row title. 15 / medium.
  static TextStyle body(BuildContext c, {Color? color}) =>
      _t(15, FontWeight.w500, -0.01, color ?? c.rx.textPrimary);

  /// Amount at the end of a row. 15 / semibold, tabular.
  static TextStyle amount(BuildContext c, {Color? color}) =>
      _t(15, FontWeight.w600, -0.01, color ?? c.rx.textPrimary, tabular: true);

  /// Label above a value, e.g. "Burn / mo". 13 / medium / secondary.
  static TextStyle label(BuildContext c, {Color? color}) =>
      _t(13, FontWeight.w500, 0, color ?? c.rx.textSecondary);

  /// Supporting line under a row title. 12.5 / regular / secondary.
  static TextStyle caption(BuildContext c, {Color? color}) =>
      _t(12.5, FontWeight.w400, 0, color ?? c.rx.textSecondary);

  /// Axis labels and fine print. 11 / medium / tertiary, tabular.
  static TextStyle micro(BuildContext c, {Color? color}) => _t(
    11,
    FontWeight.w500,
    0,
    color ?? c.rx.textTertiary,
    height: 1.2,
    tabular: true,
  );
}

// ---------------------------------------------------------------------------
// Press feedback
// ---------------------------------------------------------------------------

/// Scales its child to 0.96 while pressed (150ms ease-out), with a light
/// haptic on tap. Motion is skipped when the OS asks for reduced motion.
class RxPressable extends StatefulWidget {
  const RxPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.haptic = true,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool haptic;
  final double scale;

  @override
  State<RxPressable> createState() => _RxPressableState();
}

class _RxPressableState extends State<RxPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          // A disabled control never scales.
          scale: _pressed && enabled && !reduceMotion ? widget.scale : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// The base card: 22px radius, white / #151517. Light mode lifts with a
/// faint shadow; dark mode uses a hairline instead (shadows vanish on black).
class RxCard extends StatelessWidget {
  const RxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.radius = 22,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? rx.surface,
        borderRadius: BorderRadius.circular(radius),
        // Keeps an edge in dark mode, transparent in light (shadow does it).
        border: Border.all(color: isDark ? rx.hairline : Colors.transparent),
        boxShadow: rx.cardShadow,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return RxPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      scale: 0.98, // Large surfaces press more subtly than buttons.
      child: card,
    );
  }
}

/// Rounded square holding an icon, used at the start of list rows.
class RxIconTile extends StatelessWidget {
  const RxIconTile({
    super.key,
    required this.icon,
    this.background,
    this.foreground,
    this.size = 40,
    this.iconSize = 20,
  });

  final List<List<dynamic>> icon;
  final Color? background;
  final Color? foreground;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? rx.surfaceMuted,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: HugeIcon(
        icon: icon,
        color: foreground ?? rx.textPrimary,
        size: iconSize,
        strokeWidth: 1.8,
      ),
    );
  }
}

/// The AI CFO mark: lime sparkles on a round tile.
///
/// Light mode sits on solid ink. Dark mode uses a deep lime-tinted tile with
/// a soft lime edge instead of a near-white disc, which glared against the
/// lime glyph on black.
class RxAiBadge extends StatelessWidget {
  const RxAiBadge({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? null : rx.inverse,
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF26361A), Color(0xFF141B0F)],
              )
            : null,
        border: Border.all(
          color: isDark
              ? rx.accent.withValues(alpha: 0.28)
              : Colors.transparent,
        ),
      ),
      alignment: Alignment.center,
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedSparkles,
        color: rx.accent,
        size: size * 0.5,
        strokeWidth: 1.8,
      ),
    );
  }
}

/// Small rounded status pill: optional dot + label.
class RxPill extends StatelessWidget {
  const RxPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.dot = false,
  });

  final String label;
  final Color foreground;
  final Color background;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: RxText.family,
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Title row for a group of content, with an optional trailing action.
class RxSectionHeader extends StatelessWidget {
  const RxSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 10),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: RxText.label(
                context,
              ).copyWith(fontWeight: FontWeight.w600, color: rx.textSecondary),
            ),
          ),
          if (actionLabel != null)
            RxPressable(
              onTap: onAction,
              semanticLabel: actionLabel,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: RxText.label(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: rx.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      color: rx.textPrimary,
                      size: 16,
                      strokeWidth: 2,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Round 40px icon button used in top bars (back, actions).
class RxCircleButton extends StatelessWidget {
  const RxCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.filled = false,
  });

  final List<List<dynamic>> icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RxPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      // 48px hit area around a 40px circle.
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: filled ? rx.inverse : rx.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: filled || !isDark ? Colors.transparent : rx.hairline,
              ),
              boxShadow: filled ? null : rx.cardShadow,
            ),
            alignment: Alignment.center,
            child: HugeIcon(
              icon: icon,
              color: filled ? rx.onInverse : rx.textPrimary,
              size: 20,
              strokeWidth: 1.9,
            ),
          ),
        ),
      ),
    );
  }
}

/// Header for the main tabs (Home, Expenses, Team, AI CFO, Settings):
/// small label, big title, actions on the right. Same height, inset and
/// top spacing on every tab so switching tabs never shifts the layout.
class RxTabHeader extends StatelessWidget {
  const RxTabHeader({
    super.key,
    required this.label,
    required this.title,
    this.actions = const [],
  });

  final String label;
  final String title;
  final List<Widget> actions;

  /// Space between the status bar and the header.
  static const double topGap = 20;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: topGap),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RxText.label(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RxText.title(context),
                  ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Top bar for pushed screens: back button, centred title, optional action.
class RxTopBar extends StatelessWidget {
  const RxTopBar({super.key, required this.title, this.trailing, this.onBack});

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            RxCircleButton(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              semanticLabel: 'Back',
              onTap: onBack ?? () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RxText.navTitle(context),
              ),
            ),
            SizedBox(width: 48, child: trailing),
          ],
        ),
      ),
    );
  }
}

/// Flat placeholder block shown while data loads (no shimmer: calmer).
class RxSkeleton extends StatelessWidget {
  const RxSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.rx.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Centred empty state: an animated illustration built around [icon],
/// a title, one line of help and an optional action button.
///
/// The art is drawn in code (no image assets), so it follows the theme in
/// light and dark mode. Error icons switch it to a red tone automatically.
class RxEmptyState extends StatelessWidget {
  const RxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.scene = RxArtScene.papers,
    this.padding = const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
  });

  /// Illustration variant; papers suits form/document screens.
  final RxArtScene scene;

  final List<List<dynamic>> icon;
  final String title;
  final String? message;

  /// Optional primary button under the text.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Smaller art for tight spots such as sheets.
  final bool compact;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final isError =
        identical(icon, HugeIcons.strokeRoundedAlert02) ||
        title.toLowerCase().startsWith("couldn't");
    // Full width so it always sits centred, even inside start-aligned
    // columns (e.g. the Report screen).
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RxEmptyArt(
              icon: icon,
              tone: isError ? RxEmptyTone.error : RxEmptyTone.brand,
              scale: compact ? 0.72 : 1,
              scene: scene,
            ),
            SizedBox(height: compact ? 10 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: RxText.body(context).copyWith(fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: RxText.caption(context).copyWith(height: 1.4),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              RxPressable(
                onTap: onAction,
                semanticLabel: actionLabel,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: rx.inverse,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedAdd01,
                        color: rx.onInverse,
                        size: 18,
                        strokeWidth: 2,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        actionLabel!,
                        style: RxText.body(
                          context,
                          color: rx.onInverse,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum RxEmptyTone { brand, error }

/// What the illustration shows. [papers] is the default and suits anything
/// form or document related (lists, records, reports). The others are for
/// screens with a specific purpose.
enum RxArtScene { papers, shield, lock, mail, rocket, star }

/// Illustration for empty states: a soft halo, two tilted "paper" cards
/// and a badge carrying [icon], with twinkling sparkles.
///
/// Motion: pops in once, then the cards float gently (3.6s loop). Under the
/// OS reduced-motion setting it is drawn static.
class RxEmptyArt extends StatefulWidget {
  const RxEmptyArt({
    super.key,
    required this.icon,
    this.tone = RxEmptyTone.brand,
    this.scale = 1,
    this.scene = RxArtScene.papers,
  });

  final List<List<dynamic>> icon;
  final RxEmptyTone tone;
  final double scale;
  final RxArtScene scene;

  @override
  State<RxEmptyArt> createState() => _RxEmptyArtState();
}

class _RxEmptyArtState extends State<RxEmptyArt> with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _float.stop();
      _enter.value = 1;
    } else {
      if (!_float.isAnimating) _float.repeat();
      if (_enter.value == 0 && !_enter.isAnimating) _enter.forward();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.scale;
    final isError = widget.tone == RxEmptyTone.error;

    final badgeBg = isError
        ? rx.negativeSoft
        : (isDark ? rx.accent : rx.inverse);
    final badgeFg = isError
        ? rx.negative
        : (isDark ? const Color(0xFF0D0E0F) : rx.onInverse);
    final halo = isError
        ? rx.negative.withValues(alpha: isDark ? 0.10 : 0.06)
        : (isDark
              ? rx.accent.withValues(alpha: 0.07)
              : rx.textPrimary.withValues(alpha: 0.04));
    final sparkle = isError
        ? rx.negative
        : (isDark ? rx.accent : rx.textTertiary);

    Widget paper({required double w, required double h, bool front = false}) {
      Widget line(double width, {double o = 1}) => Container(
        width: width,
        height: 5,
        decoration: BoxDecoration(
          color: rx.textPrimary.withValues(alpha: 0.08 * o),
          borderRadius: BorderRadius.circular(10),
        ),
      );
      return Container(
        width: w,
        height: h,
        padding: EdgeInsets.all(9 * s),
        decoration: BoxDecoration(
          color: front ? rx.surface : rx.surfaceMuted,
          borderRadius: BorderRadius.circular(12 * s),
          border: Border.all(color: rx.hairline),
          boxShadow: front && !isDark
              ? const [
                  BoxShadow(
                    color: Color(0x14101828),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 16 * s,
              height: 16 * s,
              decoration: BoxDecoration(
                color: rx.textPrimary.withValues(alpha: front ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(5 * s),
              ),
            ),
            SizedBox(height: 8 * s),
            line(w * 0.62),
            SizedBox(height: 5 * s),
            line(w * 0.42, o: 0.7),
            const Spacer(),
            line(w * 0.3, o: 0.6),
          ],
        ),
      );
    }

    Widget spark(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: sparkle, shape: BoxShape.circle),
    );

    final width = 156.0 * s;
    final height = 120.0 * s;

    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedBuilder(
          animation: Listenable.merge([_float, _enter]),
          builder: (context, _) {
            final t = _float.value * 2 * math.pi;
            final e = Curves.easeOutBack.transform(_enter.value.clamp(0, 1));
            final eo = Curves.easeOut.transform(_enter.value.clamp(0, 1));
            double tw(double phase) =>
                0.35 + 0.65 * (0.5 + 0.5 * math.sin(t + phase));

            return Opacity(
              opacity: eo,
              child: Transform.scale(
                scale: 0.85 + 0.15 * e,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Halo
                    Container(
                      width: 112 * s,
                      height: 112 * s,
                      decoration: BoxDecoration(
                        color: halo,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (widget.scene == RxArtScene.papers) ...[
                      // Back paper
                      Transform.translate(
                        offset: Offset(
                          -17 * s,
                          2 * s + 2 * s * math.sin(t + 1.2),
                        ),
                        child: Transform.rotate(
                          angle: -0.16,
                          child: paper(w: 60 * s, h: 74 * s),
                        ),
                      ),
                      // Front paper
                      Transform.translate(
                        offset: Offset(11 * s, -2 * s + 4 * s * math.sin(t)),
                        child: Transform.rotate(
                          angle: 0.09,
                          child: paper(w: 64 * s, h: 80 * s, front: true),
                        ),
                      ),
                      // Badge with the screen's icon
                      Positioned(
                        right: 28 * s,
                        bottom: 8 * s + 3 * s * math.sin(t + 0.6),
                        child: Container(
                          width: 38 * s,
                          height: 38 * s,
                          decoration: BoxDecoration(
                            color: badgeBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: rx.surface, width: 3),
                          ),
                          alignment: Alignment.center,
                          child: HugeIcon(
                            icon: widget.icon,
                            color: badgeFg,
                            size: 18 * s,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ] else
                      _scene(t, s, badgeBg, badgeFg, isDark),
                    // Sparkles
                    Positioned(
                      left: 18 * s,
                      top: 14 * s,
                      child: Opacity(opacity: tw(0), child: spark(6 * s)),
                    ),
                    Positioned(
                      right: 18 * s,
                      top: 6 * s,
                      child: Opacity(opacity: tw(2.1), child: spark(8 * s)),
                    ),
                    Positioned(
                      left: 30 * s,
                      bottom: 6 * s,
                      child: Opacity(opacity: tw(4.2), child: spark(4 * s)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

extension on _RxEmptyArtState {
  /// Purpose-specific centrepiece. [t] is the float phase in radians.
  Widget _scene(double t, double s, Color accent, Color onAccent, bool dark) {
    final rx = context.rx;
    final surfaceDeco = BoxDecoration(
      color: rx.surface,
      border: Border.all(color: rx.hairline),
      boxShadow: dark
          ? null
          : const [
              BoxShadow(
                color: Color(0x14101828),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
    );
    final bob = 4 * s * math.sin(t);

    Widget badge(List<List<dynamic>> icon, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
        border: Border.all(color: rx.surface, width: 3),
      ),
      alignment: Alignment.center,
      child: HugeIcon(
        icon: icon,
        color: onAccent,
        size: size * 0.46,
        strokeWidth: 2,
      ),
    );

    switch (widget.scene) {
      // Shield with a check, and a ring that pulses out from it.
      case RxArtScene.shield:
        final pulse = (_float.value * 2) % 1;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: (1 - pulse) * 0.5,
              child: Container(
                width: (78 + 40 * pulse) * s,
                height: (78 + 40 * pulse) * s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.5),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, bob),
              child: CustomPaint(
                size: Size(70 * s, 82 * s),
                painter: _ShieldPainter(
                  fill: rx.surface,
                  stroke: rx.textPrimary.withValues(alpha: 0.12),
                  shadow: !dark,
                ),
                child: SizedBox(
                  width: 70 * s,
                  height: 82 * s,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 6 * s),
                      child: badge(HugeIcons.strokeRoundedTick02, 34 * s),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

      // Padlock whose shackle lifts a little, like it's being opened.
      case RxArtScene.lock:
        final lift = 3 * s * (0.5 + 0.5 * math.sin(t * 2));
        return Transform.translate(
          offset: Offset(0, bob * 0.5),
          child: SizedBox(
            width: 80 * s,
            height: 92 * s,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(
                  top: 4 * s - lift,
                  child: Container(
                    width: 44 * s,
                    height: 44 * s,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(22 * s),
                      ),
                      border: Border.all(
                        color: rx.textPrimary.withValues(alpha: 0.25),
                        width: 7 * s,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 72 * s,
                  height: 56 * s,
                  decoration: surfaceDeco.copyWith(
                    borderRadius: BorderRadius.circular(16 * s),
                  ),
                  alignment: Alignment.center,
                  child: badge(HugeIcons.strokeRoundedKey01, 30 * s),
                ),
              ],
            ),
          ),
        );

      // Envelope with a letter sliding up out of it.
      case RxArtScene.mail:
        final rise = 10 * s * (0.5 + 0.5 * math.sin(t));
        return Transform.translate(
          offset: Offset(0, 8 * s),
          child: SizedBox(
            width: 96 * s,
            height: 92 * s,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: 20 * s + rise,
                  child: Container(
                    width: 64 * s,
                    height: 56 * s,
                    padding: EdgeInsets.all(9 * s),
                    decoration: surfaceDeco.copyWith(
                      borderRadius: BorderRadius.circular(9 * s),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in const [0.7, 0.5, 0.6])
                          Padding(
                            padding: EdgeInsets.only(bottom: 5 * s),
                            child: Container(
                              width: 46 * s * w,
                              height: 4 * s,
                              decoration: BoxDecoration(
                                color: rx.textPrimary.withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                CustomPaint(
                  size: Size(96 * s, 58 * s),
                  painter: _EnvelopePainter(
                    fill: rx.surfaceMuted,
                    stroke: rx.textPrimary.withValues(alpha: 0.12),
                  ),
                ),
                Positioned(
                  right: -2 * s,
                  bottom: 34 * s,
                  child: badge(HugeIcons.strokeRoundedSent, 32 * s),
                ),
              ],
            ),
          ),
        );

      // Rocket lifting off with a fading exhaust trail.
      case RxArtScene.rocket:
        final climb = 6 * s * math.sin(t);
        return SizedBox(
          width: 110 * s,
          height: 110 * s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Builder(
                  builder: (context) {
                    final p = ((_float.value * 3) + i / 3) % 1;
                    return Transform.translate(
                      offset: Offset(
                        (-14 - 22 * p) * s,
                        (14 + 22 * p) * s + climb,
                      ),
                      child: Opacity(
                        opacity: (1 - p) * 0.7,
                        child: Container(
                          width: (9 - 4 * p) * s,
                          height: (9 - 4 * p) * s,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              Transform.translate(
                offset: Offset(4 * s, -4 * s + climb),
                child: Container(
                  width: 64 * s,
                  height: 64 * s,
                  decoration: surfaceDeco.copyWith(
                    borderRadius: BorderRadius.circular(20 * s),
                  ),
                  alignment: Alignment.center,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedRocket01,
                    color: rx.textPrimary,
                    size: 30 * s,
                    strokeWidth: 1.8,
                  ),
                ),
              ),
            ],
          ),
        );

      // Three stars; the middle one breathes, the others twinkle.
      case RxArtScene.star:
        final breathe = 1 + 0.06 * math.sin(t * 2);
        Widget star(double size, double phase) => Opacity(
          opacity: 0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * 2 + phase)),
          child: Icon(Icons.star_rounded, size: size, color: accent),
        );
        return SizedBox(
          width: 130 * s,
          height: 100 * s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(-40 * s, 14 * s),
                child: star(28 * s, 1.5),
              ),
              Transform.translate(
                offset: Offset(40 * s, 14 * s),
                child: star(28 * s, 3.1),
              ),
              Transform.translate(
                offset: Offset(0, -2 * s + bob * 0.6),
                child: Transform.scale(
                  scale: breathe,
                  child: Container(
                    width: 66 * s,
                    height: 66 * s,
                    decoration: surfaceDeco.copyWith(shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.star_rounded,
                      size: 38 * s,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

      case RxArtScene.papers:
        return const SizedBox.shrink();
    }
  }
}

class _ShieldPainter extends CustomPainter {
  _ShieldPainter({
    required this.fill,
    required this.stroke,
    required this.shadow,
  });

  final Color fill;
  final Color stroke;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * 0.72, h * 0.08, w * 0.9, h * 0.1, w, h * 0.12)
      ..lineTo(w, h * 0.46)
      ..cubicTo(w, h * 0.74, w * 0.74, h * 0.9, w / 2, h)
      ..cubicTo(w * 0.26, h * 0.9, 0, h * 0.74, 0, h * 0.46)
      ..lineTo(0, h * 0.12)
      ..cubicTo(w * 0.1, h * 0.1, w * 0.28, h * 0.08, w / 2, 0)
      ..close();
    if (shadow) canvas.drawShadow(path, const Color(0x33101828), 8, false);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) =>
      old.fill != fill || old.stroke != stroke || old.shadow != shadow;
}

class _EnvelopePainter extends CustomPainter {
  _EnvelopePainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(r, Paint()..color = fill);
    final line = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(r, line);
    // Front flap folds.
    canvas.drawPath(
      Path()
        ..moveTo(4, 6)
        ..lineTo(size.width / 2, size.height * 0.58)
        ..lineTo(size.width - 4, 6),
      line,
    );
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) =>
      old.fill != fill || old.stroke != stroke;
}

/// Thin hairline divider inset to line up with row text.
class RxDivider extends StatelessWidget {
  const RxDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Container(height: 1, color: context.rx.hairline),
    );
  }
}

// ---------------------------------------------------------------------------
// Category colours
// ---------------------------------------------------------------------------

/// Calm, mode-aware colours for expense categories (charts, dots, tiles).
/// Same category always gets the same hue on every screen.
class RxCategory {
  RxCategory._();

  static const _light = <Color>[
    Color(0xFF0D0E0F), // ink
    Color(0xFF6B4DE6), // violet
    Color(0xFF2F6FE0), // blue
    Color(0xFF1C7A3D), // green
    Color(0xFFD9670F), // orange
    Color(0xFFD23C75), // pink
    Color(0xFF8A5A2B), // brown
    Color(0xFF0E8A8A), // teal
  ];

  static const _dark = <Color>[
    Color(0xFFF4F4F0),
    Color(0xFFA08BFF),
    Color(0xFF6EA2FF),
    Color(0xFF5FD38A),
    Color(0xFFFFA25C),
    Color(0xFFFF7EB0),
    Color(0xFFD9A774),
    Color(0xFF4FD1C5),
  ];

  static int _slot(String category) {
    switch (category.toLowerCase().trim()) {
      case 'salaries':
      case 'salary':
      case 'payroll':
        return 0;
      case 'software':
      case 'tools':
        return 1;
      case 'servers':
      case 'infrastructure':
      case 'servers & infrastructure':
        return 2;
      case 'office':
      case 'operations':
      case 'office & operations':
        return 3;
      case 'marketing':
      case 'ads':
        return 5;
      case 'meals':
      case 'food':
        return 4;
      case 'travel':
      case 'transport':
        return 7;
      case 'legal':
        return 6;
      default:
        final h = category.toLowerCase().codeUnits.fold<int>(
          0,
          (a, b) => (a * 31 + b) & 0x7fffffff,
        );
        return h % _light.length;
    }
  }

  static Color color(BuildContext context, String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final i = _slot(category);
    return isDark ? _dark[i] : _light[i];
  }

  /// Tinted background for an icon tile of this category.
  static Color soft(BuildContext context, String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return color(context, category).withValues(alpha: isDark ? 0.16 : 0.09);
  }

  static List<List<dynamic>> icon(String category) {
    switch (category.toLowerCase().trim()) {
      case 'salaries':
      case 'salary':
      case 'payroll':
        return HugeIcons.strokeRoundedUserGroup;
      case 'software':
      case 'tools':
        return HugeIcons.strokeRoundedLaptop;
      case 'servers':
      case 'infrastructure':
      case 'servers & infrastructure':
        return HugeIcons.strokeRoundedServerStack01;
      case 'office':
      case 'operations':
      case 'office & operations':
        return HugeIcons.strokeRoundedBuilding03;
      case 'marketing':
      case 'ads':
        return HugeIcons.strokeRoundedMegaphone01;
      case 'meals':
      case 'food':
        return HugeIcons.strokeRoundedCoffee01;
      case 'travel':
      case 'transport':
        return HugeIcons.strokeRoundedAirplane01;
      case 'legal':
        return HugeIcons.strokeRoundedJusticeScale01;
      default:
        return HugeIcons.strokeRoundedInvoice01;
    }
  }
}
