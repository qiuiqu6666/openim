// Adapted from 99chat lottery_dashboard.dart _livePredictions.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import '../data/mark_six_controller.dart';
import 'mark_six_style.dart';

const markSixAttributes = <String, String>{
  'special': '特码',
  'zodiac': '生肖',
  'parity': '单双',
  'size': '大小',
  'head': '头数',
  'tail': '尾数',
  'sumParity': '合单双',
  'fiveElement': '五行',
  'wave': '波色',
  'zuhe': '组合',
};

class MarkSixPredictions extends StatefulWidget {
  const MarkSixPredictions({super.key, required this.controller});
  final MarkSixController controller;
  @override
  State<MarkSixPredictions> createState() => _MarkSixPredictionsState();
}

class _MarkSixPredictionsState extends State<MarkSixPredictions> {
  String _attribute = 'special';
  bool _combined = true;
  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final c = widget.controller;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
            child: Text('逐期预测',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        TextButton(
            onPressed: () => _selectWindow(context),
            child: Text('最近 ${c.window} 期'))
      ]),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final attribute in markSixAttributes.entries)
              Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                      label: Text(attribute.value,
                          style: const TextStyle(fontSize: 12)),
                      selected: _attribute == attribute.key,
                      onSelected: (_) =>
                          setState(() => _attribute = attribute.key))),
          ])),
      SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: const Text('综合预测 · 全部属性',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Text('基于历史数据，AI智能分析仅供参考',
              style: TextStyle(fontSize: 10, color: style.secondary)),
          value: _combined,
          onChanged: (v) => setState(() => _combined = v)),
      for (final row in c.predictions)
        Container(
            key: ValueKey('prediction-issue-${row['issue']}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 4),
            decoration: BoxDecoration(
                color: style.surface,
                border: Border.all(color: style.lotteryBorder),
                borderRadius: BorderRadius.circular(11)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('第 ${row['issueLabel'] ?? row['issue']} 期',
                  style: TextStyle(
                      color: style.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              for (final item in markSixRows(row['items']).where(
                  (item) => _combined || item['attribute'] == _attribute))
                _candidate(context, row, item),
            ])),
      if (c.predictionsLoading)
        Center(child: LoadingView.indicator(size: 24))
      else if (c.predictionError != null)
        MarkSixEmpty(
            message: c.predictionError!,
            onRetry: () => c.loadPredictions(force: true))
      else if (c.predictions.isEmpty)
        const MarkSixEmpty(message: '暂无预测')
      else
        Center(
            child: TextButton(
                onPressed: c.predictionsHasMore
                    ? () => c.loadPredictions(more: true)
                    : null,
                child: Text(c.predictionsHasMore ? '加载更多' : '已加载全部预测'))),
    ]);
  }

  Widget _candidate(BuildContext context, Map<String, dynamic> row,
      Map<String, dynamic> item) {
    final style = MarkSixStyle.of(context);
    final key = '${item['attribute']}';
    final values = (item['values'] as List? ?? []).map((v) => '$v').toList();
    final status = row['drawState'] == 'cancelled'
        ? 'void'
        : row['predictionState'] == 'insufficient_sample'
            ? 'insufficient_sample'
            : row['predictionState'] == 'not_published'
                ? 'not_published'
                : '${item['result']}';
    const labels = {
      'pending': '待开奖',
      'hit': '中',
      'miss': '未中',
      'insufficient_sample': '样本不足',
      'not_published': '未发布',
      'void': '已取消'
    };
    final color = status == 'hit'
        ? MarkSixStyle.green
        : status == 'miss'
            ? MarkSixStyle.red
            : style.secondary;
    return Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: style.divider))),
        child: Row(children: [
          Icon(
              switch (key) {
                'zodiac' => Icons.pets_rounded,
                'wave' => Icons.waves_rounded,
                'size' => Icons.swap_vert_rounded,
                'zuhe' => Icons.link_rounded,
                _ => Icons.circle_outlined
              },
              size: 17,
              color: style.primary),
          const SizedBox(width: 4),
          SizedBox(
              width: 48,
              child: Text(markSixAttributes[key] ?? key,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(
              child: InkWell(
                  onLongPress: values.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                              ClipboardData(text: values.join(' ')));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('预测号码已复制')));
                          }
                        },
                  child: Text(values.isEmpty ? '—' : values.join(' '),
                      style: const TextStyle(fontSize: 12)))),
          if (markSixMap(row['actual'])[key] != null)
            Text('${markSixMap(row['actual'])[key]}',
                style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(labels[status] ?? '—',
                  style: TextStyle(fontSize: 11, color: color))),
        ]));
  }

  Future<void> _selectWindow(BuildContext context) async {
    final choices = (widget.controller.config?['windowOptions'] as List? ??
            [6, 12, 20, 30, 40])
        .whereType<int>()
        .where((n) => n > 0 && n <= 100);
    final selected = await showModalBottomSheet<int>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(title: Text('统计范围')),
              for (final count in choices)
                ListTile(
                    title: Text('最近 $count 期'),
                    trailing: count == widget.controller.window
                        ? Icon(Icons.check,
                            color: MarkSixStyle.of(context).primary)
                        : null,
                    onTap: () => Navigator.pop(context, count))
            ])));
    if (mounted && selected != null) {
      await widget.controller.selectWindow(selected);
    }
  }
}
