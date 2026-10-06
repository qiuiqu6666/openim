import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 图二风格：渐隐圆弧转圈（头实尾透）。
class FadingArcSpinner extends StatefulWidget {
  const FadingArcSpinner({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 2.8,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  State<FadingArcSpinner> createState() => _FadingArcSpinnerState();
}

class _FadingArcSpinnerState extends State<FadingArcSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _controller.value * math.pi * 2,
            child: child,
          );
        },
        child: CustomPaint(
          painter: _FadingArcPainter(
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _FadingArcPainter extends CustomPainter {
  _FadingArcPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.12),
          color.withValues(alpha: 0.55),
          color,
        ],
        stops: const [0.0, 0.35, 0.72, 1.0],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);

    // 约 3/4 圈，留出缺口，贴近系统渐隐转圈观感。
    canvas.drawArc(rect, 0, math.pi * 1.55, false, paint);
  }

  @override
  bool shouldRepaint(covariant _FadingArcPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
