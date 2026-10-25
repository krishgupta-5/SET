import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../widgets/rx_motion.dart';
import '../../../widgets/rx_ui.dart';
import '../../ai/widgets/ai_widgets.dart';

/// Visual pieces for company setup. Everything is drawn in code, follows
/// light / dark mode, and goes still under the OS reduced-motion setting.

bool _reduce(BuildContext c) => MediaQuery.disableAnimationsOf(c);

// ---------------------------------------------------------------------------
// Step guide: robot holding a step "prop" + typed tip
// ---------------------------------------------------------------------------

/// What the robot holds and says on one step.
class SetupScene {
  const SetupScene(this.prop, this.tip);
  final List<List<dynamic>> prop;
  final String tip;
}

/// The AI CFO walking you through setup: the robot floats on the left with
/// the current step's item (ID card, building, coins...) bobbing beside it.
/// The item pops in with a spin when the step changes, and a speech bubble
/// types that step's tip.
class SetupGuide extends StatefulWidget {
  const SetupGuide({super.key, required this.scene, required this.step});

  final SetupScene scene;

  /// Changes trigger the prop swap and a new tip.
  final int step;

  @override
  State<SetupGuide> createState() => _SetupGuideState();
}

class _SetupGuideState extends State<SetupGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          height: 88,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Positioned(
                left: -10,
                top: -6,
                child: AiBot(size: 64, bubble: false),
              ),
              // The step's item, bobbing beside the robot.
              Positioned(
                right: -4,
                bottom: 2,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, child) {
                    final t = _c.value * 2 * math.pi;
                    return Transform.translate(
                      offset: Offset(0, 3 * math.sin(t + 1.2)),
                      child: Transform.rotate(
                        angle: 0.08 * math.sin(t),
                        child: child,
                      ),
                    );
                  },
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: reduce ? 0 : 420),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, a) => ScaleTransition(
                      scale: a,
                      child: RotationTransition(
                        turns: Tween(begin: -0.12, end: 0.0).animate(a),
                        child: child,
                      ),
                    ),
                    child: Container(
                      key: ValueKey(widget.step),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: rx.accent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: rx.background, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: rx.accent.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: HugeIcon(
                        icon: widget.scene.prop,
                        color: const Color(0xFF0D0E0F),
                        size: 18,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _TipBubble(key: ValueKey(widget.step), text: widget.scene.tip),
        ),
      ],
    );
  }
}

/// Speech bubble pointing at the robot. Types its text once.
class _TipBubble extends StatelessWidget {
  const _TipBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = RxText.body(
      context,
      color: rx.textPrimary,
    ).copyWith(fontSize: 14, height: 1.4);

    return RxReveal(
      offset: 6,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: rx.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(5),
          ),
          border: Border.all(color: dark ? rx.hairline : Colors.transparent),
          boxShadow: rx.cardShadow,
        ),
        child: Semantics(
          label: text,
          child: ExcludeSemantics(
            child: _reduce(context)
                ? Text(text, style: style)
                : TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: text.length),
                    duration: Duration(milliseconds: 260 + text.length * 26),
                    builder: (_, n, _) => Stack(
                      children: [
                        // Full text, invisible: fixes the bubble size so it
                        // doesn't grow letter by letter.
                        Opacity(opacity: 0, child: Text(text, style: style)),
                        Text(text.substring(0, n), style: style),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

/// Six segments: done ones are ink, the current one fills with lime, later
/// ones are muted. Animates between steps.
class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Semantics(
      label: 'Step ${step + 1} of $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: Container(
                height: 6,
                margin: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
                decoration: BoxDecoration(
                  color: rx.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: i <= step ? 1 : 0),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        decoration: BoxDecoration(
                          color: i == step ? rx.accent : rx.inverse,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Choices
// ---------------------------------------------------------------------------

/// Selectable card with an icon, title and line, for small option sets
/// (company type). Selected: ink fill.
class SetupChoiceCard extends StatelessWidget {
  const SetupChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.error = false,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final fg = selected ? rx.onInverse : rx.textPrimary;
    return Semantics(
      selected: selected,
      child: RxPressable(
        onTap: onTap,
        semanticLabel: title,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: selected ? rx.inverse : rx.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? rx.inverse
                  : error
                  ? rx.negative
                  : rx.textPrimary.withValues(alpha: 0.10),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: selected
                          ? rx.onInverse.withValues(alpha: 0.12)
                          : rx.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: HugeIcon(
                      icon: icon,
                      color: fg,
                      size: 17,
                      strokeWidth: 1.9,
                    ),
                  ),
                  const Spacer(),
                  AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: selected ? 1 : 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: rx.accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const HugeIcon(
                        icon: HugeIcons.strokeRoundedTick02,
                        color: Color(0xFF0D0E0F),
                        size: 13,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RxText.heading(context).copyWith(color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: RxText.caption(
                  context,
                  color: selected
                      ? rx.onInverse.withValues(alpha: 0.7)
                      : rx.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toggle chip with a tick that grows in when selected.
class SetupChip extends StatelessWidget {
  const SetupChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.error = false,
    this.icon,
  });

  final String label;
  final bool selected;
  final bool error;
  final VoidCallback onTap;

  /// Shown when not selected (e.g. a plus for suggestions).
  final List<List<dynamic>>? icon;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Semantics(
      selected: selected,
      child: RxPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? rx.inverse : rx.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected
                  ? rx.inverse
                  : error
                  ? rx.negative.withValues(alpha: 0.6)
                  : rx.textPrimary.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedTick02,
                          color: rx.accent,
                          size: 15,
                          strokeWidth: 2.6,
                        ),
                      )
                    : icon != null
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: HugeIcon(
                          icon: icon!,
                          color: rx.textSecondary,
                          size: 15,
                          strokeWidth: 2,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Text(
                label,
                style: RxText.label(
                  context,
                  color: selected ? rx.onInverse : rx.textPrimary,
                ).copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square "+" button next to an input.
class SetupAddButton extends StatelessWidget {
  const SetupAddButton({super.key, required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: rx.inverse,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedAdd01,
          color: rx.onInverse,
          size: 20,
          strokeWidth: 2.2,
        ),
      ),
    );
  }
}

/// Dashed outline button ("Add another account").
class SetupDashedButton extends StatelessWidget {
  const SetupDashedButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxPressable(
      onTap: onTap,
      semanticLabel: label,
      child: CustomPaint(
        painter: _DashedRRect(color: rx.textPrimary.withValues(alpha: 0.25)),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedAdd01,
                color: rx.textPrimary,
                size: 18,
                strokeWidth: 2,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: RxText.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRRect extends CustomPainter {
  const _DashedRRect({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(16),
        ).deflate(0.5),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color;
}

/// Small "3 of 3 picked" style counter pill that ticks green when met.
class SetupCounter extends StatelessWidget {
  const SetupCounter({
    super.key,
    required this.count,
    required this.min,
    required this.noun,
  });

  final int count;
  final int min;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final ok = count >= min;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
      decoration: BoxDecoration(
        color: ok ? rx.positiveSoft : rx.surfaceMuted,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: ok
                ? HugeIcons.strokeRoundedCheckmarkCircle02
                : HugeIcons.strokeRoundedCircle,
            color: ok ? rx.positive : rx.textTertiary,
            size: 15,
            strokeWidth: 2,
          ),
          const SizedBox(width: 6),
          Text(
            ok ? '$count $noun picked' : '$count of $min $noun picked',
            style: RxText.micro(
              context,
              color: ok ? rx.positive : rx.textSecondary,
            ).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading + finishing
// ---------------------------------------------------------------------------

/// Centred robot with a line, while the screen checks setup status.
class SetupLoading extends StatelessWidget {
  const SetupLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AiBot(size: 104, bubble: false),
          const SizedBox(height: 14),
          Text('Checking your setup', style: RxText.label(context)),
        ],
      ),
    );
  }
}

/// Full-screen "building your workspace" moment shown while setup saves:
/// the robot at work with a checklist that ticks off one line at a time.
/// Purely visual; navigation still happens when the save completes.
class SetupFinishing extends StatefulWidget {
  const SetupFinishing({super.key, required this.companyName});
  final String companyName;

  static const _steps = [
    (HugeIcons.strokeRoundedBuilding03, 'Saving company profile'),
    (HugeIcons.strokeRoundedUserGroup, 'Creating your teams'),
    (HugeIcons.strokeRoundedTag01, 'Setting up categories'),
    (HugeIcons.strokeRoundedSparkles, 'Briefing your AI CFO'),
  ];

  @override
  State<SetupFinishing> createState() => _SetupFinishingState();
}

class _SetupFinishingState extends State<SetupFinishing> {
  int _done = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 750), (t) {
      if (!mounted) return;
      // Hold on the last line until the save completes.
      if (_done >= SetupFinishing._steps.length - 1) {
        t.cancel();
        return;
      }
      setState(() => _done++);
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
    final name = widget.companyName.trim();

    return ColoredBox(
      color: rx.background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RxReveal(child: AiBot(size: 120)),
                const SizedBox(height: 18),
                RxReveal(
                  delay: const Duration(milliseconds: 120),
                  child: Text(
                    name.isEmpty ? 'Building your workspace' : 'Building $name',
                    textAlign: TextAlign.center,
                    style: RxText.title(context).copyWith(fontSize: 26),
                  ),
                ),
                const SizedBox(height: 6),
                RxReveal(
                  delay: const Duration(milliseconds: 200),
                  child: Text(
                    'Your AI CFO is getting everything ready.',
                    textAlign: TextAlign.center,
                    style: RxText.label(context).copyWith(fontSize: 14.5),
                  ),
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  decoration: BoxDecoration(
                    color: rx.surface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: rx.cardShadow,
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? rx.hairline
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < SetupFinishing._steps.length; i++)
                        RxReveal(
                          delay: Duration(milliseconds: 260 + i * 90),
                          child: _FinishRow(
                            icon: SetupFinishing._steps[i].$1,
                            label: SetupFinishing._steps[i].$2,
                            state: i < _done
                                ? _RowState.done
                                : i == _done
                                ? _RowState.active
                                : _RowState.waiting,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _RowState { waiting, active, done }

class _FinishRow extends StatelessWidget {
  const _FinishRow({
    required this.icon,
    required this.label,
    required this.state,
  });

  final List<List<dynamic>> icon;
  final String label;
  final _RowState state;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          RxIconTile(icon: icon, size: 34, iconSize: 17),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: RxText.body(
                context,
                color: state == _RowState.waiting
                    ? rx.textTertiary
                    : rx.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 22,
            height: 22,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: switch (state) {
                _RowState.done => Container(
                  key: const ValueKey('done'),
                  decoration: BoxDecoration(
                    color: rx.positive,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedTick02,
                    color: rx.surface,
                    size: 13,
                    strokeWidth: 3,
                  ),
                ),
                _RowState.active => CircularProgressIndicator(
                  key: const ValueKey('active'),
                  strokeWidth: 2.2,
                  color: rx.textPrimary,
                ),
                _RowState.waiting => Container(
                  key: const ValueKey('wait'),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: rx.textTertiary, width: 1.5),
                  ),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}
