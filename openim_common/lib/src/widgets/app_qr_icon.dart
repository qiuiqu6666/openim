import 'package:flutter/material.dart';

/// QR entry artwork ported from the 99chat profile surface.
///
/// Keep the geometry in this shared component so every migrated QR entry uses
/// the same optical shape instead of depending on the Flutter Material glyph,
/// whose outline can differ between SDK versions.
class AppQrIcon extends StatelessWidget {
  const AppQrIcon({
    super.key,
    this.size = 24,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _QrIconPainter(
            color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
}

class _QrIconPainter extends CustomPainter {
  const _QrIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Preserve the reference's slightly wider-than-tall aspect ratio.
    canvas.translate(0, size.height * 7 / 400);
    canvas.scale(size.width / 400, size.height / 400);

    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(90, 14)
        ..lineTo(35, 14)
        ..quadraticBezierTo(12, 14, 12, 38)
        ..lineTo(12, 94)
        ..moveTo(308, 11)
        ..lineTo(363, 11)
        ..quadraticBezierTo(390, 11, 390, 38)
        ..lineTo(390, 89)
        ..moveTo(12, 293)
        ..lineTo(12, 349)
        ..quadraticBezierTo(12, 375, 37, 375)
        ..lineTo(90, 375)
        ..moveTo(308, 375)
        ..lineTo(362, 375)
        ..quadraticBezierTo(390, 375, 390, 349)
        ..lineTo(390, 296),
      stroke,
    );

    for (final origin in const [
      Offset(60, 55),
      Offset(216, 55),
      Offset(60, 206),
    ]) {
      final outer = RRect.fromRectAndRadius(
        origin & const Size(126, 129),
        const Radius.circular(24),
      );
      final inner = RRect.fromRectAndRadius(
        (origin + const Offset(22, 23)) & const Size(82, 84),
        const Radius.circular(20),
      );
      canvas.drawDRRect(outer, inner, fill);
      canvas.drawCircle(origin + const Offset(63, 64.5), 20, fill);
    }

    for (final origin in const [
      Offset(222, 208),
      Offset(302, 208),
      Offset(262, 251),
      Offset(222, 293),
      Offset(302, 293),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          origin & const Size(39, 41),
          const Radius.circular(7),
        ),
        fill,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _QrIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
