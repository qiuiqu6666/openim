import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/widgets/settings_widgets.dart';
import 'fund_page_colors.dart';

// Presentation adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
// Source: red_packet_open_flow_page.dart and lucky_red_packet_detail_page.dart.
class FundReferenceCover extends StatelessWidget {
  const FundReferenceCover(
      {super.key,
      required this.type,
      required this.greeting,
      required this.status,
      required this.error,
      required this.opening,
      required this.splitting,
      required this.spin,
      required this.split,
      required this.onOpen});
  final String type, greeting, status;
  final String? error;
  final bool opening, splitting;
  final Animation<double> spin, split;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, card) {
        final buttonSize = card.maxWidth * FundTokens.previewCoinSizeRatio;
        final buttonBottom = card.maxHeight * FundTokens.previewCoinBottomRatio;
        final content = Stack(fit: StackFit.expand, children: [
          Image.asset('assets/img/red_packet_preview_cover_v2.png',
              key: const ValueKey('fund-reference-cover-art'),
              fit: BoxFit.cover),
          Positioned(
            left: card.maxWidth * .07,
            right: card.maxWidth * .07,
            top: card.maxHeight * FundTokens.previewTypeTopRatio,
            child: Column(children: [
              SizedBox(
                  height: card.maxHeight * .05,
                  child: Center(
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(type,
                              style: TextStyle(
                                  color: FundTokens.previewGold,
                                  fontSize: card.maxWidth *
                                      FundTokens.previewTypeFontRatio,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5))))),
              SizedBox(height: card.maxHeight * .026),
              SizedBox(
                  height: card.maxHeight * .065,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(greeting,
                          maxLines: 1,
                          style: TextStyle(
                              color: FundTokens.previewGold,
                              fontSize: card.maxWidth *
                                  FundTokens.previewGreetingFontRatio,
                              fontWeight: FontWeight.w700,
                              shadows: const [
                                Shadow(
                                    color: FundTokens.previewTextShadow,
                                    blurRadius: 3,
                                    offset: Offset(0, 2))
                              ])))),
              SizedBox(height: card.maxHeight * .008),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('—  万 事 如 意 · 财 源 广 进  —',
                      style: TextStyle(
                          color: FundTokens.previewGold,
                          fontSize: card.maxWidth *
                              FundTokens.previewBlessingFontRatio))),
            ]),
          ),
          if (error != null || status.isNotEmpty)
            Positioned(
                left: AppTokens.s4,
                right: AppTokens.s4,
                bottom: buttonBottom + buttonSize + AppTokens.s3,
                child: Column(children: [
                  Semantics(
                      liveRegion: true,
                      child: Text(status,
                          key: const ValueKey('fund-detail-status'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: FundTokens.previewError,
                              fontSize: AppTokens.captionFontSize))),
                  if (error != null)
                    Text(error!,
                        key: const ValueKey('fund-detail-claim-error'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: FundTokens.previewError,
                            fontSize: AppTokens.captionFontSize)),
                ])),
          Positioned(
              left: 0,
              right: 0,
              bottom: buttonBottom,
              child: Center(
                  child: _FundReferenceCoin(
                      size: buttonSize,
                      controller: spin,
                      opening: opening,
                      opened: splitting,
                      onOpen: onOpen))),
        ]);
        final progress = split.drive(CurveTween(curve: Curves.easeInCubic));
        final opacity = progress.drive(Tween<double>(begin: 1, end: .82));
        return ClipRRect(
          borderRadius: BorderRadius.circular(
              card.maxWidth * FundTokens.previewRadiusRatio),
          child: AnimatedBuilder(
              animation: split,
              // Keep one intact, interactive cover until the split starts.
              // The split subtree and both cover copies are reused each frame.
              builder: (context, child) => split.value <= 0 ? content : child!,
              child: Stack(fit: StackFit.expand, children: [
                for (final top in [true, false])
                  FadeTransition(
                      opacity: opacity,
                      child: SlideTransition(
                          position: progress.drive(Tween<Offset>(
                            begin: Offset.zero,
                            end: Offset(0, top ? -1.08 : 1.08),
                          )),
                          child: ClipRect(
                              child: ClipPath(
                                  clipper: _FundSplitClipper(top: top),
                                  child: SizedBox(
                                      width: card.maxWidth,
                                      height: card.maxHeight,
                                      child: content))))),
              ])),
        );
      });
}

class _FundSplitClipper extends CustomClipper<Path> {
  const _FundSplitClipper({required this.top});
  final bool top;
  @override
  Path getClip(Size size) => top
      ? (Path()
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height * .55)
        ..quadraticBezierTo(
            size.width * .5, size.height * .43, 0, size.height * .55)
        ..close())
      : (Path()
        ..moveTo(0, size.height * .55)
        ..quadraticBezierTo(
            size.width * .5, size.height * .43, size.width, size.height * .55)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close());
  @override
  bool shouldReclip(covariant _FundSplitClipper oldClipper) =>
      oldClipper.top != top;
}

class _FundReferenceCoin extends StatelessWidget {
  const _FundReferenceCoin(
      {required this.size,
      required this.controller,
      required this.opening,
      required this.opened,
      required this.onOpen});
  final double size;
  final Animation<double> controller;
  final bool opening, opened;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
        key: const ValueKey('fund-detail-claim'),
        button: true,
        enabled: !opening && !opened && onOpen != null,
        label: settingsText(context, zh: '打开红包', en: 'Open red packet'),
        child: MatrixTransition(
          key: const ValueKey('fund-detail-open-animation'),
          animation: controller,
          onTransform: (value) {
            final eased = Curves.easeInOutCubic.transform(value);
            final turns = opening ? eased * math.pi * 3 : 0.0;
            final pulse = opening ? math.sin(value * math.pi) * .035 : 0.0;
            return Matrix4.identity()
              ..setEntry(3, 2, .0012)
              ..rotateY(turns)
              ..scaleByDouble(1 + pulse, 1 + pulse, 1, 1);
          },
          child: SizedBox.square(
              dimension: size,
              child: Material(
                color: FundTokens.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const ValueKey('fund-detail-open'),
                  customBorder: const CircleBorder(),
                  onTap: opening || opened ? null : onOpen,
                  child: Ink(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: !opening && !opened
                              ? Border.all(
                                  color: FundTokens.coinBorder,
                                  width: size * .025)
                              : null,
                          gradient: const RadialGradient(
                              center: Alignment(-.35, -.35),
                              radius: .95,
                              colors: [
                                FundTokens.coinGradientTop,
                                FundTokens.coinGradientMiddle,
                                FundTokens.coinGradientBottom
                              ]),
                          boxShadow: [
                            BoxShadow(
                                color: FundTokens.coinShadow,
                                blurRadius:
                                    size * (opening || opened ? .13 : .075),
                                offset: Offset(0,
                                    size * (opening || opened ? .045 : .035)))
                          ]),
                      child: Center(
                          child: opening || opened
                              ? CustomPaint(
                                  size: Size.square(size * .72),
                                  painter: const _FundCoinHolePainter())
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                      settingsText(context,
                                          zh: '開', en: 'Open'),
                                      style: TextStyle(
                                          color: FundTokens.coinLabel,
                                          fontSize: size * .46,
                                          fontWeight: FontWeight.w700,
                                          height: 1))))),
                ),
              )),
        ),
      );
}

class _FundCoinHolePainter extends CustomPainter {
  const _FundCoinHolePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final holeSize = size.shortestSide * .34;
    final hole = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: size.center(Offset.zero),
            width: holeSize,
            height: holeSize),
        Radius.circular(size.shortestSide * .04));
    canvas.drawRRect(
        hole.shift(Offset(0, size.shortestSide * .025)),
        Paint()
          ..color = FundTokens.coinHoleShadow
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, size.shortestSide * .03));
    canvas.drawRRect(hole, Paint()..color = FundTokens.coinHole);
  }

  @override
  bool shouldRepaint(covariant _FundCoinHolePainter oldDelegate) => false;
}

class FundLuckyHeaderPainter extends CustomPainter {
  const FundLuckyHeaderPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const depth = FundTokens.detailHeaderCurveHeight;
    final path = Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - depth)
      ..quadraticBezierTo(
          size.width / 2, size.height + depth, 0, size.height - depth)
      ..close();
    canvas.drawPath(path, Paint()..color = FundTokens.luckyHeader);
    final edge = Path()
      ..moveTo(size.width, size.height - depth)
      ..quadraticBezierTo(
          size.width / 2, size.height + depth, 0, size.height - depth);
    canvas.drawPath(
        edge,
        Paint()
          ..color = FundTokens.goldEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = FundTokens.spinnerStroke
          ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(covariant FundLuckyHeaderPainter oldDelegate) => false;
}

/// Funds details use the server order. A message is only an order reference.
/// Pure overlay presentation; the owning page verifies and claims the order.
class FundPacketCoverOverlay extends StatelessWidget {
  const FundPacketCoverOverlay(
      {super.key,
      required this.cover,
      required this.split,
      required this.splitting,
      required this.loadingIndicator,
      required this.onClose,
      required this.onViewDetails,
      required this.viewDetailsLabel,
      required this.closeLabel});
  final Widget cover, loadingIndicator;
  final Animation<double> split;
  final bool splitting;
  final VoidCallback onClose;
  final VoidCallback? onViewDetails;
  final String viewDetailsLabel, closeLabel;
  @override
  Widget build(BuildContext context) {
    final cs = FundPageColors.of(context);
    return BlockSemantics(
        child: Scaffold(
      backgroundColor: FundTokens.transparent,
      body: SafeArea(
          child: Stack(children: [
        if (splitting)
          Positioned.fill(
              child: ColoredBox(
                  color: cs.card, child: Center(child: loadingIndicator))),
        Positioned.fill(
          child: FadeTransition(
              opacity: split
                  .drive(CurveTween(curve: Curves.easeInCubic))
                  .drive(Tween<double>(begin: 1, end: 0)),
              child: BackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: FundTokens.previewBlurSigma,
                      sigmaY: FundTokens.previewBlurSigma),
                  child: ColoredBox(
                      key: const ValueKey('fund-detail-scrim'),
                      color: FundTokens.referenceMask
                          .withValues(alpha: FundTokens.previewMaskOpacity)))),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: LayoutBuilder(builder: (context, viewport) {
            final shortest = math.min(viewport.maxWidth, viewport.maxHeight);
            final horizontal = shortest * FundTokens.previewSidePaddingRatio;
            final widthFactor =
                viewport.maxWidth > FundTokens.referenceDesktopWidth
                    ? FundTokens.previewDesktopWidthRatio
                    : FundTokens.previewMobileWidthRatio;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  horizontal,
                  viewport.maxHeight * FundTokens.previewTopGapRatio,
                  horizontal,
                  viewport.maxHeight * FundTokens.previewBottomGapRatio),
              child: Column(children: [
                Expanded(child: LayoutBuilder(builder: (context, body) {
                  final closeSize =
                      (shortest * FundTokens.previewCloseSizeRatio)
                          .clamp(FundTokens.previewCloseSizeMin,
                              FundTokens.previewCloseSizeMax)
                          .toDouble();
                  final gap = shortest * FundTokens.previewCloseGapRatio;
                  final detailHeight =
                      SettingsResponsive.controlHeight(context);
                  final maxByWidth = body.maxWidth * widthFactor;
                  final maxByHeight = math.max(
                      0.0,
                      (body.maxHeight - gap - closeSize - detailHeight) *
                          FundTokens.previewAspectRatio);
                  final width = math.min(maxByWidth, maxByHeight);
                  return Center(
                      child: SizedBox(
                          width: width,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {},
                                child: AspectRatio(
                                    key: const ValueKey('fund-packet-cover'),
                                    aspectRatio: FundTokens.previewAspectRatio,
                                    child: cover)),
                            SizedBox(
                                height: detailHeight,
                                child: TextButton(
                                    key: const ValueKey(
                                        'fund-detail-view-details'),
                                    style: TextButton.styleFrom(
                                        foregroundColor: AppTokens.onAccent),
                                    onPressed: onViewDetails,
                                    child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(viewDetailsLabel)))),
                            SizedBox(height: gap),
                            GestureDetector(
                                key: const ValueKey('fund-detail-close'),
                                behavior: HitTestBehavior.opaque,
                                onTap: onClose,
                                child: Semantics(
                                    button: true,
                                    label: closeLabel,
                                    child: Container(
                                        width: closeSize,
                                        height: closeSize,
                                        decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: AppTokens.onAccent
                                                    .withValues(alpha: .85),
                                                width: closeSize * .022)),
                                        alignment: Alignment.center,
                                        child: Text('×',
                                            style: TextStyle(
                                                color: AppTokens.onAccent
                                                    .withValues(alpha: .85),
                                                fontSize: closeSize * .62,
                                                height: .95,
                                                fontWeight:
                                                    FontWeight.w300))))),
                          ])));
                }))
              ]),
            );
          }),
        ),
      ])),
    ));
  }
}
