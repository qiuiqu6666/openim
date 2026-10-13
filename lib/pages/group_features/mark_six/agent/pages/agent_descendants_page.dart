// Layout adapted from 99chat agent_rebate_descendants_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../models/group_feature_context.dart';
import '../../data/mark_six_repository.dart';
import '../../widgets/mark_six_style.dart';
import '../data/agent_descendants_controller.dart';
import '../identity/agent_avatar_directory.dart';
import '../widgets/agent_descendant_tile.dart';
import 'agent_descendant_detail_page.dart';

class AgentDescendantsPage extends StatefulWidget {
  const AgentDescendantsPage({super.key, required this.featureContext});
  final GroupFeatureContext featureContext;
  @override
  State<AgentDescendantsPage> createState() => _AgentDescendantsPageState();
}

class _AgentDescendantsPageState extends State<AgentDescendantsPage> {
  late final _repository = MarkSixRepository(widget.featureContext);
  late final _state = AgentDescendantsController(_repository);
  late final _avatars = AgentAvatarDirectory(widget.featureContext);
  final _search = TextEditingController();
  String _keyword = '', _sort = 'balance';

  bool get allowed =>
      widget.featureContext.sessionCurrent() &&
      widget.featureContext.capabilitiesCurrent() &&
      widget.featureContext.capabilities.markSix.canOpenAgent;

  @override
  void initState() {
    super.initState();
    if (allowed) unawaited(_state.load());
  }

  @override
  void dispose() {
    _avatars.dispose();
    _state.dispose();
    _repository.close();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final style = MarkSixStyle.of(context);
        final rows = agentVisibleRows(_state.items,
            ownerID: _state.ownerID, keyword: _keyword, sort: _sort);
        return Scaffold(
            backgroundColor: style.background,
            appBar: markSixAppBar(context, '我的下级'),
            body: SafeArea(
                top: false,
                child: !allowed
                    ? const MarkSixEmpty(message: '你没有代理功能权限')
                    : !_state.current
                        ? const MarkSixEmpty(message: '登录状态已变更')
                        : Column(children: [
                            Container(
                                color: style.surface,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                child: Column(children: [
                                  TextField(
                                      controller: _search,
                                      onChanged: (value) =>
                                          setState(() => _keyword = value),
                                      textInputAction: TextInputAction.search,
                                      decoration: InputDecoration(
                                          hintText: '搜索昵称或编号',
                                          prefixIcon:
                                              const Icon(Icons.search_rounded),
                                          suffixIcon: _keyword.isEmpty
                                              ? null
                                              : IconButton(
                                                  tooltip: '清空',
                                                  onPressed: () {
                                                    _search.clear();
                                                    setState(
                                                        () => _keyword = '');
                                                  },
                                                  icon: const Icon(
                                                      Icons.close_rounded)),
                                          filled: true,
                                          fillColor: style.background,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 12, vertical: 8),
                                          border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(
                                                  MarkSixStyle.radius),
                                              borderSide: BorderSide.none))),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Text('排序',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: style.secondary)),
                                    const SizedBox(width: 8),
                                    for (final sort in const [
                                      ('balance', '总积分'),
                                      ('totalFlow', '总流水'),
                                      ('playerProfitLoss', '输赢')
                                    ])
                                      Expanded(
                                          child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 2),
                                              child: ChoiceChip(
                                                  label: SizedBox(
                                                      width: double.infinity,
                                                      child: Text(sort.$2,
                                                          textAlign: TextAlign.center)),
                                                  selected: _sort == sort.$1,
                                                  onSelected: (_) => setState(
                                                      () => _sort = sort.$1))))
                                  ]),
                                ])),
                            Expanded(
                                child: _state.loading && _state.items.isEmpty
                                    ? Center(child: LoadingView.indicator())
                                    : _state.error != null &&
                                            _state.items.isEmpty
                                        ? MarkSixEmpty(
                                            message: _state.error!,
                                            onRetry: () =>
                                                _state.load(force: true))
                                        : RefreshIndicator(
                                            onRefresh: () =>
                                                _state.load(force: true),
                                            child: ListView.builder(
                                                // Full snapshot, lazy visible rows.
                                                physics:
                                                    const AlwaysScrollableScrollPhysics(),
                                                padding:
                                                    const EdgeInsets.all(16),
                                                itemCount: 1 +
                                                    (rows.isEmpty ? 1 : rows.length) +
                                                    (_state.error != null ? 1 : 0),
                                                itemBuilder: (context, index) {
                                                  if (index == 0) {
                                                    return Padding(
                                                        padding: const EdgeInsets.only(bottom: 8),
                                                        child: Text(
                                                            _keyword.isEmpty
                                                                ? '共 ${_state.total} 人'
                                                                : '找到 ${rows.length} 人（共 ${_state.total} 人）',
                                                            style: TextStyle(
                                                                fontSize: 13,
                                                                color: style.secondary)));
                                                  }
                                                  if (rows.isEmpty && index == 1) {
                                                    return MarkSixEmpty(
                                                        message: _keyword.isEmpty
                                                            ? '当前暂无下级'
                                                            : '未找到匹配昵称或编号的下级');
                                                  }
                                                  if (rows.isNotEmpty && index <= rows.length) {
                                                    final row = rows[index - 1];
                                                    return AgentDescendantTile(
                                                        avatars: _avatars,
                                                        key: ValueKey(row.$1['userId']),
                                                        item: row.$1,
                                                        depth: row.$2,
                                                        onTap: () {
                                                          if (!allowed || !_state.current) return;
                                                          Navigator.of(context).push(MaterialPageRoute<void>(
                                                              builder: (_) => AgentDescendantDetailPage(
                                                                  featureContext: widget.featureContext,
                                                                  userID: '${row.$1['userId']}',
                                                                  initialItem: row.$1,
                                                                  loadedItems: _state.items)));
                                                        });
                                                  }
                                                  return TextButton(
                                                      onPressed: () => _state.load(force: true),
                                                      child: Text(_state.error ?? '重试'));
                                                }))),
                          ])));
      });
}
