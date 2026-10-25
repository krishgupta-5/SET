import 'package:flutter/material.dart';

import 'rx_ui.dart';

/// The RunwayX mark (road + chevron), drawn from the landing site's
/// `public/favicon.svg` so it stays sharp at any size. The road follows the
/// theme (ink on light, paper on dark); the chevron stays brand green.
class RxLogo extends StatelessWidget {
  const RxLogo({super.key, this.size = 32, this.roadColor, this.chevronColor});

  final double size;

  /// Overrides, e.g. white road on a dark photo.
  final Color? roadColor;
  final Color? chevronColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'RunwayX',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(
          road:
              roadColor ??
              (dark ? const Color(0xFFF4F4F0) : const Color(0xFF111111)),
          chevron:
              chevronColor ??
              (dark ? const Color(0xFF9BE15D) : const Color(0xFF7FCB3F)),
        ),
      ),
    );
  }
}

/// Mark + "RunwayX" wordmark, as in the site's navbar.
class RxWordmark extends StatelessWidget {
  const RxWordmark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RxLogo(size: size),
        SizedBox(width: size * 0.3),
        Text(
          'RunwayX',
          style: RxText.heading(context).copyWith(
            fontSize: size * 0.62,
            letterSpacing: -0.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.road, required this.chevron});

  final Color road;
  final Color chevron;

  @override
  void paint(Canvas canvas, Size size) {
    // SVG viewBox is "8 7.5 32 32": shift to origin, scale to size.
    final k = size.width / 32;
    canvas.save();
    canvas.scale(k);
    canvas.translate(-8, -7.5);

    final roadPaint = Paint()..color = road;
    canvas.drawPath(
      Path()
        ..moveTo(8.5, 39)
        ..lineTo(15.5, 39)
        ..lineTo(23, 21)
        ..lineTo(20, 21)
        ..close(),
      roadPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(39.5, 39)
        ..lineTo(32.5, 39)
        ..lineTo(25, 21)
        ..lineTo(28, 21)
        ..close(),
      roadPaint,
    );
    canvas.drawRect(const Rect.fromLTWH(22.2, 32.5, 3.6, 3.5), roadPaint);
    canvas.drawRect(const Rect.fromLTWH(22.6, 25.5, 2.8, 3), roadPaint);

    canvas.drawPath(
      Path()
        ..moveTo(24, 8)
        ..lineTo(32.2, 18.2)
        ..lineTo(27.7, 18.2)
        ..lineTo(24, 13.3)
        ..lineTo(20.3, 18.2)
        ..lineTo(15.8, 18.2)
        ..close(),
      Paint()..color = chevron,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.road != road || old.chevron != chevron;
}
