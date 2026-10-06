// Adapted from 99chat lottery_dashboard.dart _openedStatistics.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import '../models/mark_six_draw.dart';
import 'mark_six_style.dart';

class MarkSixOpenedStatistics extends StatelessWidget {
  const MarkSixOpenedStatistics({super.key, required this.draws});
  final List<MarkSixDraw> draws;
  @override
  Widget build(BuildContext context) {
    final sample = draws.where((draw) => draw.drawn).take(100).toList();
    if (sample.isEmpty) return const MarkSixEmpty(message: '暂无已开奖记录');
    return Column(children: [
      _section(context, sample, '基本类型', [
        ('parity', '单', MarkSixStyle.blue),
        ('parity', '双', MarkSixStyle.red),
        ('size', '大', MarkSixStyle.red),
        ('size', '小', MarkSixStyle.blue)
      ]),
      _section(context, sample, '组合类型', [
        ('combination', '小单', MarkSixStyle.blue),
        ('combination', '小双', MarkSixStyle.green),
        ('combination', '大单', Colors.orange),
        ('combination', '大双', MarkSixStyle.red)
      ]),
      _section(
          context,
          sample,
          '色波',
          [
            ('wave', '红', MarkSixStyle.red),
            ('wave', '蓝', MarkSixStyle.blue),
            ('wave', '绿', MarkSixStyle.green)
          ],
          columns: 3),
      _section(context, sample, '生肖', [
        for (final zodiac in [
          '鼠',
          '牛',
          '虎',
          '兔',
          '龙',
          '蛇',
          '马',
          '羊',
          '猴',
          '鸡',
          '狗',
          '猪'
        ])
          ('zodiac', zodiac, null)
      ]),
    ]);
  }

  Widget _section(BuildContext context, List<MarkSixDraw> sample, String title,
      List<(String, String, Color?)> values,
      {int columns = 2}) {
    final style = MarkSixStyle.of(context);
    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: style.lotteryPanel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: style.lotteryBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 3, height: 19, color: style.primary),
            const SizedBox(width: 9),
            Expanded(
                child: Text('$title（${sample.length}期）',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800))),
            Icon(Icons.bar_chart_rounded, size: 16, color: style.primary),
            const SizedBox(width: 4),
            Text('数据统计', style: TextStyle(fontSize: 11, color: style.secondary))
          ]),
          const SizedBox(height: 10),
          Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
              decoration: BoxDecoration(
                  color: style.lotteryAlt,
                  borderRadius: BorderRadius.circular(11)),
              child: Column(children: [
                Row(children: [
                  for (var col = 0; col < columns; col++)
                    Expanded(
                        child: Row(children: [
                      Expanded(
                          flex: 4,
                          child: Text('类型',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: style.secondary))),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 5,
                          child: Text('已开次数',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: style.secondary))),
                    ]))
                ]),
                const SizedBox(height: 4),
                for (var start = 0; start < values.length; start += columns)
                  Row(children: [
                    for (var index = start; index < start + columns; index++)
                      Expanded(
                          child: index >= values.length
                              ? const SizedBox()
                              : Container(
                                  key: ValueKey(
                                      'opened-cell-${values[index].$1}-${values[index].$2}'),
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                      color: style.surface,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(color: style.divider)),
                                  child: Row(children: [
                                    Expanded(
                                        flex: 4,
                                        child: Container(
                                            height: 28,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                                color: values[index].$3 == null
                                                    ? style.lotteryAlt
                                                    : null,
                                                gradient: values[index].$3 ==
                                                        null
                                                    ? null
                                                    : LinearGradient(colors: [
                                                        values[index]
                                                            .$3!
                                                            .withValues(
                                                                alpha: .78),
                                                        values[index].$3!
                                                      ]),
                                                borderRadius:
                                                    BorderRadius.circular(18)),
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (values[index].$3 !=
                                                          null) ...[
                                                        const Icon(
                                                            Icons
                                                                .bar_chart_rounded,
                                                            size: 13,
                                                            color:
                                                                Colors.white),
                                                        const SizedBox(width: 3)
                                                      ],
                                                      Text(
                                                          values[index].$1 ==
                                                                  'wave'
                                                              ? '${values[index].$2}波'
                                                              : values[index]
                                                                          .$1 ==
                                                                      'zodiac'
                                                                  ? '特肖${values[index].$2}'
                                                                  : values[
                                                                          index]
                                                                      .$2,
                                                          style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: values[index]
                                                                          .$3 ==
                                                                      null
                                                                  ? style.text
                                                                  : Colors
                                                                      .white)),
                                                    ])))),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        flex: 5,
                                        child: Container(
                                            height: 28,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                                color: style.dark
                                                    ? const Color(0xFF193B32)
                                                    : const Color(0xFFEBFAF5),
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: Text(
                                                '${sample.where((draw) => (values[index].$1 == 'combination' ? '${draw.value('size')}${draw.value('parity')}' : draw.value(values[index].$1)) == values[index].$2).length}',
                                                style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    color:
                                                        Color(0xFF159664))))),
                                  ]))),
                  ]),
              ])),
        ]));
  }
}
