// Layout adapted from 99chat agent_rebate_descendant_history_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../models/group_feature_context.dart';
import '../../data/mark_six_repository.dart';
import '../../widgets/mark_six_style.dart';
import '../data/agent_query_controller.dart';
import '../models/agent_date_range.dart';
import '../widgets/agent_date_range_picker.dart';

class AgentDescendantHistoryPage extends StatefulWidget {
  const AgentDescendantHistoryPage(
      {super.key, required this.featureContext, required this.userID});
  final GroupFeatureContext featureContext;
  final String userID;
  @override
  State<AgentDescendantHistoryPage> createState() =>
      _AgentDescendantHistoryPageState();
}

class _AgentDescendantHistoryPageState
    extends State<AgentDescendantHistoryPage> {
  late final _repository = MarkSixRepository(widget.featureContext);
  late final _state = AgentQueryController(_repository);
  AgentRebateDateRange _range = AgentRebateDateRange.today();
  bool get allowed =>
      widget.featureContext.sessionCurrent() &&
      widget.featureContext.capabilitiesCurrent() &&
      widget.featureContext.capabilities.markSix.canViewRebateHistory;
  Future<void> _load({bool force = false}) =>
      _state.load('/me/agent/descendants/history',
          query: {
            'startDate': _range.startApiValue,
            'endDate': _range.endApiValue,
            'userId': widget.userID
          },
          force: force);
  @override
  void initState() {
    super.initState();
    if (allowed && widget.userID.isNotEmpty) unawaited(_load());
  }

  @override
  void dispose() {
    _state.dispose();
    _repository.close();
    super.dispose();
  }

  Future<void> _dates() async {
    final range =
        await showAgentRebateDateRangePicker(context, initialRange: _range);
    if (!mounted || !allowed || range == null) return;
    setState(() => _range = range);
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final style = MarkSixStyle.of(context);
        final rows = markSixRows(_state.data)
          ..sort((a, b) =>
              '${b['businessDate']}'.compareTo('${a['businessDate']}'));
        return Scaffold(
            backgroundColor: style.background,
            appBar: markSixAppBar(context, '下级历史记录'),
            body: SafeArea(
                top: false,
                child: Column(children: [
                  AgentDateRangeBar(
                      range: _range,
                      onPressed: !_state.loading && allowed ? _dates : null),
                  Expanded(
                      child: !allowed
                          ? const MarkSixEmpty(message: '你没有收益历史权限')
                          : !_state.current
                              ? const MarkSixEmpty(message: '登录状态已变更')
                              : _state.loading
                                  ? Center(child: LoadingView.indicator())
                                  : _state.error != null
                                      ? MarkSixEmpty(
                                          message: _state.error!,
                                          onRetry: () => _load(force: true))
                                      : RefreshIndicator(
                                          onRefresh: () => _load(force: true),
                                          child: ListView.separated(
                                              padding: const EdgeInsets.all(16),
                                              physics:
                                                  const AlwaysScrollableScrollPhysics(),
                                              itemCount: rows.isEmpty
                                                  ? 1
                                                  : rows.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 12),
                                              itemBuilder: (_, index) => rows
                                                      .isEmpty
                                                  ? const MarkSixEmpty(
                                                      message: '所选日期暂无下级记录')
                                                  : _card(
                                                      context, rows[index])))),
                ])));
      });
  Widget _card(BuildContext context, Map<String, dynamic> item) {
    final style = MarkSixStyle.of(context);
    final profit = num.tryParse('${item['playerProfitLoss']}');
    final profitColor = profit == null || profit == 0
        ? style.text
        : profit < 0
            ? style.error
            : MarkSixStyle.green;
    const metrics = [
      ('流水', 'totalFlow'),
      ('玩家输赢', 'playerProfitLoss'),
      ('余额', 'balance'),
      ('待反水', 'pendingRebate'),
      ('上分', 'totalUp'),
      ('下分', 'totalDown')
    ];
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: style.surface,
            borderRadius: BorderRadius.circular(MarkSixStyle.radius),
            border: Border.all(color: style.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item['businessDate'] ?? '—'}',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: style.text)),
          const SizedBox(height: 12),
          LayoutBuilder(
              builder: (context, constraints) =>
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final metric in metrics)
                      SizedBox(
                          width: (constraints.maxWidth - 12) / 2,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(metric.$1,
                                    style: TextStyle(
                                        fontSize: 12, color: style.secondary)),
                                const SizedBox(height: 4),
                                Text(markSixAmount(item[metric.$2]),
                                    style: TextStyle(
                                        fontSize: metric.$2 == 'totalFlow' ||
                                                metric.$2 == 'playerProfitLoss'
                                            ? 18
                                            : 15,
                                        fontWeight: FontWeight.w600,
                                        color: metric.$2 == 'playerProfitLoss'
                                            ? profitColor
                                            : style.text)),
                              ]))
                  ])),
        ]));
  }
}
