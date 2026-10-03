import 'package:flutter/material.dart';

class WalletActionTile extends StatelessWidget {
  const WalletActionTile(
      {required this.action,
      required this.title,
      required this.subtitle,
      required this.textColor,
      this.dark = false,
      this.divider = true,
      super.key});
  final String action;
  final String title;
  final String subtitle;
  final Color textColor;
  final bool dark;
  final bool divider;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = (constraints.maxHeight / 108).clamp(0.8, 1.6);
        return Stack(children: [
          if (divider)
            Positioned(
                right: 0,
                top: 24 * scale,
                bottom: 22 * scale,
                child: Container(
                    width: 0.7,
                    color: dark
                        ? const Color(0xFF343744)
                        : const Color(0xFFE9EDF7))),
          Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox.square(
                dimension: 43 * scale,
                child: WalletActionArtwork(action: action)),
            SizedBox(height: 7 * scale),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 12 * scale,
                            height: 1.2,
                            color: textColor,
                            fontWeight: FontWeight.w600)))),
            SizedBox(height: 4 * scale),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(subtitle,
                        style: TextStyle(
                            fontSize: 9.5 * scale,
                            height: 1.2,
                            color: dark
                                ? const Color(0xFFA2A9BD)
                                : const Color(0xFF979FB2))))),
          ])),
        ]);
      });
}

class WalletActionArtwork extends StatelessWidget {
  const WalletActionArtwork({required this.action, super.key});
  final String action;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _WalletActionPainter(action));
}

class _WalletActionPainter extends CustomPainter {
  const _WalletActionPainter(this.action);
  final String action;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final colors = switch (action) {
      'receive' => [const Color(0xFF60EBC4), const Color(0xFF00C489)],
      'transfer' => [const Color(0xFFFF9A8C), const Color(0xFFFF343D)],
      'swap' => [const Color(0xFF5DCEFF), const Color(0xFF007DFF)],
      _ => [const Color(0xFFA780FF), const Color(0xFF7537FA)],
    };
    const rect = Rect.fromLTWH(0, 0, 64, 64);
    final background = Paint()
      ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Colors.white, colors.first, .09)!,
            Color.lerp(Colors.white, colors.last, .14)!,
            Color.lerp(Colors.white, colors.first, .12)!
          ]).createShader(rect);
    final tile = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    canvas.drawRRect(tile, background);
    canvas.drawRRect(
        tile.deflate(.4),
        Paint()
          ..color = colors.first.withValues(alpha: .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6);
    canvas.drawCircle(
        const Offset(31, 32),
        23,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: .5),
            Colors.white.withValues(alpha: 0)
          ]).createShader(const Rect.fromLTWH(8, 9, 46, 46)));
    final fill = Paint()
      ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors)
          .createShader(const Rect.fromLTWH(12, 12, 40, 40));
    final line = Paint()
      ..shader = fill.shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (action == 'receive' || action == 'transfer') {
      canvas.drawPath(
          Path()
            ..moveTo(16, 37)
            ..lineTo(16, 46)
            ..quadraticBezierTo(16, 48, 18, 48)
            ..lineTo(46, 48)
            ..quadraticBezierTo(48, 48, 48, 46)
            ..lineTo(48, 37),
          line);
      final arrow = Path()
        ..moveTo(29, 12)
        ..lineTo(35, 12)
        ..quadraticBezierTo(37, 12, 37, 14)
        ..lineTo(37, 26)
        ..lineTo(42, 26)
        ..quadraticBezierTo(45, 26, 43, 28)
        ..lineTo(34, 38)
        ..quadraticBezierTo(32, 40, 30, 38)
        ..lineTo(21, 28)
        ..quadraticBezierTo(19, 26, 22, 26)
        ..lineTo(27, 26)
        ..lineTo(27, 14)
        ..quadraticBezierTo(27, 12, 29, 12)
        ..close();
      if (action == 'transfer') {
        canvas.save();
        canvas.translate(0, 51);
        canvas.scale(1, -1);
        canvas.drawPath(arrow, fill);
        canvas.restore();
      } else {
        canvas.drawPath(arrow, fill);
      }
    } else if (action == 'swap') {
      final arrow = Path()
        ..moveTo(14, 25)
        ..lineTo(23, 16)
        ..quadraticBezierTo(27, 12, 27, 18)
        ..lineTo(27, 21)
        ..lineTo(44, 21)
        ..quadraticBezierTo(46, 21, 47, 23)
        ..lineTo(49, 25)
        ..quadraticBezierTo(51, 29, 46, 29)
        ..lineTo(17, 29)
        ..quadraticBezierTo(12, 29, 14, 25)
        ..close();
      canvas.drawPath(arrow, fill);
      canvas.save();
      canvas.translate(64, 64);
      canvas.rotate(3.141592653589793);
      canvas.drawPath(arrow, fill);
      canvas.restore();
    } else {
      final doc = Path()
        ..moveTo(21, 12)
        ..lineTo(38, 12)
        ..lineTo(46, 20)
        ..lineTo(46, 46)
        ..quadraticBezierTo(46, 50, 42, 50)
        ..lineTo(21, 50)
        ..quadraticBezierTo(17, 50, 17, 46)
        ..lineTo(17, 16)
        ..quadraticBezierTo(17, 12, 21, 12)
        ..close();
      canvas.drawPath(doc, fill);
      canvas.drawPath(
          Path()
            ..moveTo(38, 12)
            ..lineTo(38, 17)
            ..quadraticBezierTo(38, 20, 41, 20)
            ..lineTo(46, 20)
            ..close(),
          Paint()..color = colors.last.withValues(alpha: .6));
      final ink = Paint()
        ..color = Colors.white.withValues(alpha: .92)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final y in [26.0, 32.0, 38.0]) {
        canvas.drawLine(Offset(23, y), Offset(y == 38 ? 33 : 40, y), ink);
      }
      canvas.drawCircle(
          const Offset(46, 44), 10.2, Paint()..color = const Color(0xFFF3EDFF));
      canvas.drawCircle(const Offset(46, 44), 8.5, fill);
      canvas.drawPath(
          Path()
            ..moveTo(46, 40)
            ..lineTo(46, 44)
            ..lineTo(49, 46),
          ink..style = PaintingStyle.stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WalletActionPainter oldDelegate) =>
      oldDelegate.action != action;
}
