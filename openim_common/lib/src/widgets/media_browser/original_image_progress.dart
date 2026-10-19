import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../res/app_tokens.dart';

/// A filled sector reports real byte progress, without a looping animation.
class OriginalImageProgress extends StatelessWidget {
  const OriginalImageProgress({super.key, this.event});

  final ImageChunkEvent? event;

  double? get progress {
    final total = event?.expectedTotalBytes;
    if (total == null || total <= 0) return null;
    return (event!.cumulativeBytesLoaded / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final value = progress;
    final label = 'mediaViewOriginal'.tr;
    return IgnorePointer(
      child: Semantics(
        label: label,
        value: value == null ? null : '${(value * 100).floor()}%',
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s3),
          child: SizedBox.square(
            dimension: AppTokens.s8,
            child: CustomPaint(
              painter: _SectorPainter(
                progress: value,
                color: AppTokens.textPrimary(dark: true),
              ),
              // Unknown content length must not invent a percentage.
              child: value == null
                  ? Icon(Icons.downloading,
                      color: AppTokens.textPrimary(dark: true),
                      size: AppTokens.s5)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectorPainter extends CustomPainter {
  const _SectorPainter({required this.progress, required this.color});
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
      canvas.drawArc(rect.deflate(3), -math.pi / 2, math.pi * 2 * progress!,
          true, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SectorPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
