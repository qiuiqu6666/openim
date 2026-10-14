import 'package:flutter/material.dart';

import 'connection_badge_style.dart';

/// The reference uses three separate rounded columns, not a cellular wedge.
class ConnectionSignalIcon extends StatelessWidget {
  const ConnectionSignalIcon(
      {super.key, required this.palette, required this.offline});
  final ConnectionBadgePalette palette;
  final bool offline;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(ConnectionBadgeStyle.iconSize),
        painter: _SignalPainter(palette, offline),
      );
}

class _SignalPainter extends CustomPainter {
  const _SignalPainter(this.palette, this.offline);
  final ConnectionBadgePalette palette;
  final bool offline;

  @override
  void paint(Canvas canvas, Size size) {
    // A 16 × 16 grid keeps the radii and gaps stable at all pixel densities.
    canvas.save();
    canvas.scale(size.width / 16, size.height / 16);
    final bounds = const Rect.fromLTWH(0, 0, 16, 16);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [palette.signalTop, palette.signalBottom],
      ).createShader(bounds);
    for (var i = 0; i < 3; i++) {
      final height = 5.0 + i * 5;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(i * 6.0, 16 - height, 4, height),
              const Radius.circular(1.5)),
          paint);
    }
    if (offline) {
      final slash = Paint()
        ..color = palette.backgroundTop
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(1, 3), const Offset(15, 16), slash);
      slash
        ..color = palette.text
        ..strokeWidth = 1.6;
      canvas.drawLine(const Offset(1, 3), const Offset(15, 16), slash);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SignalPainter oldDelegate) =>
      oldDelegate.offline != offline ||
      oldDelegate.palette.text != palette.text ||
      oldDelegate.palette.backgroundTop != palette.backgroundTop;
}
