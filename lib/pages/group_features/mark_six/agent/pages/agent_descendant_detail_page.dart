// Layout adapted from 99chat agent_rebate_descendant_detail_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../models/group_feature_context.dart';
import '../../data/mark_six_repository.dart';
import '../../widgets/mark_six_style.dart';
import '../data/agent_query_controller.dart';
import '../widgets/agent_descendant_tile.dart';
import 'agent_descendant_history_page.dart';

class AgentDescendantDetailPage extends StatefulWidget {
  const AgentDescendantDetailPage(
      {super.key,
      required this.featureContext,
      required this.userID,
      this.initialItem,
      this.loadedItems = const []});
  final GroupFeatureContext featureContext;
  final String userID;
  final Map<String, dynamic>? initialItem;
  final List<Map<String, dynamic>> loadedItems;
  @override
  State<AgentDescendantDetailPage> createState() =>
      _AgentDescendantDetailPageState();
}

class _AgentDescendantDetailPageState extends State<AgentDescendantDetailPage> {
  late final _repository = MarkSixRepository(widget.featureContext);
  late final _state = AgentQueryController(_repository);
  bool get allowed =>
      widget.featureContext.sessionCurrent() &&
      widget.featureContext.capabilitiesCurrent() &&
      widget.featureContext.capabilities.markSix.canOpenAgent;
  Future<void> _load({bool force = false}) =>
      _state.load('/me/agent/descendants/${Uri.encodeComponent(widget.userID)}',
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final style = MarkSixStyle.of(context);
        final item = markSixMap(_state.data?['item']);
        return Scaffold(
            backgroundColor: style.background,
            appBar: markSixAppBar(
                context, '${widget.initialItem?['displayName'] ?? '下级详情'}',
                actions: [
                  if (allowed &&
                      widget.featureContext.capabilities.markSix
                          .canViewRebateHistory)
                    IconButton(
                        tooltip: '历史记录',
                        onPressed: () {
                          if (!_state.current) return;
                          Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => AgentDescendantHistoryPage(
                                  featureContext: widget.featureContext,
                                  userID: widget.userID)));
                        },
                        icon: const Icon(Icons.history_rounded))
                ]),
            body: SafeArea(
                top: false,
                child: !allowed
                    ? const MarkSixEmpty(message: '你没有代理功能权限')
                    : !_state.current
                        ? const MarkSixEmpty(message: '登录状态已变更')
                        : _state.loading
                            ? Center(child: LoadingView.indicator())
                            : _state.error != null
                                ? MarkSixEmpty(
                                    message: _state.error!,
                                    onRetry: () => _load(force: true))
                                : item.isEmpty ||
                                        '${item['userId']}' != widget.userID
                                    ? const MarkSixEmpty(
                                        message: '下级资料缺失或上下文不匹配')
                                    : RefreshIndicator(
                                        onRefresh: () => _load(force: true),
                                        child: ListView(
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            padding: const EdgeInsets.all(16),
                                            children: [
                                              Container(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  decoration: BoxDecoration(
                                                      color: style.surface,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              MarkSixStyle
                                                                  .radius),
                                                      border: Border.all(
                                                          color:
                                                              style.divider)),
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(children: [
                                                          AvatarView(
                                                              width: 48,
                                                              height: 48,
                                                              text:
                                                                  '${item['displayName'] ?? item['playerNo']}',
                                                              url:
                                                                  '${item['avatarUrl'] ?? ''}'),
                                                          const SizedBox(
                                                              width: 12),
                                                          Expanded(
                                                              child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                Text(
                                                                    '${item['displayName'] ?? item['playerNo']}',
                                                                    style: TextStyle(
                                                                        fontSize:
                                                                            17,
                                                                        color: style
                                                                            .text,
                                                                        fontWeight:
                                                                            FontWeight.w700)),
                                                                const SizedBox(
                                                                    height: 4),
                                                                Text(
                                                                    '用户编号：${item['playerNo'] ?? '—'}',
                                                                    style: TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: style
                                                                            .secondary)),
                                                              ]))
                                                        ]),
                                                        const SizedBox(
                                                            height: 16),
                                                        _metrics(context, item),
                                                      ])),
                                              const SizedBox(height: 12),
                                              Container(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  decoration: BoxDecoration(
                                                      color: style.surface,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              MarkSixStyle
                                                                  .radius)),
                                                  child: Wrap(
                                                      spacing: 24,
                                                      runSpacing: 8,
                                                      children: [
                                                        Text(
                                                            '直属下级：${_state.data?['directChildCount'] ?? '—'}'),
                                                        Text(
                                                            '全部下级：${_state.data?['descendantCount'] ?? '—'}'),
                                                        Text(
                                                            '团队上分：${markSixAmount(_state.data?['teamTotalUp'])}'),
                                                        Text(
                                                            '团队下分：${markSixAmount(_state.data?['teamTotalDown'])}'),
                                                      ])),
                                              const SizedBox(height: 16),
                                              const Text('直属下级',
                                                  style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              const SizedBox(height: 12),
                                              for (final child in widget
                                                  .loadedItems
                                                  .where((row) =>
                                                      '${row['directParentUserId']}' ==
                                                          widget.userID &&
                                                      '${row['userId']}' !=
                                                          widget.userID))
                                                AgentDescendantTile(
                                                    item: child,
                                                    onTap: () {
                                                      if (!_state.current) {
                                                        return;
                                                      }
                                                      Navigator.of(context).push(MaterialPageRoute<
                                                              void>(
                                                          builder: (_) => AgentDescendantDetailPage(
                                                              featureContext: widget
                                                                  .featureContext,
                                                              userID:
                                                                  '${child['userId']}',
                                                              initialItem:
                                                                  child,
                                                              loadedItems: widget
                                                                  .loadedItems)));
                                                    }),
                                              if (widget.loadedItems.every((row) =>
                                                  '${row['directParentUserId']}' !=
                                                  widget.userID))
                                                const MarkSixEmpty(
                                                    message: '暂无已加载的直属下级'),
                                            ]))));
      });
  Widget _metrics(BuildContext context, Map<String, dynamic> item) {
    final style = MarkSixStyle.of(context);
    const metrics = [
      ('总积分', 'balance'),
      ('总流水', 'totalFlow'),
      ('已用流水', 'usedFlow'),
      ('剩余流水', 'remainingFlow'),
      ('玩家输赢', 'playerProfitLoss'),
      ('总上分', 'totalUp'),
      ('总下分', 'totalDown'),
      ('已反水', 'totalRebated'),
      ('待反水', 'pendingRebate'),
      ('反水比例', 'rebateRate')
    ];
    return LayoutBuilder(
        builder: (context, constraints) =>
            Wrap(spacing: 12, runSpacing: 16, children: [
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: style.text)),
                        ]))
            ]));
  }
}
