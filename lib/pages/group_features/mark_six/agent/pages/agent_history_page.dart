// Layout adapted from 99chat agent_rebate_history_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../models/group_feature_context.dart';
import '../../data/mark_six_repository.dart';
import '../../widgets/mark_six_style.dart';
import '../data/agent_query_controller.dart';
import '../data/agent_history_export.dart';
import '../models/agent_date_range.dart';
import '../widgets/agent_date_range_picker.dart';
import '../widgets/agent_summary_card.dart';

class AgentHistoryPage extends StatefulWidget {
  const AgentHistoryPage(
      {super.key, required this.featureContext, this.initialRange});
  final GroupFeatureContext featureContext;
  final AgentRebateDateRange? initialRange;
  @override
  State<AgentHistoryPage> createState() => _AgentHistoryPageState();
}

class _AgentHistoryPageState extends State<AgentHistoryPage> {
  late final _repository = MarkSixRepository(widget.featureContext);
  late final _state = AgentQueryController(_repository);
  late final _export = AgentHistoryExport(_repository);
  late AgentRebateDateRange _range =
      widget.initialRange ?? AgentRebateDateRange.today();
  bool _personal = false;
  bool get allowed =>
      widget.featureContext.sessionCurrent() &&
      widget.featureContext.capabilitiesCurrent() &&
      widget.featureContext.capabilities.markSix.canViewRebateHistory;
  @override
  void initState() {
    super.initState();
    if (allowed) unawaited(_load());
  }

  @override
  void dispose() {
    _state.dispose();
    _export.dispose();
    _repository.close();
    super.dispose();
  }

  Future<void> _load({bool force = false}) => _state.load(
      _personal
          ? '/me/agent/rebate/personal-history'
          : '/me/agent/rebate/history',
      query: {'startDate': _range.startApiValue, 'endDate': _range.endApiValue},
      force: force);
  Future<void> _pickRange() async {
    final range =
        await showAgentRebateDateRangePicker(context, initialRange: _range);
    if (!mounted || !allowed || range == null) return;
    setState(() => _range = range);
    await _load();
  }

  Future<void> _download() async {
    if (!allowed || !_state.current || _export.busy) return;
    final saved = await _export.save(_range);
    if (mounted && _state.current && saved) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('历史记录已下载')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([_state, _export]),
      builder: (context, _) {
        final style = MarkSixStyle.of(context);
        return Scaffold(
            backgroundColor: style.background,
            appBar:
                markSixAppBar(context, _personal ? '个人历史' : '团队历史', actions: [
              if (!_personal && allowed)
                TextButton.icon(
                    onPressed:
                        _state.loading || _export.busy ? null : _download,
                    icon: _export.busy
                        ? LoadingView.indicator(size: 20)
                        : const Icon(Icons.download_rounded, size: 20),
                    label: const Text('下载'))
            ]),
            body: SafeArea(
                top: false,
                child: Column(children: [
                  AgentDateRangeBar(
                      range: _range,
                      onPressed: allowed && !_state.loading && !_export.busy
                          ? _pickRange
                          : null),
                  if (_export.error != null)
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_export.error!,
                            style: TextStyle(color: style.error))),
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
                                      : _body(context)),
                ])),
            bottomNavigationBar: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: FilledButton.icon(
                        onPressed: allowed && !_state.loading && !_export.busy
                            ? () async {
                                setState(() => _personal = !_personal);
                                await _load();
                              }
                            : null,
                        icon: Icon(_personal
                            ? Icons.groups_2_outlined
                            : Icons.person_outline_rounded),
                        label: Text(_personal ? '团队历史' : '个人历史')))));
      });
  Widget _body(BuildContext context) {
    final data = _state.data;
    final days = markSixRows(data?['days'])
      ..sort(
          (a, b) => '${b['businessDate']}'.compareTo('${a['businessDate']}'));
    return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: days.isEmpty ? 1 : days.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (days.isEmpty) {
                return const MarkSixEmpty(message: '所选日期暂无反水记录');
              }
              final summary =
                  index == 0 ? markSixMap(data?['total']) : days[index - 1];
              return AgentSummaryCard(
                  title:
                      index == 0 ? '合计' : '${days[index - 1]['businessDate']}',
                  subtitle: index == 0
                      ? '${_range.startApiValue} — ${_range.endApiValue}'
                      : null,
                  summary: summary,
                  highlight: index == 0,
                  history: true,
                  showCounts: !_personal);
            }));
  }
}
