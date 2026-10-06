// Presets ported from 99chat agent_rebate_date_range_picker.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import '../models/agent_date_range.dart';
import '../../widgets/mark_six_style.dart';
import '../../../../mine/settings/widgets/settings_widgets.dart'
    show SettingsAction, showSettingsActionSheet;

Future<AgentRebateDateRange?> showAgentRebateDateRangePicker(
    BuildContext context,
    {required AgentRebateDateRange initialRange,
    DateTime? now}) {
  final clock = now ?? DateTime.now();
  final choices = <(String, AgentRebateDateRange)>[
    ('昨天', AgentRebateDateRange.yesterday(clock)),
    ('今天', AgentRebateDateRange.today(clock)),
    ('一周', AgentRebateDateRange.recentDays(7, clock)),
    ('30天', AgentRebateDateRange.recentDays(30, clock)),
    ('90天', AgentRebateDateRange.recentDays(90, clock)),
  ];
  return showSettingsActionSheet<AgentRebateDateRange>(context,
      title: '选择查询时间',
      actions: [
        for (final choice in choices)
          SettingsAction(choice.$1, choice.$2,
              subtitle: choice.$2.start == initialRange.start &&
                      choice.$2.end == initialRange.end
                  ? '当前选择'
                  : '${choice.$2.startApiValue} — ${choice.$2.endApiValue}')
      ]);
}

class AgentDateRangeBar extends StatelessWidget {
  const AgentDateRangeBar({super.key, required this.range, this.onPressed});
  final AgentRebateDateRange range;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    return Material(
        color: style.surface,
        child: InkWell(
            onTap: onPressed,
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Icon(Icons.date_range_outlined, color: style.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          '${range.startApiValue} — ${range.endApiValue}',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 13, color: style.secondary))),
                  Icon(Icons.expand_more, color: style.secondary)
                ]))));
  }
}
