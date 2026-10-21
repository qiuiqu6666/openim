import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'group_personalization.dart';
import '../identity/group_name_label.dart';
import 'group_personalization_style.dart';

class GroupPersonalizationPreview extends StatelessWidget {
  const GroupPersonalizationPreview(
      {super.key,
      required this.name,
      this.avatarUrl,
      required this.appearance,
      required this.scale});
  final String name;
  final String? avatarUrl;
  final GroupPersonalization appearance;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final avatarSize = 168 * scale;
    final avatar = AvatarView(
        url: avatarUrl,
        text: name,
        isGroup: true,
        isCircle: true,
        width: avatarSize,
        height: avatarSize);
    return ClipRRect(
        borderRadius: BorderRadius.circular(28 * scale),
        child: CustomPaint(
            painter: _PreviewDecor(dark),
            child: Container(
                constraints: BoxConstraints(minHeight: 314 * scale),
                padding: EdgeInsets.symmetric(
                    horizontal: 46 * scale, vertical: 44 * scale),
                child: Row(children: [
                  Transform.translate(
                      offset: Offset(0, 32 * scale),
                      child: ClipOval(child: avatar)),
                  SizedBox(width: 44 * scale),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 20 * scale, vertical: 9 * scale),
                            decoration: BoxDecoration(
                                color: GroupPersonalizationStyle.blue
                                    .withValues(alpha: .07),
                                borderRadius:
                                    BorderRadius.circular(60 * scale)),
                            child: Text('效果预览',
                                style: TextStyle(
                                    color: GroupPersonalizationStyle.blue,
                                    fontSize: 25 * scale))),
                        SizedBox(height: 18 * scale),
                        GroupNameLabel(
                            name: name,
                            ex: appearance.mergeInto(null),
                            maxLines: largeText ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 46 * scale,
                                fontWeight: FontWeight.w700,
                                color: appearance.color == null
                                    ? (dark
                                        ? Colors.white
                                        : GroupPersonalizationStyle.ink)
                                    : Color(appearance.color!))),
                        SizedBox(height: 18 * scale),
                        Text('保存后，所有群成员都能看到群昵称颜色和图标。',
                            style: TextStyle(
                                fontSize: 25 * scale,
                                color: dark
                                    ? Colors.white70
                                    : const Color(0xFF596680),
                                height: 1.5)),
                      ])),
                ]))));
  }
}

class _PreviewDecor extends CustomPainter {
  const _PreviewDecor(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
                  colors: dark
                      ? [const Color(0xFF24354F), const Color(0xFF1C293C)]
                      : [
                          GroupPersonalizationStyle.previewStart,
                          const Color(0xFFF5F8FF),
                          GroupPersonalizationStyle.previewEnd
                        ])
              .createShader(rect));
    canvas.save();
    canvas.scale(size.width / 882, size.height / 314);
    void bubble(double x, double y, double r) {
      final circle = Rect.fromCircle(center: Offset(x, y), radius: r);
      canvas.drawCircle(
          Offset(x, y),
          r,
          Paint()
            ..shader = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: dark ? .05 : .45),
                  GroupPersonalizationStyle.blue.withValues(alpha: .03)
                ]).createShader(circle));
      canvas.drawArc(
          circle,
          3.2,
          2.5,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: dark ? .12 : .8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }

    bubble(92, 118, 69);
    bubble(614, 186, 101);
    bubble(800, 80, 109);
    bubble(720, 220, 68);
    bubble(790, 308, 59);
    canvas.save();
    canvas.translate(725, 49);
    canvas.rotate(.16);
    final speech = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 145, 120), const Radius.circular(30));
    canvas.drawRRect(
        speech,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: dark ? .1 : .7),
                const Color(0xFF80B2FF).withValues(alpha: .55)
              ]).createShader(speech.outerRect));
    canvas.drawRRect(
        speech,
        Paint()
          ..color = Colors.white.withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawPath(
        Path()
          ..moveTo(38, 118)
          ..lineTo(43, 146)
          ..quadraticBezierTo(46, 152, 52, 146)
          ..lineTo(73, 117)
          ..close(),
        Paint()..color = const Color(0xFFBDDAFF).withValues(alpha: .65));
    for (final x in [36.0, 71.0, 106.0]) {
      canvas.drawCircle(Offset(x, 64), 13,
          Paint()..color = Colors.white.withValues(alpha: .85));
    }
    canvas.restore();
    canvas.drawPath(
        Path()
          ..moveTo(207, 81)
          ..quadraticBezierTo(211, 100, 230, 104)
          ..quadraticBezierTo(211, 110, 207, 126)
          ..quadraticBezierTo(201, 109, 186, 104)
          ..quadraticBezierTo(202, 99, 207, 81),
        Paint()..color = const Color(0xFF68C9FA));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewDecor oldDelegate) => oldDelegate.dark != dark;
}
