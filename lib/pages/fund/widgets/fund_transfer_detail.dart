import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/fund_api.dart';
import 'fund_packet_detail.dart';
import 'fund_coin_icon.dart';
import 'fund_page_colors.dart';

// Presentation adapted from qiuiqu6666/99chat, revision d7c3c65 (Apache-2.0).
class FundTransferDetail extends StatelessWidget {
  const FundTransferDetail(
      {super.key,
      required this.order,
      required this.appBar,
      required this.sender,
      required this.receiver,
      required this.statusText,
      required this.text,
      required this.formatTime,
      required this.inlineErrors,
      required this.secondaryInfo});
  final FundOrder order;
  final PreferredSizeWidget appBar;
  final String sender, receiver, statusText;
  final FundDetailText text;
  final String Function(DateTime time) formatTime;
  final Widget inlineErrors, secondaryInfo;
  @override
  Widget build(BuildContext context) {
    final cs = FundPageColors.of(context);
    final received = order.status == 'done';
    final remark = order.remark.trim();
    return Scaffold(
      backgroundColor: cs.card,
      appBar: appBar,
      body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            key: const ValueKey('fund-detail-scroll'),
            padding: const EdgeInsets.fromLTRB(AppTokens.s8,
                FundTokens.transferTopGap, AppTokens.s8, FundTokens.iconSize),
            child: Center(
                child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: FundTokens.contentMaxWidth),
              child: Column(children: [
                Container(
                    key: ValueKey(received
                        ? 'fund-transfer-success'
                        : 'fund-transfer-pending'),
                    width: FundTokens.transferStatusIconSize,
                    height: FundTokens.transferStatusIconSize,
                    decoration: BoxDecoration(
                        color:
                            received ? FundTokens.transferFilled : cs.subText,
                        shape: BoxShape.circle),
                    child: Icon(
                        received
                            ? Icons.check_rounded
                            : Icons.info_outline_rounded,
                        color: AppTokens.onAccent,
                        size: FundTokens.transferStatusGlyphSize)),
                const SizedBox(height: FundTokens.transferIconGap),
                Text(
                    text(
                        order.scene == FundScene.group
                            ? '$sender群转账给$receiver'
                            : '$sender向$receiver发起的转账',
                        'Transfer from $sender to $receiver'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: FundTokens.detailTitleFont,
                        color: cs.text,
                        fontWeight: FontWeight.w400)),
                const SizedBox(height: FundTokens.transferSectionGap),
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FundCoinIcon(
                          currency: order.currency,
                          size: FundTokens.coinLogoSize),
                      const SizedBox(width: FundTokens.referenceCoinLabelGap),
                      Text(order.currency.displayName,
                          style: TextStyle(
                              fontSize: AppTokens.listTitleFontSize,
                              color: cs.text,
                              fontWeight: FontWeight.w400)),
                    ]),
                const SizedBox(height: FundTokens.transferSectionGap),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(order.amount.displayDecimal,
                        key: const ValueKey('fund-detail-amount'),
                        style: TextStyle(
                            fontSize: FundTokens.detailAmountFontSize,
                            height: 1,
                            color: cs.text,
                            fontWeight: FontWeight.w400,
                            letterSpacing: .3))),
                const SizedBox(height: FundTokens.transferMetaGap),
                Divider(
                    height: 1,
                    thickness: FundTokens.cardFooterDividerWidth,
                    color: cs.line),
                const SizedBox(height: FundTokens.referenceTransferMetaTopGap),
                _detailRow(context, text('当前状态', 'Current status'),
                    received ? text('已接收', 'Received') : statusText,
                    valueKey: const ValueKey('fund-detail-status')),
                if (remark.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.s4),
                  _detailRow(context, text('转账备注', 'Memo'), remark,
                      valueKey: const ValueKey('fund-detail-transfer-remark')),
                ],
                if (order.createdAt != null) ...[
                  const SizedBox(height: AppTokens.s4),
                  _detailRow(context, text('转账时间', 'Transfer time'),
                      formatTime(order.createdAt!)),
                ],
                const SizedBox(height: AppTokens.s4),
                _detailRow(context, text('收款人', 'Recipient'), receiver),
                inlineErrors,
                secondaryInfo,
              ]),
            )),
          )),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value,
      {Key? valueKey}) {
    final cs = FundPageColors.of(context);
    return Row(children: [
      SizedBox(
          width: FundTokens.transferMetaLabelWidth,
          child: Text(label,
              style: TextStyle(
                  fontSize: AppTokens.captionFontSize, color: cs.subText))),
      Expanded(
          child: Text(value,
              key: valueKey,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: AppTokens.captionFontSize, color: cs.text)))
    ]);
  }
}
