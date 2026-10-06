import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'fund_card_metrics.dart';
import 'fund_card_palette.dart';
import 'fund_card_recipient.dart';
import 'fund_packet_summary.dart';

// The reference 99chat transfer card's original vector artwork.
const String _transferArrowIconSvg = '''
<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <path d="M512 993.28C245.76 993.28 30.72 778.24 30.72 512S245.76 30.72 512 30.72s481.28 215.04 481.28 481.28-215.04 481.28-481.28 481.28z m0-880.64c-220.16 0-399.36 179.2-399.36 399.36s179.2 399.36 399.36 399.36 399.36-179.2 399.36-399.36-179.2-399.36-399.36-399.36z"></path>
  <path d="M281.6 491.52h450.56c5.12 0 10.24 0 15.36-5.12 10.24-5.12 15.36-10.24 20.48-20.48 5.12-10.24 5.12-20.48 0-30.72 0-5.12-5.12-10.24-10.24-15.36l-148.48-148.48c-15.36-15.36-40.96-15.36-56.32 0s-15.36 40.96 0 56.32L634.88 409.6H281.6c-20.48 0-40.96 20.48-40.96 40.96s20.48 40.96 40.96 40.96zM742.4 532.48H291.84c-5.12 0-10.24 0-15.36 5.12-10.24 5.12-15.36 10.24-20.48 20.48-5.12 10.24-5.12 20.48 0 30.72 0 5.12 5.12 10.24 10.24 15.36l148.48 148.48c10.24 10.24 20.48 10.24 30.72 10.24 10.24 0 20.48-5.12 30.72-10.24 15.36-15.36 15.36-40.96 0-56.32L389.12 614.4h353.28c20.48 0 40.96-20.48 40.96-40.96s-20.48-40.96-40.96-40.96z"></path>
</svg>
''';

/// 99chat red_packet_card.dart / transfer_card.dart visual structure, backed
/// by the current server's order snapshot. The parent owns the detail action.
class FundMessageCard extends StatelessWidget {
  const FundMessageCard({
    super.key,
    required this.message,
    this.isGroupChat = false,
    this.claimedByMe = false,
    this.isOutgoing = false,
    this.timeText = '',
    this.statusResolved = true,
    this.recipient = const FundCardRecipient(),
    this.packetCount,
  });

  final FundMessageData message;
  final bool isGroupChat;
  final bool claimedByMe;
  final bool isOutgoing;
  final String timeText;
  final bool statusResolved;
  final FundCardRecipient recipient;
  final int? packetCount;
  bool get _exclusive => message.biz == 'packet_exclusive';
  bool get _groupTransfer => message.biz == 'group_transfer';
  bool get _usesRecipientAvatar => _exclusive || _groupTransfer;

  bool get _settled =>
      claimedByMe || message.status == 'done' || message.status == 'refunded';

  String? get _statusLabel {
    if (!statusResolved) return StrRes.fundOpenDetails;
    if (message.status == 'refunded') return StrRes.fundRefunded;
    if (claimedByMe) return StrRes.fundClaimed;
    if (message.status == 'open') {
      // The server credits transfers directly. An old snapshot never asks
      // the recipient to accept another payment.
      return message.isPacket ? null : StrRes.fundOpenDetails;
    }
    if (message.isTransfer) return StrRes.fundCredited;
    return isGroupChat && message.biz != 'packet_exclusive'
        ? StrRes.fundFullyClaimed
        : StrRes.fundClaimed;
  }

  @override
  Widget build(BuildContext context) {
    final palette = FundCardPalette.forCard(
      isPacket: message.isPacket,
      settled: _settled,
      dark: Theme.of(context).brightness == Brightness.dark,
      highContrast: MediaQuery.highContrastOf(context),
    );
    final amount = '${message.displayAmount} ${message.currencyLabel}';
    final remark = FundMessageData.normalizeRemark(message.remark);
    // The amount line is the packet total, never the viewer's received share.
    // A missing order count is omitted rather than guessed from the message.
    final receiverName = recipient.name.trim().isNotEmpty
        ? recipient.name.trim()
        : 'fundCardRecipient'.tr;
    final title = _exclusive
        ? recipient.name.trim().isEmpty
            ? StrRes.fundExclusivePacket
            : 'fundCardExclusiveTitle'.trParams({'name': receiverName})
        : _groupTransfer
            ? 'fundCardTransferTitle'.trParams({'name': receiverName})
            : message.isPacket
                ? remark.isNotEmpty
                    ? remark
                    : StrRes.fundGoodLuck
                : '${StrRes.fundTransfer} $amount';
    final status = _statusLabel;
    // The reference transfer card puts the memo below the amount. Keep the
    // actual credited/refunded state visible alongside that server text.
    final subtitles = [
      if (message.isTransfer && !_groupTransfer && remark.isNotEmpty) remark,
      if (status != null &&
          (!message.isPacket ||
              (statusResolved && message.status == 'refunded')) &&
          (!_groupTransfer || message.status == 'refunded' || !statusResolved))
        status,
    ];
    final semanticStatus = status ?? StrRes.fundClaimable;
    final semanticLabel = [
      message.typeLabel,
      if (_groupTransfer) title,
      message.isPacket ? title : amount,
      if (message.isPacket) 'fundCardPacketTotal'.trParams({'amount': amount}),
      if (message.isPacket && packetCount != null && packetCount! > 0)
        'fundCardPacketCount'.trParams({'count': '$packetCount'}),
      if (message.isTransfer && remark.isNotEmpty) remark,
      if (semanticStatus != StrRes.fundOpenDetails) semanticStatus,
      StrRes.fundOpenDetails,
    ].join(', ');
    final radius =
        BorderRadius.circular(FundCardMetrics.r(FundCardMetrics.cardRadius));
    final titleSize =
        FundCardMetrics.titleFontSize(mobile: FundCardMetrics.titleSizeMobile);
    final subtitleSize = FundCardMetrics.subtitleFontSize(
      mobile: message.isPacket
          ? FundCardMetrics.cardSp(FundCardMetrics.subtitleSizeMobile)
          : FundCardMetrics.sp(FundCardMetrics.subtitleSizeMobile),
    );
    final largeText =
        MediaQuery.textScalerOf(context).scale(titleSize) > titleSize;

    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth = FundCardMetrics.clampCardWidth(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : FundCardMetrics.maxWidth);
      final tailOverhang = FundCardMetrics.w(FundCardMetrics.tailOverhang);
      Widget tail() => Positioned(
            left: isOutgoing ? null : 0,
            right: isOutgoing ? 0 : null,
            top: FundCardMetrics.h(FundCardMetrics.tailTop),
            child: Transform.flip(
              flipX: !isOutgoing,
              child: CustomPaint(
                key: const Key('fund-card-tail'),
                size: Size(FundCardMetrics.w(FundCardMetrics.tailWidth),
                    FundCardMetrics.h(FundCardMetrics.tailHeight)),
                painter: _FundTailPainter(color: palette.body),
              ),
            ),
          );

      return Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: SizedBox(
          width: cardWidth,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (!isOutgoing) tail(),
              Padding(
                padding: EdgeInsets.only(
                    left: isOutgoing ? 0 : tailOverhang,
                    right: isOutgoing ? tailOverhang : 0),
                child: Material(
                  color: FundTokens.transparent,
                  child: InkWell(
                    borderRadius: radius,
                    child: DecoratedBox(
                      key: const Key('fund-card-surface'),
                      decoration: BoxDecoration(
                        color: message.isPacket ? null : palette.body,
                        gradient: message.isPacket
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [palette.bodyHighlight, palette.body])
                            : null,
                        borderRadius: radius,
                        boxShadow: message.isPacket && !_settled
                            ? [
                                BoxShadow(
                                  color: palette.body.withValues(
                                      alpha: FundCardMetrics.shadowOpacity),
                                  blurRadius: FundCardMetrics.shadowBlur,
                                  offset: Offset(
                                      0,
                                      FundCardMetrics.h(
                                          FundCardMetrics.shadowOffset)),
                                )
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ConstrainedBox(
                            key: const Key('fund-card-body'),
                            constraints: BoxConstraints(
                                minHeight: FundCardMetrics.minBodyHeight),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: FundCardMetrics.bodyPadding,
                                child: Row(
                                  crossAxisAlignment:
                                      FundCardMetrics.useDesktopChatCard
                                          ? CrossAxisAlignment.center
                                          : CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding:
                                          FundCardMetrics.useDesktopChatCard
                                              ? EdgeInsets.zero
                                              : EdgeInsets.only(
                                                  top: FundCardMetrics.h(2)),
                                      child: _FundLeading(
                                        recipient: _usesRecipientAvatar
                                            ? recipient
                                            : null,
                                        isPacket: message.isPacket,
                                        dimmed: message.isPacket && _settled,
                                        palette: palette,
                                      ),
                                    ),
                                    SizedBox(
                                        width: FundCardMetrics.leadingTextGap),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: largeText
                                                ? null
                                                : message.isPacket
                                                    ? 1
                                                    : 2,
                                            overflow: largeText
                                                ? null
                                                : TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: palette.title,
                                                fontSize: titleSize,
                                                fontWeight: FontWeight.w500,
                                                height:
                                                    FundCardMetrics.lineHeight),
                                          ),
                                          if (message.isPacket) ...[
                                            SizedBox(
                                                height: FundCardMetrics.lineGap(
                                                    mobile: FundCardMetrics.h(
                                                        FundCardMetrics
                                                            .packetSummaryGap))),
                                            FundPacketSummary(
                                                key: const Key(
                                                    'fund-card-packet-summary'),
                                                amount: amount,
                                                packetCount: packetCount,
                                                palette: palette),
                                          ],
                                          if (_groupTransfer) ...[
                                            SizedBox(
                                                height: FundCardMetrics.h(2)),
                                            Text(amount,
                                                key: const Key(
                                                    'fund-card-group-amount'),
                                                maxLines: largeText ? null : 1,
                                                overflow: largeText
                                                    ? null
                                                    : TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: palette.title,
                                                    fontSize: titleSize,
                                                    fontWeight: FontWeight.w500,
                                                    height: FundCardMetrics
                                                        .lineHeight)),
                                          ],
                                          for (final subtitle in subtitles) ...[
                                            SizedBox(
                                                height: FundCardMetrics.lineGap(
                                                    mobile: FundCardMetrics.h(
                                                        message.isPacket
                                                            ? 10
                                                            : 6))),
                                            Text(
                                              subtitle,
                                              maxLines: largeText
                                                  ? null
                                                  : message.isPacket
                                                      ? 1
                                                      : 2,
                                              overflow: largeText
                                                  ? null
                                                  : TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: palette.subtitle,
                                                  fontSize: subtitleSize,
                                                  fontWeight: FontWeight.w500,
                                                  height: FundCardMetrics
                                                      .lineHeight),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            key: const Key('fund-card-footer'),
                            padding: FundCardMetrics.footerPadding,
                            decoration: BoxDecoration(
                              color: message.isPacket
                                  ? palette.footer.withValues(
                                      alpha:
                                          FundCardMetrics.packetFooterOpacity)
                                  : palette.footer,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(FundCardMetrics.r(
                                    FundCardMetrics.cardRadius)),
                                bottomRight: Radius.circular(FundCardMetrics.r(
                                    FundCardMetrics.cardRadius)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(
                                  _exclusive
                                      ? StrRes.fundExclusivePacket
                                      : message.isPacket
                                          ? '99Chat红包'
                                          : '99Chat',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _footerStyle(palette),
                                )),
                                Text(timeText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _footerStyle(palette)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (isOutgoing) tail(),
            ],
          ),
        ),
      );
    });
  }

  TextStyle _footerStyle(FundCardPalette palette) => TextStyle(
        color: palette.footerText,
        fontSize: FundCardMetrics.footerSp(message.isPacket
            ? FundCardMetrics.packetFooterSize
            : FundCardMetrics.transferFooterSize),
        fontWeight: FontWeight.w500,
      );
}

class _FundLeading extends StatelessWidget {
  const _FundLeading(
      {required this.isPacket,
      required this.dimmed,
      required this.palette,
      this.recipient});
  final FundCardRecipient? recipient;

  final bool isPacket;
  final bool dimmed;
  final FundCardPalette palette;

  @override
  Widget build(BuildContext context) {
    final size = FundCardMetrics.iconSize();
    if (recipient != null) {
      return Opacity(
          opacity: dimmed ? FundCardMetrics.openedIconOpacity : 1,
          child: AvatarView(
              width: size,
              height: size,
              url: recipient!.faceURL,
              text: recipient!.name,
              isCircle: true));
    }
    if (isPacket) {
      return Opacity(
        opacity: dimmed ? FundCardMetrics.openedIconOpacity : 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FundCardMetrics.packetIconRadius),
          child: Image.asset('assets/img/red_packet_icon.png',
              width: size, height: size, fit: BoxFit.cover),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * FundCardMetrics.transferIconPaddingRatio),
      decoration: BoxDecoration(
        color: palette.iconBg,
        borderRadius: BorderRadius.circular(FundCardMetrics.useDesktopChatCard
            ? size / 2
            : FundCardMetrics.transferIconRadius),
      ),
      child: SvgPicture.string(
        _transferArrowIconSvg,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(palette.icon, BlendMode.srcIn),
      ),
    );
  }
}

/// The reference card's two quadratic curves, with its original overhang.
class _FundTailPainter extends CustomPainter {
  const _FundTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(size.width * .88, size.height * .14,
            size.width * .92, size.height * .46)
        ..quadraticBezierTo(size.width * .96, size.height * .78, 0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_FundTailPainter oldDelegate) =>
      oldDelegate.color != color;
}
