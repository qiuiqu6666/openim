// Layout adapted from 99chat agent_rebate_current_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../models/group_feature_context.dart';
import '../../data/mark_six_repository.dart';
import '../../widgets/mark_six_style.dart';
import '../data/agent_rebate_controller.dart';
import '../widgets/agent_summary_card.dart';

class AgentCurrentPage extends StatefulWidget {
  const AgentCurrentPage({super.key, required this.featureContext});
  final GroupFeatureContext featureContext;
  @override
  State<AgentCurrentPage> createState() => _AgentCurrentPageState();
}

class _AgentCurrentPageState extends State<AgentCurrentPage> {
  late final _repository = MarkSixRepository(widget.featureContext);
  late final _state = AgentRebateController(_repository);
  bool get allowed =>
      widget.featureContext.sessionCurrent() &&
      widget.featureContext.capabilitiesCurrent() &&
      widget.featureContext.capabilities.markSix.canOpenAgent;
  @override
  void initState() {
    super.initState();
    if (allowed) unawaited(_state.initialize());
  }

  @override
  void dispose() {
    _state.dispose();
    _repository.close();
    super.dispose();
  }

  Future<void> _confirmApply() async {
    if (!allowed || !_state.canApply()) {
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('确认级差反水'),
                content: const Text('申请结算本人级差待结算。金额由机器人侧核算，确定继续吗？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认申请'))
                ]));
    if (!mounted || !allowed || confirmed != true || !_state.canApply()) return;
    await _state.apply();
    if (mounted && _state.current && _state.settled) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('反水结算成功')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final style = MarkSixStyle.of(context);
        return Scaffold(
            backgroundColor: style.background,
            appBar: markSixAppBar(context, '当前反水汇总'),
            body: SafeArea(
                top: false,
                child: Column(children: [
                  Expanded(
                      child: !allowed
                          ? const MarkSixEmpty(message: '你没有代理功能权限')
                          : !_state.current
                              ? const MarkSixEmpty(message: '登录状态已变更')
                              : _state.loading
                                  ? Center(child: LoadingView.indicator())
                                  : _state.error != null
                                      ? MarkSixEmpty(
                                          message: _state.error!,
                                          onRetry: () =>
                                              _state.initialize(force: true))
                                      : _body(context)),
                  if (allowed && _state.data != null)
                    Container(
                        width: double.infinity,
                        color: style.surface,
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          if (_state.applyError != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(_state.applyError!,
                                    style: TextStyle(color: style.error))),
                          if (_state.submitting ||
                              _state.polling ||
                              _state.restoring)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      LoadingView.indicator(size: 20),
                                      const SizedBox(width: 8),
                                      Flexible(
                                          child: Text(_state.restoring
                                              ? '正在确认上次申请状态…'
                                              : '反水处理中，请稍候…'))
                                    ])),
                          SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                  onPressed: !_state.current ||
                                          _state.restoring ||
                                          _state.submitting ||
                                          _state.polling
                                      ? null
                                      : _state.needsStatusQuery
                                          ? () => _state.checkStatus()
                                          : _state.canApply()
                                              ? _confirmApply
                                              : null,
                                  child: Text(_state.restoring
                                      ? '恢复申请状态中…'
                                      : _state.submitting
                                          ? '提交中…'
                                          : _state.polling
                                              ? '处理中'
                                              : _state.needsStatusQuery
                                                  ? '查询处理状态'
                                                  : '申请反水'))),
                        ])),
                ])));
      });
  Widget _body(BuildContext context) {
    final data = _state.data;
    if (data == null) return const MarkSixEmpty(message: '暂无当前汇总');
    final summary = markSixMap(data['summary']);
    final personal =
        markSixMap(data['personal'] ?? data['personalSummary'] ?? data['self']);
    return RefreshIndicator(
        onRefresh: () => _state.initialize(force: true),
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (personal.isNotEmpty)
                AgentSummaryCard(
                    title: '个人反水汇总',
                    summary: personal,
                    personal: true,
                    highlight: true),
              if (personal.isNotEmpty) const SizedBox(height: 12),
              if (summary.isNotEmpty)
                AgentSummaryCard(
                    title: '${summary['agentName'] ?? '当前汇总'}',
                    subtitle: [
                      if (summary['agentNo'] != null)
                        '用户编号：${summary['agentNo']}',
                      if (summary['dataTime'] != null)
                        '数据时间：${summary['dataTime']}'
                    ].join('  ·  '),
                    summary: summary,
                    highlight: true)
              else
                const MarkSixEmpty(message: '暂无当前汇总'),
            ]));
  }
}
