import 'package:flutter/material.dart';
import '../res/styles.dart';

/// The icon language shared by conversation actions and primary navigation.
enum AppIconKind {
  singleChat,
  groupChat,
  contacts,
  profile,
  add,
  addFriend,
  addGroup,
  createGroup,
  pin,
  mute,
  alert,
}

class AppIconTokens {
  AppIconTokens._();

  static const double large = 24;
  static const double medium = 20;
  static const double small = 16;
  static const double status = 12;
  static const double androidTouchTarget = 48;

  static Color get primary => Styles.c_0C1C33;
  static Color get secondary => Styles.c_8E9AB0;
  static Color get selected => Styles.c_0089FF;
  static const Color danger = Color(0xFFE45454);
  static const Color onColor = Colors.white;
  static Color get disabled =>
      Styles.isDark ? const Color(0xFF718094) : const Color(0xFFB8C0CE);
}

/// Line icons on a common 24-unit canvas. State changes never switch to fill.
class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    required this.kind,
    this.size = AppIconTokens.large,
    this.color,
  });

  final AppIconKind kind;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _AppIconPainter(
              kind: kind, color: color ?? AppIconTokens.primary, size: size),
        ),
      );
}

class _AppIconPainter extends CustomPainter {
  const _AppIconPainter({
    required this.kind,
    required this.color,
    required this.size,
  });

  final AppIconKind kind;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas.save();
    canvas.scale(canvasSize.width / 24, canvasSize.height / 24);
    final opticalScale = size == AppIconTokens.small ? 1.35 : 1.0;
    if (opticalScale != 1) {
      canvas.translate(12, 12);
      canvas.scale(opticalScale);
      canvas.translate(-12, -12);
    }
    final stroke =
        (size <= AppIconTokens.small ? 1.5 : 1.8) * 24 / size / opticalScale;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    void path(Path path) => canvas.drawPath(path, paint);
    void circle(double x, double y, double radius) =>
        canvas.drawCircle(Offset(x, y), radius, paint);
    void rect(double l, double t, double r, double b, double radius) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(l, t, r, b), Radius.circular(radius)),
          paint,
        );

    switch (kind) {
      case AppIconKind.singleChat:
        path(Path()
          ..moveTo(5.5, 5)
          ..lineTo(18.5, 5)
          ..quadraticBezierTo(20, 5, 20, 6.5)
          ..lineTo(20, 15.5)
          ..quadraticBezierTo(20, 17, 18.5, 17)
          ..lineTo(10.5, 17)
          ..lineTo(5, 20)
          ..lineTo(5, 17)
          ..quadraticBezierTo(4, 16.5, 4, 15.5)
          ..lineTo(4, 6.5)
          ..quadraticBezierTo(4, 5, 5.5, 5)
          ..close());
      case AppIconKind.groupChat:
        rect(6.5, 4, 20, 15, 2);
        path(Path()
          ..moveTo(16.5, 15)
          ..lineTo(18.5, 17.5)
          ..lineTo(18.5, 15));
        path(Path()
          ..moveTo(5.5, 8)
          ..quadraticBezierTo(4, 8, 4, 9.5)
          ..lineTo(4, 17)
          ..quadraticBezierTo(4, 18.5, 5.5, 18.5)
          ..lineTo(8, 18.5)
          ..lineTo(8, 21)
          ..lineTo(11, 18.5)
          ..lineTo(15, 18.5));
      case AppIconKind.contacts:
        rect(5, 4, 19, 20, 2);
        circle(12, 9.5, 2);
        line(9, 15, 15, 15);
        line(3, 8, 5, 8);
        line(3, 16, 5, 16);
      case AppIconKind.profile:
        circle(12, 8, 3.3);
        path(Path()
          ..moveTo(5, 20)
          ..lineTo(5, 18.5)
          ..cubicTo(5, 14, 19, 14, 19, 18.5)
          ..lineTo(19, 20));
      case AppIconKind.add:
        circle(12, 12, 8.5);
        line(12, 8, 12, 16);
        line(8, 12, 16, 12);
      case AppIconKind.addFriend:
        circle(10, 8, 2.7);
        path(Path()
          ..moveTo(4.5, 18)
          ..cubicTo(4.5, 13.5, 15.5, 13.5, 15.5, 18));
        line(18.5, 7, 18.5, 13);
        line(15.5, 10, 21.5, 10);
      case AppIconKind.addGroup:
        circle(8.5, 8, 2.4);
        circle(15, 8.5, 2.1);
        path(Path()
          ..moveTo(3.5, 18)
          ..cubicTo(3.5, 14, 13, 14, 13, 18));
        path(Path()
          ..moveTo(14, 14.5)
          ..quadraticBezierTo(17.5, 14, 18, 17));
        line(19, 18, 19, 22);
        line(17, 20, 21, 20);
      case AppIconKind.createGroup:
        rect(4, 5, 17, 15, 2);
        path(Path()
          ..moveTo(7, 15)
          ..lineTo(7, 18)
          ..lineTo(10, 15));
        line(19, 16, 19, 22);
        line(16, 19, 22, 19);
      case AppIconKind.pin:
        path(Path()
          ..moveTo(8, 4.5)
          ..lineTo(16, 4.5)
          ..lineTo(15, 9)
          ..lineTo(18, 12)
          ..lineTo(18, 14)
          ..lineTo(6, 14)
          ..lineTo(6, 12)
          ..lineTo(9, 9)
          ..close());
        line(12, 14, 12, 20);
      case AppIconKind.mute:
        path(Path()
          ..moveTo(6, 16.5)
          ..lineTo(7.5, 14.5)
          ..lineTo(7.5, 10)
          ..cubicTo(7.5, 4, 16.5, 4, 16.5, 10)
          ..lineTo(16.5, 14.5)
          ..lineTo(18, 16.5)
          ..close());
        line(10.5, 19, 13.5, 19);
        line(4.5, 19.5, 19.5, 4.5);
      case AppIconKind.alert:
        circle(12, 12, 8.5);
        line(12, 7.5, 12, 13);
        circle(12, 16.5, .2);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AppIconPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.size != size;
}
