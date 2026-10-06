// Layout adapted from 99chat test_page.dart result table.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import '../models/mark_six_draw.dart';
import 'mark_six_latest_card.dart';
import 'mark_six_style.dart';

class MarkSixHistoryTable extends StatelessWidget {
  const MarkSixHistoryTable({super.key, required this.draws});
  final List<MarkSixDraw> draws;
  static const widths = [100, 44, 62, 38, 38, 30, 30, 30, 38, 38];
  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final rows = draws.where((draw) => draw.drawn).take(100).toList();
    if (rows.isEmpty) return const MarkSixEmpty(message: '暂无开奖记录');
    return Column(children: [
      _row(context,
          const ['时间', '期号', '特', '单双', '大小', '头', '尾', '合', '五行', '波色'],
          header: true),
      for (final draw in rows)
        _row(
            context,
            [
              draw.time,
              draw.issue,
              draw.number,
              draw.value('parity'),
              draw.value('size'),
              draw.value('head'),
              draw.value('tail'),
              draw.value('sumParity'),
              draw.value('fiveElement'),
              draw.wave
            ],
            draw: draw),
      Padding(
          padding: const EdgeInsets.all(12),
          child: Text('最近 ${rows.length} 期',
              style: TextStyle(fontSize: 11, color: style.secondary))),
    ]);
  }

  Widget _row(BuildContext context, List<String> values,
      {bool header = false, MarkSixDraw? draw}) {
    final style = MarkSixStyle.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    return Container(
        height: (header ? 34 : 36) * scale.clamp(1, 1.7),
        decoration: BoxDecoration(
            color: header ? style.lotteryAlt : style.surface,
            border:
                Border(bottom: BorderSide(color: style.divider, width: .8))),
        child: Row(children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
                flex: widths[i],
                child: Container(
                  height: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(color: style.divider, width: .8))),
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: !header && i == 2
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              MarkSixNumberBall(
                                  number: draw!.number,
                                  wave: draw.wave,
                                  size: 28),
                              const SizedBox(width: 2),
                              Text(draw.zodiac,
                                  style: const TextStyle(fontSize: 11))
                            ])
                          : Text(values[i],
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: header || [3, 4, 8, 9].contains(i)
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: !header && i == 9
                                      ? markSixWaveColor(values[i])
                                      : !header && [3, 7].contains(i)
                                          ? (values[i] == '单'
                                              ? MarkSixStyle.blue
                                              : values[i] == '双'
                                                  ? MarkSixStyle.red
                                                  : style.text)
                                          : !header && i == 4
                                              ? (values[i] == '小'
                                                  ? MarkSixStyle.blue
                                                  : values[i] == '大'
                                                      ? MarkSixStyle.red
                                                      : style.text)
                                              : style.text))),
                )),
        ]));
  }
}
