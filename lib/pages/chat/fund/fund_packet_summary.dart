import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'fund_card_metrics.dart';
import 'fund_card_palette.dart';

/// The 99chat packet headline's amount/count line, using real order totals.
class FundPacketSummary extends StatelessWidget {
  const FundPacketSummary(
      {super.key,
      required this.amount,
      required this.palette,
      this.packetCount});

  final String amount;
  final int? packetCount;
  final FundCardPalette palette;

  @override
  Widget build(BuildContext context) {
    final amountSize = FundCardMetrics.cardSp(FundCardMetrics.packetAmountSize);
    final largeText =
        MediaQuery.textScalerOf(context).scale(amountSize) > amountSize;
    final hasCount = packetCount != null && packetCount! > 0;
    return Text.rich(
        TextSpan(children: [
          TextSpan(
              text: amount,
              style: TextStyle(
                  color: palette.title,
                  fontSize: amountSize,
                  fontWeight: FontWeight.w700,
                  height: FundCardMetrics.packetSummaryLineHeight,
                  letterSpacing: FundCardMetrics.packetAmountLetterSpacing)),
          if (hasCount)
            TextSpan(
                text: ' · ${'fundCardPacketCount'.trParams({
                      'count': '$packetCount'
                    })}',
                style: TextStyle(
                    color: palette.subtitle,
                    fontSize: FundCardMetrics.cardSp(
                        FundCardMetrics.subtitleSizeMobile),
                    fontWeight: FontWeight.w500,
                    height: FundCardMetrics.packetSummaryLineHeight)),
        ]),
        maxLines: largeText ? null : 1,
        overflow: largeText ? null : TextOverflow.ellipsis);
  }
}
