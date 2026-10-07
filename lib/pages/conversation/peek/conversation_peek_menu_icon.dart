import 'package:flutter/material.dart';

import 'conversation_peek_actions.dart';

/// Rounded outline artwork traced from the conversation menu reference.
/// Keeping paths here makes the silhouettes identical on Android and iOS.
class ConversationPeekMenuIcon extends StatelessWidget {
  const ConversationPeekMenuIcon({
    super.key,
    required this.action,
    required this.color,
    this.size = 20,
    this.isMuted = false,
  });

  final ConversationPeekAction action;
  final Color color;
  final double size;
  final bool isMuted;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child:
            CustomPaint(painter: _PeekMenuIconPainter(action, color, isMuted)),
      );
}

class _PeekMenuIconPainter extends CustomPainter {
  const _PeekMenuIconPainter(this.action, this.color, this.isMuted);

  final ConversationPeekAction action;
  final Color color;
  final bool isMuted;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (action) {
      case ConversationPeekAction.archive:
        path.moveTo(3, 7);
        path.lineTo(5.1, 3.8);
        path.quadraticBezierTo(5.7, 3, 6.7, 3);
        path.lineTo(17.3, 3);
        path.quadraticBezierTo(18.3, 3, 18.9, 3.8);
        path.lineTo(21, 7);
        path.lineTo(21, 19.3);
        path.quadraticBezierTo(21, 21, 19.3, 21);
        path.lineTo(4.7, 21);
        path.quadraticBezierTo(3, 21, 3, 19.3);
        path.close();
        path.moveTo(3, 7);
        path.lineTo(21, 7);
        path.moveTo(12, 11);
        path.lineTo(12, 16.7);
        path.moveTo(9.2, 14);
        path.lineTo(12, 16.8);
        path.lineTo(14.8, 14);
      case ConversationPeekAction.addToFolder:
      case ConversationPeekAction.removeFromFolder:
        path.moveTo(2, 6);
        path.quadraticBezierTo(2, 4, 4, 4);
        path.lineTo(8.5, 4);
        path.quadraticBezierTo(9.3, 4, 9.8, 4.6);
        path.lineTo(11.5, 6.3);
        path.lineTo(20, 6.3);
        path.quadraticBezierTo(22, 6.3, 22, 8.3);
        path.lineTo(22, 19);
        path.quadraticBezierTo(22, 21, 20, 21);
        path.lineTo(4, 21);
        path.quadraticBezierTo(2, 21, 2, 19);
        path.close();
        path.moveTo(9, 13.7);
        path.lineTo(15, 13.7);
        if (action == ConversationPeekAction.addToFolder) {
          path.moveTo(12, 10.7);
          path.lineTo(12, 16.7);
        }
      case ConversationPeekAction.togglePin:
        path.moveTo(6.4, 2.6);
        path.lineTo(17.6, 2.6);
        path.moveTo(8, 2.6);
        path.lineTo(8, 8.8);
        path.quadraticBezierTo(8, 11.4, 5.1, 13.6);
        path.lineTo(18.9, 13.6);
        path.quadraticBezierTo(16, 11.4, 16, 8.8);
        path.lineTo(16, 2.6);
        path.moveTo(12, 13.6);
        path.lineTo(12, 22);
      case ConversationPeekAction.toggleMute:
        if (isMuted) {
          path.moveTo(4, 18.5);
          path.quadraticBezierTo(6, 17, 6, 14.5);
          path.lineTo(6, 10.5);
          path.cubicTo(6, 2.4, 18, 2.4, 18, 10.5);
          path.lineTo(18, 14.5);
          path.quadraticBezierTo(18, 17, 20, 18.5);
          path.close();
        } else {
          path.moveTo(10.3, 4.9);
          path.cubicTo(14.7, 3.6, 18, 7, 18, 11);
          path.lineTo(18, 12);
          path.moveTo(6.4, 8.1);
          path.quadraticBezierTo(6, 9.2, 6, 10.7);
          path.lineTo(6, 14.5);
          path.quadraticBezierTo(6, 17, 3.8, 18.5);
          path.lineTo(19, 18.5);
          path.moveTo(4, 3.8);
          path.lineTo(21, 20.1);
        }
        path.moveTo(11, 3.3);
        path.quadraticBezierTo(12, 2.6, 13, 3.3);
        path.moveTo(10.7, 22);
        path.quadraticBezierTo(12, 22.7, 13.3, 22);
      case ConversationPeekAction.delete:
        path.moveTo(8.3, 4.7);
        path.lineTo(8.3, 2.8);
        path.quadraticBezierTo(8.3, 2, 9.1, 2);
        path.lineTo(14.9, 2);
        path.quadraticBezierTo(15.7, 2, 15.7, 2.8);
        path.lineTo(15.7, 4.7);
        path.moveTo(3.7, 5.1);
        path.lineTo(20.3, 5.1);
        path.moveTo(5.1, 8.3);
        path.lineTo(5.1, 18.9);
        path.quadraticBezierTo(5.1, 21.7, 7.9, 21.7);
        path.lineTo(16.1, 21.7);
        path.quadraticBezierTo(18.9, 21.7, 18.9, 18.9);
        path.lineTo(18.9, 8.3);
        path.moveTo(12, 9.7);
        path.lineTo(12, 17.1);
      case ConversationPeekAction.openChat:
        path.moveTo(4, 3);
        path.lineTo(20, 3);
        path.quadraticBezierTo(22, 3, 22, 5);
        path.lineTo(22, 16);
        path.quadraticBezierTo(22, 18, 20, 18);
        path.lineTo(8, 18);
        path.lineTo(2, 22);
        path.lineTo(2, 5);
        path.quadraticBezierTo(2, 3, 4, 3);
    }
    canvas.drawPath(path, pen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PeekMenuIconPainter oldDelegate) =>
      action != oldDelegate.action ||
      color != oldDelegate.color ||
      isMuted != oldDelegate.isMuted;
}
