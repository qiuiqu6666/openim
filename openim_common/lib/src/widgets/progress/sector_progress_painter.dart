import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared filled-sector progress for media downloads and message uploads.
class SectorProgressPainter extends CustomPainter {
  const SectorProgressPainter({required this.progress, required this.color});
  final double? progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    canvas.drawOval(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    if (progress != null) {
      canvas.drawArc(
          rect.deflate(3),
          -math.pi / 2,
          math.pi * 2 * progress!.clamp(0.0, 1.0),
          true,
          Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(SectorProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
