import 'package:flutter/material.dart';
import 'package:openim_common/localization.dart';
import 'package:openim_common/openim_common.dart';
import 'mark_six_style.dart';

class LotteryTabBar extends StatelessWidget {
  const LotteryTabBar(
      {super.key,
      required this.selectedIndex,
      required this.onChanged,
      this.rules = false});
  final bool rules;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final tabs = [
      AppCopy.text('开奖历史'),
      AppCopy.text('智能预测'),
      AppCopy.text('已开统计'),
      rules ? '游戏规则' : '本群宣言'
    ];
    final icons = [
      Icons.access_time_rounded,
      Icons.auto_awesome_rounded,
      Icons.bar_chart_rounded,
      rules ? Icons.menu_book_rounded : Icons.campaign_rounded
    ];
    return Container(
        key: const ValueKey('lottery-tab-bar'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            color: style.lotteryAlt,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: style.lotteryBorder)),
        child: Row(children: [
          for (var index = 0; index < tabs.length; index++)
            Expanded(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: selectedIndex == index
                            ? const LinearGradient(
                                colors: [Color(0xFF3A91FA), Color(0xFF1976F3)])
                            : null),
                    child: TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            foregroundColor: selectedIndex == index
                                ? AppTokens.onAccent
                                : style.secondary),
                        onPressed: () {
                          onChanged(index);
                        },
                        child: FittedBox(
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icons[index], size: 16),
                          const SizedBox(width: 6),
                          Text(tabs[index],
                              style: const TextStyle(fontSize: 12))
                        ])))))
        ]));
  }
}
