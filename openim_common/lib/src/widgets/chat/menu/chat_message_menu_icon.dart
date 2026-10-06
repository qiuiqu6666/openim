import 'package:flutter/material.dart';

/// Rounded outline artwork adapted from 99chat's message action menu.
class ChatMessageMenuIcon extends StatelessWidget {
  const ChatMessageMenuIcon({
    required this.action,
    required this.color,
    this.size = 22,
    super.key,
  });

  final String action;
  final Color color;
  final double size;

  static bool supports(String action) => const {
        'replyMessage',
        'copyMessage',
        'forwardMessage',
        'revoke',
        'favorite_message',
        'add_to_stickers',
        'delete',
        'mergeForward',
        'multiSelect',
        'voiceToText',
      }.contains(action);

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _ChatMessageMenuIconPainter(action, color)),
      );
}

class _ChatMessageMenuIconPainter extends CustomPainter {
  const _ChatMessageMenuIconPainter(this.action, this.color);

  final String action;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (action) {
      case 'replyMessage':
        path.moveTo(4.3, 4.2);
        path.lineTo(19.7, 4.2);
        path.quadraticBezierTo(22, 4.2, 22, 6.5);
        path.lineTo(22, 16.5);
        path.quadraticBezierTo(22, 18.8, 19.7, 18.8);
        path.lineTo(14.1, 18.8);
        path.lineTo(12, 21);
        path.lineTo(9.8, 18.8);
        path.lineTo(4.3, 18.8);
        path.quadraticBezierTo(2, 18.8, 2, 16.5);
        path.lineTo(2, 6.5);
        path.quadraticBezierTo(2, 4.2, 4.3, 4.2);
        path.close();
        for (final x in [7.2, 12.0, 16.8]) {
          canvas.drawCircle(Offset(x, 11.7), 1.25, Paint()..color = color);
        }
        break;
      case 'copyMessage':
        path.moveTo(9, 2.2);
        path.lineTo(19.4, 2.2);
        path.quadraticBezierTo(20.6, 2.2, 20.6, 3.4);
        path.lineTo(20.6, 16.3);
        path.addRRect(RRect.fromRectAndRadius(
          const Rect.fromLTRB(4.1, 6.7, 16, 20.8),
          const Radius.circular(1.25),
        ));
        break;
      case 'forwardMessage':
        path.moveTo(13.7, 4.2);
        path.lineTo(21.7, 11.8);
        path.lineTo(13.7, 19.6);
        path.lineTo(13.7, 14.7);
        path.cubicTo(8.8, 14.4, 4.2, 16.4, 2.6, 20.6);
        path.cubicTo(2.6, 12.8, 6.3, 8.8, 13.7, 8.8);
        path.close();
        break;
      case 'revoke':
        path.moveTo(6.2, 4.2);
        path.lineTo(2.6, 7.8);
        path.lineTo(6.2, 11.4);
        path.moveTo(3, 7.8);
        path.lineTo(14.3, 7.8);
        path.cubicTo(23.2, 7.8, 23.2, 19.4, 14.3, 19.4);
        path.lineTo(7.6, 19.4);
        break;
      case 'favorite_message':
      case 'add_to_stickers':
        path.moveTo(6.3, 3.8);
        path.lineTo(17.7, 3.8);
        path.quadraticBezierTo(18.8, 3.8, 18.8, 4.9);
        path.lineTo(18.8, 20.8);
        path.lineTo(12, 16.1);
        path.lineTo(5.2, 20.8);
        path.lineTo(5.2, 4.9);
        path.quadraticBezierTo(5.2, 3.8, 6.3, 3.8);
        path.close();
        break;
      case 'delete':
        path.moveTo(9, 2.2);
        path.lineTo(15, 2.2);
        path.moveTo(3.4, 6.1);
        path.lineTo(20.6, 6.1);
        path.moveTo(5.3, 6.5);
        path.lineTo(5.3, 19.7);
        path.quadraticBezierTo(5.3, 21.7, 7.3, 21.7);
        path.lineTo(16.7, 21.7);
        path.quadraticBezierTo(18.7, 21.7, 18.7, 19.7);
        path.lineTo(18.7, 6.5);
        path.moveTo(9.7, 11.3);
        path.lineTo(9.7, 16.8);
        path.moveTo(14.3, 11.3);
        path.lineTo(14.3, 16.8);
        break;
      case 'mergeForward':
        // Two incoming branches merge into one outgoing arrow.
        path.moveTo(3, 5);
        path.lineTo(6, 5);
        path.quadraticBezierTo(10, 5, 10, 9);
        path.lineTo(10, 15);
        path.quadraticBezierTo(10, 19, 6, 19);
        path.lineTo(3, 19);
        path.moveTo(10, 12);
        path.lineTo(21, 12);
        path.moveTo(17.5, 8.5);
        path.lineTo(21, 12);
        path.lineTo(17.5, 15.5);
        break;
      case 'voiceToText':
        path.addRRect(RRect.fromRectAndRadius(
          const Rect.fromLTRB(5.2, 2.8, 10.8, 12.5),
          const Radius.circular(2.8),
        ));
        path.moveTo(2.8, 10.3);
        path.lineTo(2.8, 11.5);
        path.cubicTo(2.8, 18, 13.2, 18, 13.2, 11.5);
        path.lineTo(13.2, 10.3);
        path.moveTo(8, 16.4);
        path.lineTo(8, 20.5);
        path.moveTo(5.2, 20.5);
        path.lineTo(10.8, 20.5);
        for (final y in [5.5, 11.5, 17.5]) {
          path.moveTo(17, y);
          path.lineTo(21, y);
        }
        break;
      case 'multiSelect':
        for (final y in [4.2, 12.0, 19.8]) {
          path.moveTo(2.3, y + .2);
          path.lineTo(3.7, y + 1.6);
          path.lineTo(6.4, y - 1.2);
          path.moveTo(10.6, y);
          path.lineTo(22, y);
        }
        break;
    }
    canvas.drawPath(path, pen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChatMessageMenuIconPainter oldDelegate) =>
      oldDelegate.action != action || oldDelegate.color != color;
}
