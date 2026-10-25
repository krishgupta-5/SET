import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../widgets/rx_ui.dart';

/// Visual pieces for the AI CFO tab. All art is drawn in code, so it is
/// crisp at any size and follows light/dark mode. Every loop stops under
/// the OS reduced-motion setting.

bool _reduce(BuildContext c) => MediaQuery.disableAnimationsOf(c);

// ---------------------------------------------------------------------------
// Thinking state
// ---------------------------------------------------------------------------

enum AiBotMood { thinking, offline }

/// The AI CFO character, drawn in code: a small robot that floats, blinks
/// and glows. [AiBotMood.thinking] glances around with a typing bubble;
/// [AiBotMood.offline] dozes with floating "z"s and a dim antenna.
class AiBot extends StatefulWidget {
  const AiBot({
    super.key,
    this.mood = AiBotMood.thinking,
    this.size = 120,
    this.bubble = true,
  });

  final AiBotMood mood;
  final double size;

  /// Typing bubble beside the head while thinking. Off for hero art.
  final bool bubble;

  @override
  State<AiBot> createState() => _AiBotState();
}

class _AiBotState extends State<AiBot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduce(context)) {
      _c.stop();
      _c.value = 0.25;
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.size / 120; // Drawn at 120, scaled.
    final offline = widget.mood == AiBotMood.offline;
    final accent = offline ? rx.textTertiary : rx.accent;
    final ink = rx.textPrimary;

    return ExcludeSemantics(
      child: SizedBox(
        width: 190 * s,
        height: 170 * s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            final t = v * 2 * math.pi;
            final bob = (offline ? 3 : 5) * s * math.sin(t);
            // Blink twice per loop (thinking only).
            double blink(double at) {
              final d = (v - at).abs();
              return d < 0.025 ? (d / 0.025).clamp(0.1, 1.0) : 1.0;
            }

            final eyeOpen = offline ? 0.12 : blink(0.3) * blink(0.78);
            // Eyes glance left, centre, right while thinking.
            final glance = offline ? 0.0 : 4 * s * math.sin(t * 1);
            final glow = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * 2));

            Widget eye() => Container(
              width: 14 * s,
              height: 18 * s * eyeOpen,
              decoration: BoxDecoration(
                color: offline ? ink.withValues(alpha: 0.5) : accent,
                borderRadius: BorderRadius.circular(8 * s),
                boxShadow: offline
                    ? null
                    : [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.6 * glow),
                          blurRadius: 10 * s,
                        ),
                      ],
              ),
            );

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Soft halo behind the character.
                Container(
                  width: 150 * s,
                  height: 150 * s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (offline ? rx.textTertiary : rx.accent).withValues(
                          alpha: dark ? 0.16 : 0.14,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Ground shadow that shrinks as the bot rises.
                Positioned(
                  bottom: 8 * s,
                  child: Container(
                    width: (64 - bob * 0.8) * s,
                    height: 8 * s,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: dark ? 0.25 : 0.10),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -6 * s + bob),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Antenna
                      Container(
                        width: 12 * s,
                        height: 12 * s,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: offline
                              ? null
                              : [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.7 * glow),
                                    blurRadius: 14 * s * glow,
                                  ),
                                ],
                        ),
                      ),
                      Container(
                        width: 3 * s,
                        height: 10 * s,
                        color: ink.withValues(alpha: 0.25),
                      ),
                      // Head
                      Container(
                        width: 96 * s,
                        height: 76 * s,
                        decoration: BoxDecoration(
                          color: rx.surface,
                          borderRadius: BorderRadius.circular(26 * s),
                          border: Border.all(color: rx.hairline),
                          boxShadow: dark
                              ? null
                              : const [
                                  BoxShadow(
                                    color: Color(0x1A101828),
                                    blurRadius: 18,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                        ),
                        padding: EdgeInsets.all(9 * s),
                        // Face screen
                        child: Container(
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xFF0C0F0A)
                                : const Color(0xFF14161A),
                            borderRadius: BorderRadius.circular(18 * s),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Transform.translate(
                                offset: Offset(glance, 0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    eye(),
                                    SizedBox(width: 16 * s),
                                    eye(),
                                  ],
                                ),
                              ),
                              SizedBox(height: 7 * s),
                              Container(
                                width: offline ? 12 * s : 18 * s,
                                height: 3 * s,
                                decoration: BoxDecoration(
                                  color: (offline ? Colors.white : accent)
                                      .withValues(alpha: offline ? 0.35 : 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Mood extras
                if (!offline && widget.bubble)
                  Positioned(
                    right: 6 * s,
                    top: 26 * s + bob * 0.6,
                    child: Opacity(
                      opacity: (0.6 + 0.4 * math.sin(t * 2)).clamp(0.0, 1.0),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 9 * s,
                          vertical: 8 * s,
                        ),
                        decoration: BoxDecoration(
                          color: rx.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(14 * s),
                            topRight: Radius.circular(14 * s),
                            bottomRight: Radius.circular(14 * s),
                            bottomLeft: Radius.circular(4 * s),
                          ),
                          border: Border.all(color: rx.hairline),
                        ),
                        child: const AiTypingDots(),
                      ),
                    ),
                  )
                else if (offline)
                  for (var i = 0; i < 3; i++)
                    Builder(
                      builder: (_) {
                        final p = ((v * 1.5) + i / 3) % 1;
                        return Positioned(
                          right: (30 - 14 * p + i * 4) * s,
                          top: (52 - 40 * p) * s,
                          child: Opacity(
                            opacity: math.sin(p * math.pi).clamp(0.0, 1.0),
                            child: Text(
                              'z',
                              style: RxText.value(
                                context,
                                size: (12 + 6 * p) * s,
                                color: rx.textSecondary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Loading state: the AI character with a slowly changing status line,
/// centred on its own (no placeholder cards).
class AiThinking extends StatefulWidget {
  const AiThinking({super.key});

  static const _steps = [
    'Reading your expenses',
    'Checking your runway',
    'Comparing monthly burn',
    'Looking for savings',
    'Writing your briefing',
  ];

  @override
  State<AiThinking> createState() => _AiThinkingState();
}

class _AiThinkingState extends State<AiThinking> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (mounted) setState(() => _i = (_i + 1) % AiThinking._steps.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AiBot(),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
              child: child,
            ),
          ),
          child: Text(
            '${AiThinking._steps[_i]}…',
            key: ValueKey(_i),
            textAlign: TextAlign.center,
            style: RxText.heading(context).copyWith(fontSize: 17),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your AI CFO is preparing today\'s briefing',
          textAlign: TextAlign.center,
          style: RxText.caption(context),
        ),
      ],
    );
  }
}

/// Offline state: dozing AI character, a friendly line and a retry button.
class AiOffline extends StatelessWidget {
  const AiOffline({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AiBot(mood: AiBotMood.offline),
        const SizedBox(height: 18),
        Text(
          'Your AI CFO is taking a break',
          textAlign: TextAlign.center,
          style: RxText.heading(context).copyWith(fontSize: 17),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            "We couldn't reach the AI right now. Your numbers are safe.",
            textAlign: TextAlign.center,
            style: RxText.caption(context).copyWith(height: 1.45),
          ),
        ),
        const SizedBox(height: 20),
        RxPressable(
          onTap: onRetry,
          semanticLabel: 'Try again',
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
                  icon: HugeIcons.strokeRoundedRefresh,
                  color: rx.onInverse,
                  size: 17,
                  strokeWidth: 2,
                ),
                const SizedBox(width: 8),
                Text(
                  'Try again',
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
    );
  }
}

/// Three dots that rise and fade in turn, like someone typing.
class AiTypingDots extends StatefulWidget {
  const AiTypingDots({super.key, this.color});
  final Color? color;

  @override
  State<AiTypingDots> createState() => _AiTypingDotsState();
}

class _AiTypingDotsState extends State<AiTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
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
    final color = widget.color ?? context.rx.textSecondary;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Builder(
                builder: (_) {
                  final p = ((_c.value - i * 0.18) % 1);
                  final k = math.sin(p * math.pi).clamp(0.0, 1.0);
                  return Transform.translate(
                    offset: Offset(0, -3 * k),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.35 + 0.65 * k),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text reveal
// ---------------------------------------------------------------------------

/// Reveals [text] word by word, like it's being written, then stays put.
/// Plays once per [text]; reduced motion shows it all at once.
class AiTypewriter extends StatefulWidget {
  const AiTypewriter({
    super.key,
    required this.text,
    required this.style,
    this.delay = Duration.zero,
    this.wordMs = 95,
    this.onDone,
  });

  final String text;
  final TextStyle style;
  final Duration delay;
  final int wordMs;
  final VoidCallback? onDone;

  @override
  State<AiTypewriter> createState() => _AiTypewriterState();
}

class _AiTypewriterState extends State<AiTypewriter>
    with SingleTickerProviderStateMixin {
  late List<String> _words = _split(widget.text);
  late AnimationController _c = _make();
  bool _started = false;

  static List<String> _split(String t) =>
      RegExp(r'\S+\s*').allMatches(t).map((m) => m.group(0)!).toList();

  AnimationController _make() =>
      AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds: (widget.wordMs * (_words.length + 3)).clamp(600, 14000),
        ),
      )..addStatusListener((s) {
        // Deferred: completion can fire mid-build (reduced motion jumps the
        // value straight to 1), and onDone usually calls setState.
        if (s == AnimationStatus.completed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onDone?.call();
          });
        }
      });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduce(context)) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AiTypewriter old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _c.dispose();
      _words = _split(widget.text);
      _c = _make();
      if (_reduce(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final n = _words.length;
          // Each word fades in over a soft window of [_fade] words, so the
          // text flows on gently instead of popping word by word.
          const fade = 3.0;
          final head = _c.value * (n + fade);
          final base = widget.style.color?.a ?? 1;
          return Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < n; i++)
                  TextSpan(
                    text: _words[i],
                    style: widget.style.copyWith(
                      color: widget.style.color?.withValues(
                        alpha:
                            base *
                            Curves.easeOut.transform(
                              ((head - i) / fade).clamp(0.0, 1.0),
                            ),
                      ),
                    ),
                  ),
              ],
            ),
            style: widget.style,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

enum AiTone { brand, positive, warning, negative, info }

extension AiToneColors on AiTone {
  Color fg(RxColors rx, bool dark) => switch (this) {
    AiTone.brand => dark ? rx.accent : rx.textPrimary,
    AiTone.positive => rx.positive,
    AiTone.warning => rx.warning,
    AiTone.negative => rx.negative,
    AiTone.info => dark ? const Color(0xFF6EA2FF) : const Color(0xFF2F6FE0),
  };

  Color bg(RxColors rx, bool dark) => switch (this) {
    AiTone.brand => dark ? rx.accent.withValues(alpha: 0.14) : rx.surfaceMuted,
    AiTone.positive => rx.positiveSoft,
    AiTone.warning => rx.warningSoft,
    AiTone.negative => rx.negativeSoft,
    AiTone.info =>
      (dark ? const Color(0xFF6EA2FF) : const Color(0xFF2F6FE0)).withValues(
        alpha: dark ? 0.16 : 0.09,
      ),
  };
}

/// One insight section: small tinted icon and a title, then [child].
/// Flat on purpose: one card, no nested boxes, no badges.
class AiSection extends StatelessWidget {
  const AiSection({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.tone,
    required this.child,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String? subtitle;
  final AiTone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RxCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RxIconTile(
                icon: icon,
                size: 30,
                iconSize: 16,
                background: tone.bg(rx, dark),
                foreground: tone.fg(rx, dark),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: RxText.heading(context))),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Tiny "AI" marker with a sparkle that twinkles.
class AiChip extends StatefulWidget {
  const AiChip({super.key, this.label = 'AI'});
  final String label;

  @override
  State<AiChip> createState() => _AiChipState();
}

class _AiChipState extends State<AiChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? rx.accent : rx.textPrimary;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: dark ? rx.accent.withValues(alpha: 0.12) : rx.surfaceMuted,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Transform.rotate(
              angle: _c.value * 2 * math.pi * 0.25,
              child: Opacity(
                opacity: 0.55 + 0.45 * math.sin(_c.value * 2 * math.pi).abs(),
                child: child,
              ),
            ),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedSparkles,
              color: fg,
              size: 12,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            widget.label,
            style: RxText.micro(
              context,
              color: fg,
            ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

/// One recommendation as a plain row: number, title, saving on the right,
/// one line of detail underneath.
class AiRecommendation extends StatelessWidget {
  const AiRecommendation({
    super.key,
    required this.index,
    required this.title,
    required this.description,
    this.savings,
    required this.tone,
  });

  final int index;
  final String title;
  final String description;
  final String? savings;
  final AiTone tone;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final hasSavings =
        savings != null && savings!.trim().isNotEmpty && savings != 'N/A';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Text(
            '$index',
            style: RxText.body(
              context,
              color: rx.textTertiary,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: RxText.body(context).copyWith(height: 1.3),
                    ),
                  ),
                  if (hasSavings) ...[
                    const SizedBox(width: 10),
                    Text(
                      savings!,
                      style: RxText.label(
                        context,
                        color: rx.positive,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
              if (description.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  description,
                  style: RxText.caption(context).copyWith(height: 1.45),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bullet with a tick, for short point lists.
class AiBullet extends StatelessWidget {
  const AiBullet({super.key, required this.text, required this.tone});

  final String text;
  final AiTone tone;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 1),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: tone.bg(rx, dark),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedTick02,
            color: tone.fg(rx, dark),
            size: 12,
            strokeWidth: 2.6,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: RxText.body(
              context,
              color: rx.textSecondary,
            ).copyWith(fontWeight: FontWeight.w400, height: 1.45),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar
// ---------------------------------------------------------------------------

/// Compact head of [AiBot] for profile spots (chat header, message avatar).
/// Blinks, glances and pulses its antenna; [thinking] makes the eyes scan
/// faster and the antenna glow brighter.
class AiBotAvatar extends StatefulWidget {
  const AiBotAvatar({
    super.key,
    this.size = 36,
    this.thinking = false,
    this.animate = true,
  });

  final double size;
  final bool thinking;

  /// False draws a still pose (e.g. the chat header).
  final bool animate;

  @override
  State<AiBotAvatar> createState() => _AiBotAvatarState();
}

class _AiBotAvatarState extends State<AiBotAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate || _reduce(context)) {
      _c.stop();
      // 0 = rest pose: eyes centred (no glance) and no bob. The old 0.25
      // was the peak of the glance, which pushed the eyes to the right.
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AiBotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final d = widget.size;
    final accent = rx.accent;

    return ExcludeSemantics(
      child: SizedBox(
        width: d,
        height: d,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            final t = v * 2 * math.pi;
            double blink(double at) {
              final x = (v - at).abs();
              return x < 0.025 ? (x / 0.025).clamp(0.1, 1.0) : 1.0;
            }

            final eyeOpen = blink(0.3) * blink(0.78);
            final speed = widget.thinking ? 3.0 : 1.0;
            // Idle: cubed sine so the eyes rest in the centre and only
            // glance briefly to each side. Thinking: steady left-right scan.
            final s = math.sin(t * speed);
            final glance = widget.thinking
                ? d * 0.05 * s
                : d * 0.05 * s * s * s;
            final glow = widget.thinking
                ? 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 6))
                : 0.4 + 0.3 * (0.5 + 0.5 * math.sin(t * 2));
            final bob = d * 0.03 * math.sin(t);

            Widget eye() => Container(
              width: d * 0.13,
              height: d * 0.17 * eyeOpen,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(d),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.6 * glow),
                    blurRadius: d * 0.12,
                  ),
                ],
              ),
            );

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Head
                Transform.translate(
                  offset: Offset(0, d * 0.06 + bob),
                  child: Container(
                    width: d,
                    height: d * 0.82,
                    padding: EdgeInsets.all(d * 0.09),
                    decoration: BoxDecoration(
                      color: rx.surface,
                      borderRadius: BorderRadius.circular(d * 0.3),
                      border: Border.all(
                        color: dark
                            ? accent.withValues(alpha: 0.28)
                            : rx.hairline,
                      ),
                      boxShadow: rx.cardShadow,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF0C0F0A)
                            : const Color(0xFF14161A),
                        borderRadius: BorderRadius.circular(d * 0.2),
                      ),
                      child: Transform.translate(
                        offset: Offset(glance, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            eye(),
                            SizedBox(width: d * 0.14),
                            eye(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Antenna light
                Positioned(
                  top: -d * 0.1 + bob,
                  child: Container(
                    width: d * 0.16,
                    height: d * 0.16,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.7 * glow),
                          blurRadius: d * 0.25 * glow,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
