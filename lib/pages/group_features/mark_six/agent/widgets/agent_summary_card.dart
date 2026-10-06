// Adapted from 99chat agent_rebate_summary_card.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../widgets/mark_six_style.dart';

class AgentSummaryCard extends StatelessWidget {
  const AgentSummaryCard(
      {super.key,
      required this.title,
      required this.summary,
      this.subtitle,
      this.personal = false,
      this.highlight = false,
      this.history = false,
      this.showCounts = true});
  final String title;
  final String? subtitle;
  final Map<String, dynamic> summary;
  final bool personal, highlight, history, showCounts;
  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final values = personal
        ? <(String, String)>[
            ('玩家余额', 'balance'),
            ('个人总流水', 'totalFlow'),
            ('个人总输赢', 'totalProfitLoss'),
            ('已反水', 'totalRebate'),
            ('个人待反水', 'pendingRebate'),
            ('级差待结算', 'agentPendingRebate'),
          ]
        : <(String, String)>[
            if (showCounts && history) ('代理人数', 'agentCount'),
            (history ? (showCounts ? '玩家人数' : '记录数') : '用户人数', 'playerCount'),
            ('总余额', 'totalBalance'),
            ('总流水', 'totalFlow'),
            ('玩家输赢', 'playerProfitLoss'),
            if (history && showCounts) ('平台输赢', 'platformProfitLoss'),
            ('总上分', 'totalUp'),
            ('总下分', 'totalDown'),
            if (history) (showCounts ? '团队总反水' : '已反水', 'totalRebated'),
          ];
    return Container(
        padding: const EdgeInsets.all(AppTokens.s5),
        decoration: BoxDecoration(
            color: style.surface,
            borderRadius: BorderRadius.circular(MarkSixStyle.radius),
            border: Border.all(
                color: highlight
                    ? style.primary.withValues(alpha: .45)
                    : style.divider),
            boxShadow: MarkSixStyle.shadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: highlight ? style.primary : style.text)),
          if (subtitle?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: TextStyle(fontSize: 12, color: style.secondary))
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
              builder: (context, constraints) =>
                  Wrap(spacing: 12, runSpacing: 16, children: [
                    for (final item in values)
                      SizedBox(
                          width: (constraints.maxWidth - 12) / 2,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.$1,
                                    style: TextStyle(
                                        fontSize: 12, color: style.secondary)),
                                const SizedBox(height: 4),
                                Text(markSixAmount(summary[item.$2]),
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: style.text)),
                              ]))
                  ])),
        ]));
  }
}
