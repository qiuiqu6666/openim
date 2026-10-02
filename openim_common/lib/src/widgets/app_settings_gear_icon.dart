import 'package:flutter/material.dart';

/// Settings gear artwork ported from 99chat's main-tab header.
///
/// The filled six-tooth silhouette, transparent annulus and solid center are
/// intentionally kept as vector geometry so the header action stays identical
/// across Flutter SDK versions and display densities.
class AppSettingsGearIcon extends StatelessWidget {
  const AppSettingsGearIcon({
    super.key,
    this.size = 24,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _SettingsGearIconPainter(color),
      );
}

class _SettingsGearIconPainter extends CustomPainter {
  const _SettingsGearIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 600, size.height / 600);
    canvas.translate(-325, -310);
    final silhouette = Path()
      ..moveTo(583, 326)
      ..lineTo(667, 326)
      ..cubicTo(688, 326, 698, 340, 701, 359)
      ..lineTo(707, 398)
      ..cubicTo(709, 413, 719, 420, 747, 435)
      ..cubicTo(760, 443, 767, 442, 780, 437)
      ..lineTo(814, 423)
      ..cubicTo(832, 415, 845, 423, 855, 439)
      ..lineTo(895, 508)
      ..cubicTo(905, 525, 901, 539, 886, 552)
      ..lineTo(856, 576)
      ..cubicTo(846, 584, 843, 590, 843, 604)
      ..lineTo(843, 629)
      ..cubicTo(843, 642, 848, 649, 858, 657)
      ..lineTo(886, 678)
      ..cubicTo(902, 691, 904, 705, 895, 722)
      ..lineTo(855, 790)
      ..cubicTo(844, 808, 829, 809, 812, 801)
      ..lineTo(779, 787)
      ..cubicTo(766, 781, 758, 782, 746, 789)
      ..lineTo(722, 804)
      ..cubicTo(710, 811, 706, 818, 704, 833)
      ..lineTo(699, 868)
      ..cubicTo(696, 886, 684, 897, 664, 897)
      ..lineTo(584, 897)
      ..cubicTo(563, 897, 552, 885, 549, 868)
      ..lineTo(543, 831)
      ..cubicTo(542, 817, 536, 810, 524, 803)
      ..lineTo(499, 787)
      ..cubicTo(490, 780, 483, 779, 471, 785)
      ..lineTo(438, 800)
      ..cubicTo(420, 809, 406, 806, 395, 789)
      ..lineTo(355, 722)
      ..cubicTo(344, 704, 345, 690, 361, 677)
      ..lineTo(392, 654)
      ..cubicTo(402, 647, 405, 638, 405, 625)
      ..lineTo(405, 604)
      ..cubicTo(405, 590, 402, 582, 392, 574)
      ..lineTo(363, 550)
      ..cubicTo(349, 538, 346, 525, 355, 509)
      ..lineTo(398, 438)
      ..cubicTo(408, 421, 420, 415, 439, 424)
      ..lineTo(473, 438)
      ..cubicTo(486, 443, 494, 439, 505, 433)
      ..lineTo(528, 419)
      ..cubicTo(540, 412, 543, 403, 545, 390)
      ..lineTo(550, 358)
      ..cubicTo(553, 339, 565, 326, 583, 326)
      ..close()
      ..fillType = PathFillType.evenOdd
      ..addOval(
        Rect.fromCircle(
          center: const Offset(623, 618),
          radius: 140,
        ),
      );
    final paint = Paint()..color = color;
    canvas.drawPath(silhouette, paint);
    canvas.drawCircle(const Offset(622, 620), 85.5, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SettingsGearIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
