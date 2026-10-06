import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Quiet curves behind the auth surface, painted without image assets.
class AuthWaveBackground extends StatelessWidget {
  const AuthWaveBackground({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: _WavePainter(
              AppTokens.accent,
              Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        ),
      );
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.color, this.dark);
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint();
    void wave(Rect rect, double opacity) {
      paint.shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
      ).createShader(rect);
      canvas.drawOval(rect, paint);
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final alpha = dark ? .09 : .085;
    wave(Rect.fromLTWH(-w * .45, -h * .29, w * .92, h * .42), alpha);
    wave(Rect.fromLTWH(w * .36, h * .05, w * .98, h * .34), alpha);
    wave(Rect.fromLTWH(-w * .72, h * .83, w * 1.46, h * .61), alpha);
    wave(Rect.fromLTWH(w * .22, h * .83, w * 1.42, h * .62), alpha * 1.3);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dark != dark;
}
