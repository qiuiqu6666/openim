import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/fund_api.dart';
import 'fund_page_colors.dart';
import 'fund_packet_cover.dart';

typedef FundDetailText = String Function(String chinese, String english);
typedef FundDetailAvatarBuilder = Widget Function(String userID, double size);
typedef FundDetailAmountBuilder = Widget Function(
    FundAmount amount,
    FundCurrency currency,
    double amountFontSize,
    double unitFontSize,
    double lineHeight);

// Presentation adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
/// Shared packet details; eligibility and mutations belong to the page.
class FundPacketDetail extends StatelessWidget {
  const FundPacketDetail(
      {super.key,
      required this.order,
      required this.userID,
      required this.claimedAmount,
      required this.loading,
      required this.claiming,
      required this.appBar,
      required this.statusText,
      required this.greeting,
      required this.partyAvatar,
      required this.partyName,
      required this.amountView,
      required this.text,
      required this.formatTime,
      required this.inlineErrors,
      required this.footer,
      required this.onRefresh,
      required this.onShowCover});
  final FundOrder order;
  final String userID, statusText, greeting;
  final FundAmount? claimedAmount;
  final bool loading, claiming;
  final PreferredSizeWidget appBar;
  final FundDetailAvatarBuilder partyAvatar;
  final String Function(String userID) partyName;
  final FundDetailAmountBuilder amountView;
  final FundDetailText text;
  final String Function(DateTime time) formatTime;
  final Widget inlineErrors, footer;
  final Future<void> Function() onRefresh;
  final VoidCallback? onShowCover;
  @override
  Widget build(BuildContext context) {
    final cs = FundPageColors.of(context);
    final claims =
        order.shares.where((share) => share.isClaimed).toList(growable: false);
    // A completed direct credit already proves the recipient and amount. It
    // does not create a claim share or provide a separate receipt timestamp.
    final directlyCredited = !order.requiresClaim && order.status == 'done';
    final amount = directlyCredited
        ? order.amount
        : order.claimedShareFor(userID)?.amount ?? claimedAmount;
    final units = claims.fold<BigInt>(
        BigInt.zero, (sum, share) => sum + share.amount.units);
    final scale = BigInt.from(10).pow(order.currency.decimals);
    final totalClaimed = FundAmount.parse(
        '${units ~/ scale}.${(units % scale).toString().padLeft(order.currency.decimals, '0')}',
        order.currency);
    return Scaffold(
      backgroundColor:
          cs.dark ? FundTokens.luckySurfaceDark : AppTokens.onAccent,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: Column(children: [
        SizedBox(
            key: const ValueKey('fund-detail-packet-header'),
            height: MediaQuery.paddingOf(context).top +
                kToolbarHeight +
                FundTokens.luckyHeaderExtraHeight,
            width: double.infinity,
            child: const CustomPaint(painter: FundLuckyHeaderPainter())),
        Expanded(
            child: Center(
                child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: FundTokens.detailMaxWidth),
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: CustomScrollView(
                key: const ValueKey('fund-detail-scroll'),
                slivers: [
                  if (loading)
                    const SliverToBoxAdapter(
                        child: LinearProgressIndicator(
                            minHeight: FundTokens.spinnerStroke)),
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppTokens.s7,
                              AppTokens.s7, AppTokens.s7, AppTokens.s8),
                          child: Column(children: [
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  partyAvatar(order.senderID,
                                      FundTokens.detailSenderAvatarSize),
                                  const SizedBox(width: AppTokens.s3),
                                  Flexible(
                                      child: Text(
                                          text(
                                              '${partyName(order.senderID)}的红包',
                                              'Red packet from ${partyName(order.senderID)}'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: cs.text,
                                              fontSize:
                                                  FundTokens.detailTitleFont,
                                              fontWeight: FontWeight.w500))),
                                ]),
                            const SizedBox(height: AppTokens.s4),
                            Text(greeting,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: cs.text,
                                    fontSize: FundTokens.detailGreetingFontSize,
                                    height: 1.4)),
                            const SizedBox(
                                height: FundTokens.referenceAmountGap),
                            if (amount != null)
                              amountView(
                                  amount,
                                  order.currency,
                                  FundTokens.packetAmountFontSize,
                                  FundTokens.detailUnitFontSize,
                                  FundTokens.detailAmountLineHeight)
                            else
                              Text(statusText,
                                  key: const ValueKey('fund-detail-status'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: cs.subText,
                                      fontSize: AppTokens.listTitleFontSize,
                                      height: 1.5)),
                            if (amount != null)
                              Semantics(
                                  liveRegion: true,
                                  child: Text(statusText,
                                      key: const ValueKey('fund-detail-status'),
                                      style: TextStyle(
                                          color: cs.subText,
                                          fontSize:
                                              FundTokens.detailStatusFontSize),
                                      textAlign: TextAlign.center)),
                          ]))),
                  SliverToBoxAdapter(child: inlineErrors),
                  SliverToBoxAdapter(
                      child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.s6,
                              vertical: AppTokens.captionFontSize),
                          decoration: BoxDecoration(
                              color: cs.dark
                                  ? FundTokens.progressDark
                                  : FundTokens.progressLight,
                              border: Border(
                                  bottom: BorderSide(
                                      color: cs.line,
                                      width:
                                          FundTokens.cardFooterDividerWidth))),
                          child: Text(
                              directlyCredited
                                  ? text(
                                      '已到账 1/1 个，共 ${order.amount.displayDecimal}/${order.amount.displayDecimal} ${order.currency.displayName}',
                                      '1/1 credited · ${order.amount.displayDecimal}/${order.amount.displayDecimal} ${order.currency.displayName}')
                                  : !order.isOpen && claims.isEmpty
                                      ? text(
                                          '共 ${order.shareCount} 个，总额 ${order.amount.displayDecimal} ${order.currency.displayName}',
                                          '${order.shareCount} packets · total ${order.amount.displayDecimal} ${order.currency.displayName}')
                                      : text(
                                          '已领取 ${claims.length}/${order.shareCount} 个，共 ${totalClaimed.displayDecimal}/${order.amount.displayDecimal} ${order.currency.displayName}',
                                          '${claims.length}/${order.shareCount} claimed · ${totalClaimed.displayDecimal}/${order.amount.displayDecimal} ${order.currency.displayName}'),
                              key: const ValueKey('fund-detail-share-progress'),
                              style: TextStyle(
                                  color: cs.subText,
                                  fontSize: FundTokens.progressFont,
                                  height: 1.5)))),
                  if (directlyCredited)
                    SliverToBoxAdapter(
                        child: _buildRecipientRow(context,
                            key: const ValueKey('fund-detail-direct-recipient'),
                            recipientID: order.recvID,
                            amount: order.amount,
                            time: order.createdAt))
                  else if (claims.isEmpty)
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppTokens.s7,
                                vertical: FundTokens.referenceEmptyGap),
                            child: Text(
                                order.isOpen
                                    ? text('还没有人领取这个红包',
                                        'No one has claimed this red packet yet.')
                                    : text('暂无领取明细',
                                        'No claim details are available.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: cs.subText,
                                    fontSize: AppTokens.captionFontSize))))
                  else
                    SliverList(
                        delegate: SliverChildBuilderDelegate(
                            (context, index) => Column(children: [
                                  _buildClaimRow(context, claims[index], order),
                                  if (index < claims.length - 1)
                                    Divider(
                                        height:
                                            FundTokens.cardFooterDividerWidth,
                                        thickness:
                                            FundTokens.cardFooterDividerWidth,
                                        indent: FundTokens
                                            .referenceRecordDividerIndent,
                                        endIndent: AppTokens.s6,
                                        color: cs.line),
                                ]),
                            childCount: claims.length)),
                  if (order.requiresClaim && amount == null)
                    SliverToBoxAdapter(
                        child: TextButton(
                            key: const ValueKey('fund-detail-back-cover'),
                            onPressed: onShowCover,
                            child: Text(text('返回红包封面', 'Back to red packet')))),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppTokens.s7)),
                ]),
          ),
        ))),
        footer,
      ]),
    );
  }

  Widget _buildClaimRow(
      BuildContext context, FundShare share, FundOrder order) {
    FundShare? best;
    if (order.biz == 'packet_lucky' && order.status == 'done') {
      for (final item in order.shares.where((share) => share.isClaimed)) {
        if (best == null || item.amount.compareTo(best.amount) > 0) best = item;
      }
    }
    return _buildRecipientRow(context,
        key: ValueKey('fund-detail-share-${share.index}'),
        recipientID: share.claimerID,
        amount: share.amount,
        time: share.claimedAt,
        bestLuck: best?.index == share.index);
  }

  Widget _buildRecipientRow(BuildContext context,
      {required Key key,
      required String recipientID,
      required FundAmount amount,
      DateTime? time,
      bool bestLuck = false}) {
    final cs = FundPageColors.of(context);
    final amountView =
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('${amount.displayDecimal} ${order.currency.displayName}',
          style: TextStyle(
              color: cs.text,
              fontSize: FundTokens.recordAmountFont,
              fontWeight: FontWeight.w500)),
      if (bestLuck) ...[
        const SizedBox(height: FundTokens.referenceRecordGap),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.emoji_events_outlined,
              color: cs.tagTextColor, size: FundTokens.recordTimeFont),
          const SizedBox(width: FundTokens.referenceRecordGap),
          Text(text('手气最佳', 'Best luck'),
              style: TextStyle(
                  color: cs.tagTextColor, fontSize: FundTokens.recordTimeFont)),
        ]),
      ],
    ]);
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s6, vertical: AppTokens.s5),
      child: LayoutBuilder(builder: (context, constraints) {
        final stack = constraints.maxWidth < FundTokens.referenceStackWidth ||
            MediaQuery.textScalerOf(context).scale(AppTokens.captionFontSize) >
                AppTokens.s6;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          partyAvatar(recipientID, FundTokens.recordAvatarSize),
          const SizedBox(width: AppTokens.s4),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(partyName(recipientID),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: cs.text,
                        fontSize: FundTokens.detailTitleFont,
                        height: 1.3)),
                if (time != null) ...[
                  const SizedBox(height: FundTokens.referenceRecordGap),
                  Text(formatTime(time),
                      style: TextStyle(
                          color: cs.subText,
                          fontSize: FundTokens.recordTimeFont)),
                ],
                if (stack) ...[
                  const SizedBox(height: AppTokens.s3),
                  amountView
                ],
              ])),
          if (!stack) ...[
            const SizedBox(width: AppTokens.s4),
            Flexible(
                fit: FlexFit.tight,
                child: Align(alignment: Alignment.topRight, child: amountView)),
          ],
        ]);
      }),
    );
  }
}
