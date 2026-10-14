// 99CHAT-style My Downline: first-level family order and original card layout.
// New OpenIM improvements retained: full authorized snapshot, real avatars,
// local all-player search, global ranking, and lazy list rendering.
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
  String _keyword = '';
  String _sort = 'balance';
  bool _descending = true;
  AgentDescendantView _view = AgentDescendantView.team;

  List<Map<String, dynamic>>? _projectionSource;
  String? _projectionOwner;
  AgentDescendantsProjection? _projection;
  List<AgentDescendantVisibleRow>? _rowsCache;
  String? _rowsKey;

  bool get allowed =>
      widget.featureContext.sessionCurrent() &&
      widget.featureContext.capabilitiesCurrent() &&
      widget.featureContext.capabilities.markSix.canOpenAgent;

  AgentDescendantsProjection _indexForSnapshot() {
    final source = _state.items;
    if (!identical(_projectionSource, source) ||
        _projectionOwner != _state.ownerID || _projection == null) {
      _projectionSource = source;
      _projectionOwner = _state.ownerID;
      _projection = AgentDescendantsProjection(source, ownerID: _state.ownerID);
      _rowsCache = null;
      _rowsKey = null;
    }
    return _projection!;
  }

  List<AgentDescendantVisibleRow> _visibleRows(AgentDescendantsProjection index) {
    final key = '$_view|$_sort|$_descending|$_keyword';
    if (_rowsCache == null || _rowsKey != key) {
      _rowsKey = key;
      _rowsCache = index.visibleRows(view: _view, keyword: _keyword,
          sort: _sort, descending: _descending);
    }
    return _rowsCache!;
  }

  void _selectSort(String next) => setState(() {
        if (_sort == next) {
          _descending = !_descending;
        } else {
          _sort = next;
          _descending = true;
        }
      });

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

  Widget _sortChip(MarkSixStyle style, String key, String title) {
    final active = _sort == key;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ChoiceChip(
          selected: active,
          onSelected: (_) => _selectSort(key),
          label: SizedBox(
            width: double.infinity,
            child: Text(active ? '$title ${_descending ? '↓' : '↑'}' : title,
                textAlign: TextAlign.center, maxLines: 1,
                style: const TextStyle(fontSize: 12)),
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          selectedColor: style.primary.withValues(alpha: .12),
          backgroundColor: style.background,
          side: BorderSide(color: active ? style.primary : style.divider),
        ),
      ),
    );
  }

  Widget _header(MarkSixStyle style) => Container(
        color: style.surface,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _search,
            onChanged: (value) => setState(() => _keyword = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索昵称或编号',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _keyword.isEmpty ? null : IconButton(
                tooltip: '清空',
                onPressed: () {
                  _search.clear();
                  setState(() => _keyword = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
              filled: true,
              fillColor: style.background,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MarkSixStyle.radius),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Extra ranking is supplementary and does not replace the default
          // familiar 99CHAT family layout.
          Row(children: [
            TextButton.icon(
              onPressed: () => setState(() => _view = AgentDescendantView.team),
              icon: Icon(Icons.account_tree_outlined, size: 16,
                  color: _view == AgentDescendantView.team
                      ? style.primary : style.secondary),
              label: Text('团队层级', style: TextStyle(
                  fontSize: 13, color: _view == AgentDescendantView.team
                      ? style.primary : style.secondary,
                  fontWeight: _view == AgentDescendantView.team
                      ? FontWeight.w700 : FontWeight.normal)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() => _view = AgentDescendantView.ranking),
              icon: Icon(Icons.leaderboard_outlined, size: 16,
                  color: _view == AgentDescendantView.ranking
                      ? style.primary : style.secondary),
              label: Text('全局排名', style: TextStyle(
                  fontSize: 13, color: _view == AgentDescendantView.ranking
                      ? style.primary : style.secondary,
                  fontWeight: _view == AgentDescendantView.ranking
                      ? FontWeight.w700 : FontWeight.normal)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('排序', style: TextStyle(fontSize: 13, color: style.secondary)),
            const SizedBox(width: 8),
            _sortChip(style, 'balance', '总积分'),
            _sortChip(style, 'totalFlow', '总流水'),
            _sortChip(style, 'playerProfitLoss', '输赢'),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          final style = MarkSixStyle.of(context);
          final index = _indexForSnapshot();
          final rows = _visibleRows(index);
          final searching = _keyword.trim().isNotEmpty;
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
                          _header(style),
                          Expanded(
                            child: _state.loading && _state.items.isEmpty
                                ? Center(child: LoadingView.indicator())
                                : _state.error != null && _state.items.isEmpty
                                    ? MarkSixEmpty(
                                        message: _state.error!,
                                        onRetry: () => _state.load(force: true))
                                    : RefreshIndicator(
                                        onRefresh: () => _state.load(force: true),
                                        child: ListView.builder(
                                          physics: const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.all(20),
                                          // Retain the current full-snapshot,
                                          // visible-row-only rendering model.
                                          addAutomaticKeepAlives: false,
                                          itemCount: 1 + (rows.isEmpty ? 1 : rows.length) +
                                              (_state.error != null ? 1 : 0),
                                          itemBuilder: (context, position) {
                                            if (position == 0) {
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 12),
                                                child: Text(
                                                  searching
                                                      ? '找到 ${rows.length} 人（共 ${_state.total} 人）'
                                                      : '共 ${_state.total} 人',
                                                  style: TextStyle(fontSize: 13,
                                                      color: style.secondary),
                                                ),
                                              );
                                            }
                                            if (rows.isEmpty && position == 1) {
                                              return MarkSixEmpty(message: searching
                                                  ? '未找到匹配昵称或编号的下级'
                                                  : '当前暂无下级');
                                            }
                                            if (rows.isNotEmpty && position <= rows.length) {
                                              final (item, depth) = rows[position - 1];
                                              final direct = index.parentDescription(item);
                                              final parentID = '${item['directParentUserId'] ?? ''}'.trim();
                                              final unusualRoot = depth == 0 && parentID.isNotEmpty &&
                                                  parentID != _state.ownerID &&
                                                  _view == AgentDescendantView.team;
                                              final showDirect = !searching &&
                                                  _view == AgentDescendantView.team &&
                                                  (depth > 0 || unusualRoot);
                                              final rootWarning = unusualRoot &&
                                                  index.relationshipPath(item).contains('关系异常')
                                                  ? '上级关系异常，请核对' : direct;
                                              return AgentDescendantTile(
                                                avatars: _avatars,
                                                key: ValueKey(item['userId']),
                                                item: item,
                                                depth: depth,
                                                relationText: searching
                                                    ? index.relationshipPath(item)
                                                    : showDirect ? rootWarning : null,
                                                onTap: () {
                                                  if (!allowed || !_state.current) return;
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) => AgentDescendantDetailPage(
                                                        featureContext: widget.featureContext,
                                                        userID: '${item['userId']}',
                                                        initialItem: item,
                                                        loadedItems: _state.items,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            }
                                            return TextButton(
                                              onPressed: () => _state.load(force: true),
                                              child: Text(_state.error ?? '重试'),
                                            );
                                          },
                                        ),
                                      ),
                          ),
                        ]),
            ),
          );
        },
      );
}
