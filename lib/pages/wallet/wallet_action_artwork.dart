import 'package:flutter/material.dart';

/// Shared visual treatment for the four primary Wallet actions.
///
/// The tile intentionally keeps typography at fixed readable sizes instead of
/// scaling text down with the card height. This preserves clarity on compact
/// phones while keeping all four actions on one row.
class WalletActionTile extends StatelessWidget {
  const WalletActionTile({
    required this.action,
    required this.title,
    required this.subtitle,
    required this.textColor,
    this.dark = false,
    this.divider = true,
    super.key,
  });

  static const double iconSize = 44;
  static const double titleFontSize = 14;
  static const double subtitleFontSize = 11;

  final String action;
  final String title;
  final String subtitle;
  final Color textColor;
  final bool dark;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final secondaryText = dark
        ? const Color(0xFFB3BAC8)
        : const Color(0xFF918A82);
    final dividerColor = dark
        ? const Color(0xFF343744).withValues(alpha: 0.72)
        : const Color(0xFFEEE8DF).withValues(alpha: 0.92);

    return Stack(
      children: [
        if (divider)
          Positioned(
            right: 0,
            top: 18,
            bottom: 18,
            child: Container(width: 0.7, color: dividerColor),
          ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: iconSize,
                  child: WalletActionArtwork(action: action, dark: dark),
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    height: 1.15,
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: subtitleFontSize,
                    height: 1.15,
                    color: secondaryText,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.05,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class WalletActionArtwork extends StatelessWidget {
  const WalletActionArtwork({
    required this.action,
    this.dark = false,
    super.key,
  });

  static const Color actionAccent = Color(0xFF9A7042);
  static const Color actionAccentStrong = Color(0xFF7E5732);
  static const Color actionSurface = Color(0xFFF7F2EA);
  static const Color actionSurfaceDark = Color(0xFF2A2723);
  static const Color actionBorder = Color(0xFFEBE3D8);
  static const Color actionBorderDark = Color(0xFF433B32);

  final String action;
  final bool dark;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _WalletActionPainter(action, dark));
}

class _WalletActionPainter extends CustomPainter {
  const _WalletActionPainter(this.action, this.dark);
  final String action;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    const rect = Rect.fromLTWH(0, 0, 64, 64);
    final surface = dark
        ? WalletActionArtwork.actionSurfaceDark
        : WalletActionArtwork.actionSurface;
    final border = dark
        ? WalletActionArtwork.actionBorderDark
        : WalletActionArtwork.actionBorder;
    final accent = dark
        ? const Color(0xFFD6B27A)
        : WalletActionArtwork.actionAccent;
    final accentStrong = dark
        ? const Color(0xFFB68A55)
        : WalletActionArtwork.actionAccentStrong;

    final tile = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    canvas.drawRRect(tile, Paint()..color = surface);
    canvas.drawRRect(
      tile.deflate(.5),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    canvas.drawCircle(
      const Offset(31, 31),
      22,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: dark ? .05 : .44),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(const Rect.fromLTWH(9, 9, 44, 44)),
    );
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accentStrong],
      ).createShader(const Rect.fromLTWH(12, 12, 40, 40));
    final line = Paint()
      ..shader = fill.shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
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
        line,
      );
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
        Paint()..color = accentStrong.withValues(alpha: .62),
      );
      final ink = Paint()
        ..color = Colors.white.withValues(alpha: .92)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final y in [26.0, 32.0, 38.0]) {
        canvas.drawLine(Offset(23, y), Offset(y == 38 ? 33 : 40, y), ink);
      }
      canvas.drawCircle(
        const Offset(46, 44),
        10.2,
        Paint()
          ..color = dark
              ? const Color(0xFF27364A)
              : const Color(0xFFEAF1FB),
      );
      canvas.drawCircle(const Offset(46, 44), 8.5, fill);
      canvas.drawPath(
        Path()
          ..moveTo(46, 40)
          ..lineTo(46, 44)
          ..lineTo(49, 46),
        ink..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WalletActionPainter oldDelegate) =>
      oldDelegate.action != action || oldDelegate.dark != dark;
}
