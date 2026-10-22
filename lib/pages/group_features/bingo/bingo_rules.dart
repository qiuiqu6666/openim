import 'package:flutter/material.dart';
import '../mark_six/widgets/mark_six_style.dart';

/// Built-in explanations of the confirmed Bingo Mark Six display rules.
class BingoRules extends StatelessWidget {
  const BingoRules({super.key});

  static const sections = [
    ('开奖号码', '号码范围为 01～49。每期开出 7 个号码，前 6 个为正码（平码），第 7 个为特码。开奖历史按该组号码实际所属期号展示。'),
    (
      '特码大小与单双',
      '01～24 为小，25～48 为大；49 为平。除 49 外，奇数为单、偶数为双。49 的大小和单双均按“平”显示，不计入大单、大双、小单、小双组合。'
    ),
    (
      '尾数与合数',
      '尾数指号码的个位：0～4 为尾小，5～9 为尾大。合数为十位与个位相加：1～6 为合小，7～13 为合大；合数为奇数时为合单，偶数时为合双。例如 34 的合数为 7，显示合大、合单，尾数为 4，显示尾小。'
    ),
    ('总和', '总和包含 6 个正码和 1 个特码。总和不超过 174 为小，至少 175 为大；总和为奇数时为单，偶数时为双。'),
    (
      '波色、生肖与五行',
      '波色分为红波、蓝波、绿波，使用对应颜色的号码球展示。生肖和金、木、水、火、土五行按该期开奖数据标注；缺失或无法识别的属性显示“—”。'
    ),
    (
      '已开统计',
      '统计最近最多 100 期的特码，包括基本类型、大小单双组合、波色和生肖。标题显示实际统计期数；“平”单独计数，历史统计不代表未来开奖结果。'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (title, body) in sections)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: style.lotteryPanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: style.lotteryBorder)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
                header: true,
                child: Text(title,
                    style: TextStyle(
                        color: style.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700))),
            const SizedBox(height: 8),
            Text(body,
                style: TextStyle(
                    color: style.secondary, fontSize: 13, height: 1.6)),
          ]),
        ),
    ]);
  }
}
