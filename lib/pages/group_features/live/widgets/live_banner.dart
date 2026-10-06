import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../models/live_models.dart';
import 'live_style.dart';

class GroupLiveBanner extends StatelessWidget {
  const GroupLiveBanner(
      {super.key,
      required this.session,
      required this.onWatch,
      this.anchorFaceURL = ''});
  final LiveSession session;
  final VoidCallback onWatch;
  final String anchorFaceURL;
  @override
  Widget build(BuildContext context) => Material(
      color: LiveStyle.dark(context)
          ? AppTokens.surfaceAltDark
          : LiveStyle.card(context),
      child: InkWell(
          onTap: onWatch,
          child: SizedBox(
              height: LiveStyle.bannerHeight,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final compact = constraints.maxWidth < 400;
                    final gap = compact ? 4.0 : 8.0;
                    return Row(children: [
                      SizedBox(
                          width: compact ? constraints.maxWidth * .13 : 72,
                          height: LiveStyle.bannerHeight,
                          child: OverflowBox(
                              minHeight: 0,
                              maxHeight:
                                  compact ? constraints.maxWidth * .13 : 72,
                              child: Image.asset(LiveStyle.bannerAsset,
                                  width:
                                      compact ? constraints.maxWidth * .13 : 72,
                                  height:
                                      compact ? constraints.maxWidth * .13 : 72,
                                  fit: BoxFit.contain))),
                      SizedBox(width: gap),
                      Expanded(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            SizedBox(
                                width: double.infinity,
                                height: 24,
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        session.roomName.isEmpty
                                            ? '群直播'
                                            : session.roomName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 16,
                                            height: 1.2,
                                            fontWeight: FontWeight.w600,
                                            color: LiveStyle.dark(context)
                                                ? LiveStyle.text(context)
                                                : const Color(0xFF1F2329))))),
                            if (session.description.isNotEmpty)
                              const SizedBox(height: 2),
                            if (session.description.isNotEmpty)
                              Text(session.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      height: 1.2,
                                      color: LiveStyle.dark(context)
                                          ? LiveStyle.secondary(context)
                                          : const Color(0xFF8A8F99))),
                          ])),
                      SizedBox(width: gap),
                      SizedBox(
                          width: compact ? constraints.maxWidth * .09 : 40,
                          height: 40,
                          child: FittedBox(
                              child: SizedBox.square(
                                  dimension: 40,
                                  child: Stack(children: [
                                    Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: const Color(0xFFFFD6E4),
                                                width: 1.5)),
                                        child: ClipOval(
                                            child: AvatarView(
                                                width: 37,
                                                height: 37,
                                                url: anchorFaceURL,
                                                text: session.anchorID))),
                                    Positioned(
                                        right: 0,
                                        bottom: 2,
                                        child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Color(0xFFFF6B9D),
                                                      Color(0xFFFFB35C)
                                                    ]),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 1.5))))
                                  ])))),
                      SizedBox(width: gap),
                      SizedBox(
                          width: compact ? constraints.maxWidth * .25 : 110,
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: const _EnterLiveButton())),
                    ]);
                  })))));
}

class _EnterLiveButton extends StatelessWidget {
  const _EnterLiveButton();
  @override
  Widget build(BuildContext context) => Container(
      height: 32,
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFF9A2F), Color(0xFFFF6358), Color(0xFFFF3F78)],
              stops: [0, .48, 1]),
          borderRadius: BorderRadius.all(Radius.circular(16)),
          boxShadow: [
            BoxShadow(
                color: Color(0x40FF6358), blurRadius: 14, offset: Offset(0, 5))
          ]),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Text('进入直播间',
            style: TextStyle(
                color: AppTokens.onAccent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.05)),
        SizedBox(width: 3),
        CustomPaint(size: Size(7, 11), painter: _EnterChevronPainter())
      ]));
}

class _EnterChevronPainter extends CustomPainter {
  const _EnterChevronPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
        Path()
          ..moveTo(1.2, 1.2)
          ..lineTo(size.width - 1.2, size.height / 2)
          ..lineTo(1.2, size.height - 1.2),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GroupLiveBadge extends StatelessWidget {
  const GroupLiveBadge({super.key, required this.status});
  final LiveStatus status;
  @override
  Widget build(BuildContext context) => status.active
      ? MediaQuery.withNoTextScaling(
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: switch (status) {
                    LiveStatus.live => LiveStyle.red,
                    LiveStatus.authorized => LiveStyle.waiting,
                    _ => LiveStyle.blue
                  },
                  borderRadius: BorderRadius.circular(999)),
              child: Text(status.label,
                  style: const TextStyle(
                      color: AppTokens.onAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      height: 1.1))))
      : const SizedBox.shrink();
}
