import 'package:flutter/material.dart';

/// Motion kit for the redesign (better-ui / Emil rules):
/// - Entrances: opacity + 12px rise, 300ms ease-out, staggered per section.
///   They run once, on first build; later rebuilds don't replay them.
/// - Data: bars and tracks grow from zero, then glide to new values.
/// - Reduced motion (OS setting): no movement or growth, opacity only.

const _enterCurve = Curves.easeOutCubic;

/// Fades and lifts [child] into place once, after [delay].
class RxReveal extends StatefulWidget {
  const RxReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 12,
    this.duration = const Duration(milliseconds: 300),
  });

  /// Convenience for staggered lists: delay = index x 60ms, capped at 360ms.
  factory RxReveal.index(int i, {Key? key, required Widget child}) => RxReveal(
    key: key,
    delay: Duration(milliseconds: (i * 60).clamp(0, 360)),
    child: child,
  );

  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  State<RxReveal> createState() => _RxRevealState();
}

class _RxRevealState extends State<RxReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: _enterCurve,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        return Opacity(
          opacity: v,
          child: reduce
              ? child
              : Transform.translate(
                  offset: Offset(0, widget.offset * (1 - v)),
                  child: child,
                ),
        );
      },
    );
  }
}

/// Animates a 0..1 fraction: starts from 0 on first build, then eases to
/// each new value. Use it to drive bar heights, track widths and sweeps.
class RxGrow extends StatelessWidget {
  const RxGrow({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 650),
    this.delay = Duration.zero,
  });

  final double value;
  final Widget Function(BuildContext context, double value) builder;
  final Duration duration;

  /// Extra hold before growing, for left-to-right cascades. Only the first
  /// run is delayed; value changes animate immediately.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return builder(context, value);
    }
    final total = duration + delay;
    final lead = total.inMicroseconds == 0
        ? 0.0
        : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: total,
      curve: Interval(lead, 1, curve: _enterCurve),
      builder: (context, v, _) => builder(context, v),
    );
  }
}
