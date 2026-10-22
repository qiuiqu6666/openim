import 'package:flutter/material.dart';
import '../mark_six/widgets/mark_six_style.dart';
import '../mark_six/widgets/mark_six_latest_card.dart' show MarkSixNumberBall;
import 'bingo_draw.dart';

/// Compact history rows using the provider's actual published issue.
class BingoHistoryTable extends StatelessWidget {
  const BingoHistoryTable({super.key, required this.draws});
  final List<BingoDraw> draws;

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    Color attributeColor(String value) => switch (value) {
          '大' || '单' || '合大' || '合单' || '尾大' => MarkSixStyle.red,
          '小' || '双' || '合小' || '合双' || '尾小' => MarkSixStyle.blue,
          _ => style.secondary,
        };
    Widget cell(String label, double width,
            {double height = 44, Color? color, Widget? child}) =>
        Container(
          width: width * scale,
          height: height * scale,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
                right: BorderSide(color: style.lotteryBorder),
                bottom: BorderSide(color: style.lotteryBorder)),
          ),
          child: child ??
              Text(label,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: color ?? style.text)),
        );
    Widget group(String title, List<String> labels, List<double> widths) =>
        Column(children: [
          cell(title, widths.reduce((a, b) => a + b),
              height: 22, color: style.secondary),
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              cell(labels[i], widths[i], height: 22, color: style.secondary)
          ]),
        ]);
    Widget ball(BingoBall b) => Row(mainAxisSize: MainAxisSize.min, children: [
          MarkSixNumberBall(
              number: b.number.toString().padLeft(2, '0'),
              size: 24,
              wave: b.color == Colors.red
                  ? '红'
                  : b.color == Colors.blue
                      ? '蓝'
                      : b.color == Colors.green
                          ? '绿'
                          : ''),
          const SizedBox(width: 2),
          Text(b.zodiac, style: TextStyle(fontSize: 11, color: style.text)),
        ]);
    final table =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('左右滑动查看完整记录',
          style: TextStyle(fontSize: 12, color: style.secondary)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration:
              BoxDecoration(border: Border.all(color: style.lotteryBorder)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: [
              ColoredBox(
                  color: style.lotteryAlt,
                  child: Row(children: [
                    cell('期数', 66),
                    cell('正码', 252),
                    cell('特码', 44),
                    group('特码', ['五行', '大小', '单双', '合大小', '合单双', '尾大小'],
                        [30, 30, 30, 40, 40, 40]),
                    group('总和', ['总数', '大小', '单双'], [40, 30, 30]),
                    cell('肖量', 40),
                    cell('尾量', 40),
                  ])),
              for (var i = 0; i < draws.length; i++)
                ColoredBox(
                    color: i.isEven ? style.lotteryPanel : style.surface,
                    child: Row(children: [
                      cell(draws[i].issue, 66),
                      cell('', 252,
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: draws[i].regular.map(ball).toList())),
                      cell('', 44, child: ball(draws[i].special)),
                      cell(draws[i].special.fiveElement, 30,
                          color: style
                              .fiveElementColor(draws[i].special.fiveElement)),
                      cell(draws[i].special.bigSmall, 30,
                          color:
                              style.resultTagAccent(draws[i].special.bigSmall)),
                      cell(draws[i].special.oddEven, 30,
                          color: draws[i].special.oddEven == '单'
                              ? MarkSixStyle.red
                              : draws[i].special.oddEven == '双'
                                  ? MarkSixStyle.blue
                                  : style.secondary),
                      cell(draws[i].special.compositeSize, 40,
                          color:
                              attributeColor(draws[i].special.compositeSize)),
                      cell(draws[i].special.compositeParity, 40,
                          color:
                              attributeColor(draws[i].special.compositeParity)),
                      cell(draws[i].special.tailSize, 40,
                          color: attributeColor(draws[i].special.tailSize)),
                      cell('${_sum(draws[i])}', 40),
                      cell(draws[i].sumBigSmall, 30,
                          color: attributeColor(draws[i].sumBigSmall)),
                      cell(draws[i].sumOddEven, 30,
                          color: attributeColor(draws[i].sumOddEven)),
                      cell(
                          _balls(draws[i]).any((b) => b.zodiac == '—')
                              ? '—'
                              : '${_balls(draws[i]).map((b) => b.zodiac).toSet().length}肖',
                          40),
                      cell(
                          '${_balls(draws[i]).map((b) => b.number % 10).toSet().length}尾',
                          40),
                    ])),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('未提供的属性显示 —',
          style: TextStyle(fontSize: 12, color: style.secondary)),
    ]);
    return table;
  }

  Iterable<BingoBall> _balls(BingoDraw draw) => [...draw.regular, draw.special];
  int _sum(BingoDraw draw) => _balls(draw).fold(0, (sum, b) => sum + b.number);
}
