import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../widgets/rx_form.dart';
import '../../../widgets/rx_logo.dart';
import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';
import '../../ai/widgets/ai_widgets.dart';

/// Visual kit for the auth flow (login, sign up, reset, verify).
///
/// First-impression screens, so they get more motion than the rest of the
/// app: a drifting aurora + dot-grid backdrop like the landing site, the AI
/// CFO robot with floating metric chips, a typed speech line, and every
/// block revealed one by one. Everything is drawn in code, follows light /
/// dark mode, and goes still under the OS reduced-motion setting.

bool _reduce(BuildContext c) => MediaQuery.disableAnimationsOf(c);

// ---------------------------------------------------------------------------
// Staggered entrance
// ---------------------------------------------------------------------------

/// Reveals auth blocks one after another: step [i] waits 120ms + i x 90ms,
/// then fades and rises 16px over 450ms.
class AuthStep extends StatelessWidget {
  const AuthStep(this.i, {super.key, required this.child});

  final int i;
  final Widget child;

  @override
  Widget build(BuildContext context) => RxReveal(
    delay: Duration(milliseconds: 120 + i * 90),
    duration: const Duration(milliseconds: 450),
    offset: 16,
    child: child,
  );
}

// ---------------------------------------------------------------------------
// Page layout (no scroll)
// ---------------------------------------------------------------------------

/// Shared auth page: plain background, brand bar on top, the robot hero
/// filling whatever height is left, then the form and footer.
///
/// The page never scrolls with the keyboard closed: the hero shrinks (and
/// drops its chips, then hides) so everything fits on one screen. With the
/// keyboard open the hero becomes a one-line robot and the page can scroll
/// so the focused field stays visible.
///
/// The widget tree is the same in both states (only the hero slot's content
/// and the scroll physics change). Swapping the tree when the keyboard
/// opened rebuilt the text fields, which dropped focus, closed the keyboard
/// and looped, so fields could not be typed into.
class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.hero,
    required this.compactText,
    required this.body,
    this.footer,
    this.leading,
  });

  /// Builds the hero for the height it gets.
  final Widget Function(double height) hero;

  /// Line next to the small robot while typing.
  final String compactText;

  /// Title, form card, social row...
  final List<Widget> body;
  final Widget? footer;

  /// E.g. a back button in the brand bar.
  final Widget? leading;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  /// Page height with the keyboard closed. Kept while typing so the layout
  /// doesn't squash; the scroll view then lets the field scroll into view.
  double? _fullHeight;

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.rxOverlayStyle,
      child: Scaffold(
        backgroundColor: context.rx.background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: LayoutBuilder(
              builder: (context, box) {
                if (!typing) _fullHeight = box.maxHeight;
                final height = typing
                    ? (_fullHeight ?? box.maxHeight)
                    : box.maxHeight;

                return SingleChildScrollView(
                  physics: typing
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  // Keyboard closed: exactly the screen height (no scroll).
                  // Typing: at least that tall, but free to grow (e.g. the
                  // password checklist) and scroll. IntrinsicHeight only
                  // measures when the height isn't tight, i.e. while typing,
                  // when the hero slot holds no LayoutBuilder.
                  child: ConstrainedBox(
                    constraints: typing
                        ? BoxConstraints(minHeight: height)
                        : BoxConstraints.tightFor(height: height),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthStep(
                              0,
                              child: AuthBrandBar(leading: widget.leading),
                            ),
                            // Hero + form as one group, centred in the free
                            // space. The hero takes what the form leaves (up
                            // to its design height).
                            Expanded(
                              child: Column(
                                mainAxisAlignment: typing
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Flexible(
                                    child: typing
                                        ? Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            child: AuthHeroCompact(
                                              text: widget.compactText,
                                            ),
                                          )
                                        : LayoutBuilder(
                                            builder: (context, c) =>
                                                c.maxHeight < 96
                                                ? const SizedBox.shrink()
                                                : AuthStep(
                                                    1,
                                                    child: widget.hero(
                                                      c.maxHeight,
                                                    ),
                                                  ),
                                          ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...widget.body,
                                ],
                              ),
                            ),
                            if (widget.footer != null)
                              AuthStep(9, child: widget.footer!),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// Brand
// ---------------------------------------------------------------------------

/// RunwayX logo + wordmark (from the website).
class AuthBrandBar extends StatelessWidget {
  const AuthBrandBar({super.key, this.leading});

  /// Optional widget before the mark, e.g. a back button.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 2)],
          const RxWordmark(size: 30),
        ],
      ),
    );
  }
}

/// Round back button for the brand bar.
class AuthBackButton extends StatelessWidget {
  const AuthBackButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => RxCircleButton(
    icon: HugeIcons.strokeRoundedArrowLeft01,
    semanticLabel: 'Back',
    onTap: onTap,
  );
}

// ---------------------------------------------------------------------------
// Hero: robot + floating metric chips + typed speech line
// ---------------------------------------------------------------------------

class AuthChipData {
  const AuthChipData(this.icon, this.label, this.value, {this.up});
  final List<List<dynamic>> icon;
  final String label;
  final String value;

  /// Green (true) / red (false) tint for the value; null = neutral.
  final bool? up;
}

/// The AI CFO promo: robot floating in the middle with turning rings,
/// metric chips around it, and a speech bubble that types a rotating line.
/// Sizes itself to [height]: the robot scales, chips drop out when tight.
class AuthHero extends StatefulWidget {
  const AuthHero({
    super.key,
    required this.lines,
    required this.height,
    this.chips = defaultChips,
  });

  final List<String> lines;
  final double height;

  /// Up to three; placed top-left, middle-right, bottom-left.
  final List<AuthChipData> chips;

  static const defaultChips = [
    AuthChipData(HugeIcons.strokeRoundedRocket01, 'Runway', '18 mo', up: true),
    AuthChipData(HugeIcons.strokeRoundedFire, 'Burn rate', '-12%', up: true),
    AuthChipData(HugeIcons.strokeRoundedUserGroup, 'Payroll', 'On track'),
  ];

  @override
  State<AuthHero> createState() => _AuthHeroState();
}

class _AuthHeroState extends State<AuthHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduce(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Never taller than the design size; centred in any extra space.
    final h = widget.height.clamp(0.0, 270.0);
    final showSpeech = h >= 150;
    final showChips = h >= 190;
    final stage = h - (showSpeech ? 48 : 0);
    // The rings are ~1.83x the robot size tall; keep them inside the stage
    // so they never spill onto the title on short phones.
    final bot = (stage / 1.9).clamp(44.0, 104.0);
    const slots = [
      Alignment(-1, -0.8),
      Alignment(1, -0.1),
      Alignment(-0.9, 0.62),
    ];

    // Takes exactly its own height; AuthPage centres hero + form together.
    return Center(
      heightFactor: 1,
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _OrbitRings(scale: bot / 104),
                  AiBot(size: bot, bubble: false),
                  if (showChips)
                    for (var i = 0; i < widget.chips.length && i < 3; i++)
                      Align(
                        alignment: slots[i],
                        child: RxReveal(
                          delay: Duration(milliseconds: 650 + i * 160),
                          duration: const Duration(milliseconds: 500),
                          child: AnimatedBuilder(
                            animation: _c,
                            builder: (_, child) {
                              final t = _c.value * 2 * math.pi + i * 2.1;
                              return Transform.translate(
                                offset: Offset(
                                  2.5 * math.cos(t),
                                  5 * math.sin(t),
                                ),
                                child: child,
                              );
                            },
                            child: _MetricChip(data: widget.chips[i]),
                          ),
                        ),
                      ),
                ],
              ),
            ),
            if (showSpeech) ...[
              const SizedBox(height: 8),
              AuthSpeech(lines: widget.lines),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two thin dashed rings slowly turning behind the robot, with a lime
/// satellite riding the outer one.
class _OrbitRings extends StatefulWidget {
  const _OrbitRings({this.scale = 1});
  final double scale;

  @override
  State<_OrbitRings> createState() => _OrbitRingsState();
}

class _OrbitRingsState extends State<_OrbitRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduce(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size(250 * widget.scale, 190 * widget.scale),
        painter: _RingsPainter(
          t: _c,
          color: context.rx.textPrimary,
          accent: context.rx.accent,
          scale: widget.scale,
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.t,
    required this.color,
    required this.accent,
    this.scale = 1,
  }) : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final Color accent;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final a = t.value * 2 * math.pi;
    final s = scale;
    void ring(double rx, double ry, double rot, double alpha, int dashes) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: alpha);
      final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
      final step = 2 * math.pi / dashes;
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(rect, rot + i * step, step * 0.55, false, paint);
      }
    }

    ring(118 * s, 82 * s, a, 0.16, 36);
    ring(96 * s, 66 * s, -a * 1.4, 0.10, 28);

    // A lime "satellite" riding the outer ring.
    final sat = Offset(
      c.dx + 118 * s * math.cos(a * 3),
      c.dy + 82 * s * math.sin(a * 3),
    );
    canvas.drawCircle(
      sat,
      6,
      Paint()
        ..color = accent.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(sat, 2.6, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.color != color || old.accent != accent;
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.data});
  final AuthChipData data;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final valueColor = switch (data.up) {
      true => rx.positive,
      false => rx.negative,
      null => rx.textPrimary,
    };
    // No blur here: the chips move every frame and a moving BackdropFilter
    // is expensive on mid-range Android. A near-opaque fill reads the same.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x14101828),
                  blurRadius: 14,
                  spreadRadius: -4,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 7, 11, 7),
          decoration: BoxDecoration(
            color: rx.surface.withValues(alpha: dark ? 0.9 : 0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: rx.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: rx.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: HugeIcon(
                  icon: data.icon,
                  color: rx.textPrimary,
                  size: 14,
                  strokeWidth: 1.9,
                ),
              ),
              const SizedBox(width: 7),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.label, style: RxText.micro(context)),
                  const SizedBox(height: 1),
                  Text(
                    data.value,
                    style: RxText.amount(
                      context,
                      color: valueColor,
                    ).copyWith(fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Speech bubble from the robot. Types each line letter by letter, holds
/// it, then fades to the next. Reduced motion shows the first line still.
class AuthSpeech extends StatefulWidget {
  const AuthSpeech({super.key, required this.lines});

  final List<String> lines;

  @override
  State<AuthSpeech> createState() => _AuthSpeechState();
}

class _AuthSpeechState extends State<AuthSpeech> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Start after the hero has revealed.
    _timer = Timer(const Duration(milliseconds: 500), _schedule);
  }

  void _schedule() {
    if (!mounted || widget.lines.length < 2 || _reduce(context)) return;
    final ms = 900 + widget.lines[_i].length * 38 + 2400;
    _timer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % widget.lines.length);
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final reduce = _reduce(context);
    final line = widget.lines.isEmpty ? '' : widget.lines[_i];
    final style = RxText.body(
      context,
      color: rx.textSecondary,
    ).copyWith(fontSize: 14, fontWeight: FontWeight.w500);

    return Semantics(
      liveRegion: true,
      label: line,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
          decoration: BoxDecoration(
            color: rx.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: rx.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedSparkles,
                color: rx.textPrimary,
                size: 15,
                strokeWidth: 1.9,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: reduce
                      ? Text(line, key: ValueKey(_i), style: style)
                      : TweenAnimationBuilder<int>(
                          key: ValueKey(_i),
                          tween: IntTween(begin: 0, end: line.length),
                          duration: Duration(milliseconds: line.length * 38),
                          builder: (_, n, _) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  line.substring(0, n),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: style,
                                ),
                              ),
                              // Caret while typing.
                              AnimatedOpacity(
                                opacity: n < line.length ? 1 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Container(
                                  width: 2,
                                  height: 15,
                                  margin: const EdgeInsets.only(left: 2),
                                  color: rx.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact hero used while the keyboard is open: small robot + one line.
class AuthHeroCompact extends StatelessWidget {
  const AuthHeroCompact({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AiBotAvatar(size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RxText.label(context),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Form surfaces and controls
// ---------------------------------------------------------------------------

/// Card that holds the form: surface colour, soft lift in light mode,
/// hairline in dark mode.
class AuthGlassCard extends StatelessWidget {
  const AuthGlassCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: rx.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dark ? rx.hairline : Colors.transparent),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0F101828),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// Primary action with a light sheen sweeping across every few seconds.
class AuthPrimaryButton extends StatefulWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.icon = HugeIcons.strokeRoundedArrowRight02,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final List<List<dynamic>>? icon;

  @override
  State<AuthPrimaryButton> createState() => _AuthPrimaryButtonState();
}

class _AuthPrimaryButtonState extends State<AuthPrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduce(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final reduce = _reduce(context);
    return Stack(
      children: [
        RxButton(
          label: widget.label,
          onTap: widget.onTap,
          loading: widget.loading,
          height: 54,
        ),
        if (!reduce && !widget.loading && widget.onTap != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) {
                    // Sweep in the first 30% of the loop, rest otherwise.
                    final p = (_c.value / 0.3).clamp(0.0, 1.0);
                    if (p >= 1) return const SizedBox.shrink();
                    return FractionalTranslation(
                      translation: Offset(-1 + 2.2 * p, 0),
                      child: Transform(
                        transform: Matrix4.skewX(-0.4),
                        child: Container(
                          width: 70,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                rx.onInverse.withValues(alpha: 0),
                                rx.onInverse.withValues(alpha: 0.22),
                                rx.onInverse.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        // Trailing arrow, inside the button, to the right.
        if (widget.icon != null && !widget.loading)
          Positioned(
            right: 8,
            top: 8,
            bottom: 8,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: widget.onTap == null ? 0.45 : 1,
                child: Container(
                  width: 38,
                  decoration: BoxDecoration(
                    color: rx.accent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: HugeIcon(
                    icon: widget.icon!,
                    color: const Color(0xFF0D0E0F),
                    size: 18,
                    strokeWidth: 2.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Outlined social sign-in button: brand mark + label.
class AuthSocialButton extends StatelessWidget {
  const AuthSocialButton({
    super.key,
    required this.label,
    required this.leading,
    required this.onTap,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxPressable(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: rx.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: rx.textPrimary.withValues(alpha: 0.12)),
            boxShadow: rx.cardShadow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RxText.body(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google + GitHub side by side.
class AuthSocialRow extends StatelessWidget {
  const AuthSocialRow({
    super.key,
    required this.onGoogle,
    required this.onGithub,
  });

  final VoidCallback? onGoogle;
  final VoidCallback? onGithub;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AuthSocialButton(
            label: 'Google',
            onTap: onGoogle,
            leading: Image.asset(
              'assets/images/google_logo.png',
              width: 20,
              height: 20,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AuthSocialButton(
            label: 'GitHub',
            onTap: onGithub,
            leading: HugeIcon(
              icon: HugeIcons.strokeRoundedGithub,
              color: context.rx.textPrimary,
              size: 21,
              strokeWidth: 1.8,
            ),
          ),
        ),
      ],
    );
  }
}

/// GitHub sign-in is UI only for now; the provider is wired up later.
void showGithubComingSoon(BuildContext context) =>
    showRxToast(context, 'GitHub sign-in is coming soon');

/// Tinted status banner (sent / info / error) that grows in.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    super.key,
    required this.icon,
    required this.text,
    this.tone = AuthNoticeTone.positive,
  });

  final List<List<dynamic>> icon;
  final String text;
  final AuthNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final (bg, fg) = switch (tone) {
      AuthNoticeTone.positive => (rx.positiveSoft, rx.positive),
      AuthNoticeTone.negative => (rx.negativeSoft, rx.negative),
      AuthNoticeTone.neutral => (rx.surfaceMuted, rx.textPrimary),
    };
    return RxReveal(
      offset: 8,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HugeIcon(icon: icon, color: fg, size: 18, strokeWidth: 1.9),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: RxText.caption(
                  context,
                  color: fg,
                ).copyWith(fontSize: 13.5, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum AuthNoticeTone { positive, negative, neutral }

/// Inline field error under an input. Animates in and out.
class AuthFieldError extends StatelessWidget {
  const AuthFieldError({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topLeft,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(
                text!,
                style: RxText.caption(context, color: context.rx.negative),
              ),
            ),
    );
  }
}

/// Fine print under the sign-up form.
class AuthFinePrint extends StatelessWidget {
  const AuthFinePrint({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: RxText.micro(context).copyWith(height: 1.45),
  );
}

/// Hairline with centred text ("or").
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, this.text = 'or'});
  final String text;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final line = Expanded(
      child: Container(
        height: 1,
        color: rx.textPrimary.withValues(alpha: 0.08),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text, style: RxText.micro(context)),
        ),
        line,
      ],
    );
  }
}

/// "Prompt  Action" footer line, e.g. "New here?  Create account".
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(prompt, style: RxText.label(context)),
        RxPressable(
          onTap: onTap,
          semanticLabel: action,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Text(
              action,
              style: RxText.label(context, color: context.rx.textPrimary)
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: context.rx.accent,
                    decorationThickness: 2,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small text button, e.g. "Forgot password?".
class AuthTextLink extends StatelessWidget {
  const AuthTextLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RxPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Text(
          label,
          style: RxText.label(
            context,
            color: context.rx.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Big title + supporting line at the top of each auth screen.
class AuthTitle extends StatelessWidget {
  const AuthTitle({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: RxText.title(context).copyWith(fontSize: 30)),
        const SizedBox(height: 6),
        Text(subtitle, style: RxText.label(context).copyWith(fontSize: 14.5)),
      ],
    );
  }
}
