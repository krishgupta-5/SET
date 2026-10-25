import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'rx_motion.dart';

/// Circular charts for the redesign. Both sweep in from 12 o'clock on first
/// build (give them a new key to replay), then glide to new values.
/// Reduced motion: drawn in their final state, no sweep.

/// One slice of an [RxDonut].
@immutable
class RxDonutSegment {
  const RxDonutSegment({required this.value, required this.color});

  final double value;
  final Color color;
}

/// Multi-segment donut with an optional centre label.
///
/// [selected] lifts one segment (thicker) and dims the rest, so a legend tap
/// can point at its slice.
class RxDonut extends StatelessWidget {
  const RxDonut({
    super.key,
    required this.segments,
    required this.trackColor,
    this.size = 176,
    this.thickness = 18,
    this.selected,
    this.center,
    this.gapDegrees = 2.5,
    this.duration = const Duration(milliseconds: 900),
    this.semanticLabel,
  });

  final List<RxDonutSegment> segments;
  final Color trackColor;
  final double size;
  final double thickness;
  final int? selected;
  final Widget? center;
  final double gapDegrees;
  final Duration duration;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RxGrow(
              value: 1,
              duration: duration,
              builder: (context, t) => CustomPaint(
                size: Size.square(size),
                painter: _DonutPainter(
                  segments: segments,
                  progress: t,
                  thickness: thickness,
                  trackColor: trackColor,
                  selected: selected,
                  gap: segments.length > 1 ? gapDegrees * math.pi / 180 : 0,
                ),
              ),
            ),
            if (center != null)
              Padding(
                // Keep centre text clear of the (possibly lifted) ring.
                padding: EdgeInsets.all(thickness + 14),
                child: center,
              ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.progress,
    required this.thickness,
    required this.trackColor,
    required this.selected,
    required this.gap,
  });

  final List<RxDonutSegment> segments;
  final double progress;
  final double thickness;
  final Color trackColor;
  final int? selected;
  final double gap;

  static const _lift = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Leave room for the lifted segment so it never clips.
    final radius = (size.shortestSide - thickness - _lift) / 2;
    final rect = Rect.fromCircle(center: c, radius: radius);

    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = trackColor,
    );

    final total = segments.fold<double>(0, (a, s) => a + math.max(0, s.value));
    if (total <= 0 || progress <= 0) return;

    const full = math.pi * 2;
    final available = full - gap * segments.length;
    // Every slice gets at least ~1.5deg so tiny categories stay visible.
    const minSweep = 0.026;
    final sweeps = [
      for (final s in segments)
        math.max(minSweep, available * math.max(0, s.value) / total),
    ];
    final scale = available / sweeps.fold<double>(0, (a, b) => a + b);

    final drawn = full * progress; // How far round the sweep has reached.
    var start = -math.pi / 2 + gap / 2;
    var travelled = 0.0;

    for (var i = 0; i < segments.length; i++) {
      final sweep = sweeps[i] * scale;
      final visible = (drawn - travelled).clamp(0.0, sweep);
      if (visible > 0) {
        final isSel = selected == i;
        final dim = selected != null && !isSel;
        canvas.drawArc(
          rect,
          start,
          visible,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSel ? thickness + _lift : thickness
            ..strokeCap = StrokeCap.butt
            ..color = dim
                ? segments[i].color.withValues(alpha: 0.28)
                : segments[i].color,
        );
      }
      start += sweep + gap;
      travelled += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.thickness != thickness ||
      old.trackColor != trackColor ||
      old.segments.length != segments.length ||
      !_sameSegments(old.segments, segments);

  static bool _sameSegments(List<RxDonutSegment> a, List<RxDonutSegment> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value || a[i].color != b[i].color) return false;
    }
    return true;
  }
}

/// Single-value ring gauge (0..1) with round caps and a centre label.
class RxRing extends StatelessWidget {
  const RxRing({
    super.key,
    required this.value,
    required this.color,
    required this.trackColor,
    this.size = 92,
    this.thickness = 9,
    this.center,
    this.semanticLabel,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double size;
  final double thickness;
  final Widget? center;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RxGrow(
              value: value.clamp(0.0, 1.0),
              duration: const Duration(milliseconds: 900),
              builder: (context, v) => CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(
                  value: v,
                  color: color,
                  trackColor: trackColor,
                  thickness: thickness,
                ),
              ),
            ),
            if (center != null)
              Padding(padding: EdgeInsets.all(thickness + 6), child: center),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.thickness,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = (size.shortestSide - thickness) / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(c, radius, base..color = trackColor);
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      base..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.thickness != thickness;
}
