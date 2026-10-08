import 'dart:async';
import 'package:flutter/material.dart';
import '../../sangong_scope.dart';
import '../../models/sangong_admin_models.dart';
import '../../pages/sangong_user_detail_page.dart';
import '../data/report_query_controller.dart';
import '../widgets/report_widgets.dart';
import 'report_detail_page.dart';

class SangongReportCenterPage extends StatefulWidget {
  const SangongReportCenterPage({super.key});
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push<void>(SangongPageRoute(
          context: context,
          settings: const RouteSettings(name: 'sangong_report_center'),
          builder: (_) => const SangongReportCenterPage()));
  @override
  State<SangongReportCenterPage> createState() =>
      _SangongReportCenterPageState();
}

class _SangongReportCenterPageState extends State<SangongReportCenterPage> {
  late final _runtime = SangongScope.read(context);
  late final _summary = ReportQueryController(_runtime, 'management-summary');
  late final _sessions =
      ReportQueryController(_runtime, 'sessions', listKey: 'sessions');
  ReportQueryController? _list;
  final _search = TextEditingController();
  int _tab = 0, _selection = 0;
  String _type = '';
  int? get _sessionId {
    final session = _summary.data['session'];
    return session is Map ? session['id'] as int? : null;
  }

  Map<String, dynamic> get _batchQuery =>
      {if (_sessionId != null) 'sessionId': _sessionId};
  @override
  void initState() {
    super.initState();
    _summary.addListener(_summaryChanged);
    unawaited(_summary.load());
    unawaited(_sessions.load());
  }

  void _summaryChanged() {
    if (!mounted) return;
    if (!_summary.busy &&
        _summary.data.isNotEmpty &&
        _tab != 0 &&
        _list == null) {
      _makeList();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _summary.removeListener(_summaryChanged);
    _summary.dispose();
    _sessions.dispose();
    _list?.dispose();
    _search.dispose();
    super.dispose();
  }

  void _makeList() {
    _list?.dispose();
    const resources = [
      '',
      'management-users',
      'management-teams',
      'ledger',
      'rounds'
    ];
    const keys = ['', 'users', 'users', 'entries', 'rounds'];
    _list = ReportQueryController(_runtime, resources[_tab],
        listKey: keys[_tab],
        query: {
          ..._batchQuery,
          if ((_tab == 1 || _tab == 2) && _search.text.trim().isNotEmpty)
            'search': _search.text.trim(),
          if (_tab == 3 && _type.isNotEmpty) 'type': _type,
        });
    unawaited(_list!.load());
  }

  void _selectTab(int value) {
    if (value == _tab) return;
    _search.clear();
    _type = '';
    _list?.dispose();
    _list = null;
    setState(() => _tab = value);
    if (value != 0 && _summary.data.isNotEmpty) _makeList();
  }

  Future<void> _refresh() async {
    _list?.dispose();
    _list = null;
    setState(() {});
    await _summary.replaceQuery({if (_selection > 0) 'sessionId': _selection});
  }

  void _openUser(Map<String, dynamic> row) =>
      unawaited(Navigator.of(context).push<void>(SangongPageRoute(
          context: context,
          builder: (_) => SangongUserDetailPage(
              user: SangongAdminUserReport.fromJson(row),
              initialSessionId: _sessionId))));
  void _openLedger(Map<String, dynamic> row) =>
      unawaited(SangongReportDetailPage.open(context,
          title: '${reportUser(row)} · 账变',
          resource: 'ledger',
          listKey: 'entries',
          query: {..._batchQuery, 'imUserId': row['imUserId']}));
  void _openTeam(Map<String, dynamic> row) =>
      unawaited(SangongReportDetailPage.open(context,
          title: '${reportUser(row)} · 团队',
          resource: 'team',
          listKey: 'members',
          query: {..._batchQuery, 'imUserId': row['imUserId']}));

  Widget _overview() {
    final data = _summary.data;
    if (data.isEmpty) {
      return _summary.busy
          ? const Center(child: CircularProgressIndicator())
          : ListTile(
              title: Text(_summary.error ?? '暂无报表'),
              trailing:
                  TextButton(onPressed: _refresh, child: const Text('重试')));
    }
    final s = data['summary'] as Map;
    final state = data['state'] is Map ? data['state'] as Map : const {};
    final placed = state['placed'] is Map ? state['placed'] as Map : const {};
    final rules =
        state['settings'] is Map ? state['settings'] as Map : const {};
    return Column(children: [
      ReportMetrics({
        '登记用户': s['userCount'],
        '当前积分总额': s['currentBalance'],
        '团队负责人': s['teamCount'],
        '批次牌局数': s['roundCount'],
        '有效结算局': s['settledCount'],
        '已结算闲家下注': s['totalBets'],
        '庄家净额': s['bankerNet'],
        '庄家抽水': s['rake'],
        '已入账返水（净额）': s['paidRebate'],
        '账变笔数': s['ledgerCount']
      }),
      const ListTile(
          title: Text('当前运行状态'), subtitle: Text('以下为当前局实时快照，不受历史批次选择影响。')),
      ReportMetrics({
        '状态': reportPhase(state['status']),
        '当前有效下注': placed['grandTotal'],
        '门数': rules['doorCount'],
        '最小下注': rules['minBet'],
        '最大下注（0不限）': rules['maxBet'],
        '庄抽水 %': rules['rakePercent']
      }),
      const ListTile(
          title: Text('所选批次账变分类'),
          subtitle: Text('金额为该类型的实际账变合计，包含退款和冲正；当前积分不是历史期末积分。')),
      ...(data['ledgerTypes'] as List? ?? []).whereType<Map>().map((row) =>
          ListTile(
              title: Text(ledgerLabel(row['type'])),
              subtitle: Text('${row['count']}笔'),
              trailing: Text(reportValue(row['amount'])))),
      if (_summary.error != null) ListTile(title: Text(_summary.error!)),
    ]);
  }

  Widget _userTile(Map<String, dynamic> row, {required bool team}) {
    final parent = row['parent'] is Map ? row['parent'] as Map : const {};
    return Card(
        child: ExpansionTile(
      title: Text(reportUser(row)),
      subtitle: Text('当前积分 ${reportValue(row['balance'])}\n${row['imUserId']}'),
      children: [
        ReportMetrics({
          '批次期末积分': row['closingBalance'],
          '闲家流水': row['playerTurnover'],
          '庄家流水': row['bankerTurnover'],
          '上分 / 划入': row['totalUp'],
          '下分 / 划出': row['totalDown'],
          '游戏账变净额': row['profitLoss'],
          '已入账返水': row['paidRebate'],
          '直属下级': row['childrenCount'],
          '上级': parent['nickname'] ?? '无',
        }),
        Wrap(children: [
          TextButton(
              onPressed: () => _openUser(row), child: const Text('用户详情')),
          TextButton(
              onPressed: () => _openLedger(row), child: const Text('完整账变')),
          TextButton(
              onPressed: () => _openTeam(row),
              child: Text(team ? '查看团队明细' : '查看下级团队')),
        ])
      ],
    ));
  }

  Widget _listBody() {
    final list = _list;
    if (list == null) {
      return _summary.error == null
          ? const Center(child: CircularProgressIndicator())
          : Text(_summary.error!);
    }
    return Column(children: [
      if (_tab == 1 || _tab == 2)
        Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
                controller: _search,
                decoration: InputDecoration(
                    labelText: '搜索昵称或完整用户ID',
                    suffixIcon: IconButton(
                        tooltip: '搜索',
                        icon: const Icon(Icons.search),
                        onPressed: list.busy
                            ? null
                            : () {
                                setState(_makeList);
                              })),
                onSubmitted: list.busy
                    ? null
                    : (_) {
                        setState(_makeList);
                      })),
      if (_tab == 3)
        Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: '账变类型'),
                items: ledgerKinds.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: list.busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _type = value;
                          _makeList();
                        });
                      })),
      if (_tab == 2)
        const ListTile(subtitle: Text('列出有直属下级的负责人；点击查看完整下级团队或仅直属成员。')),
      ...list.rows.map((row) {
        if (_tab == 1 || _tab == 2) return _userTile(row, team: _tab == 2);
        if (_tab == 3) return ReportLedgerTile(row);
        return Card(
            child: ListTile(
                title: Text(
                    '第${row['periodNo']}期 · ${reportPhase(row['status'])}'),
                subtitle: Text(
                    '庄门 ${row['bankerDoor']} · 局号 ${row['id']}\n${reportTime(row['settledAt'] ?? row['betWindowOpenAt'])}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(SangongReportDetailPage.open(context,
                    title: '第${row['periodNo']}期明细',
                    resource: 'management-round',
                    query: {'roundId': row['id']}))));
      }),
      ReportPagingFooter(list),
    ]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation:
          Listenable.merge([_summary, _sessions, if (_list != null) _list!]),
      builder: (_, __) => Scaffold(
            appBar: AppBar(title: const Text('报表中心'), actions: [
              IconButton(
                  tooltip: '刷新报表',
                  onPressed: _summary.busy ? null : _refresh,
                  icon: const Icon(Icons.refresh))
            ]),
            body: !_summary.current
                ? const Center(child: Text('当前群或管理权限已变化，请重新进入'))
                : Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_summary.data['hallName'] ?? '当前厅'}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              SelectableText(
                                  '当前群 ${_runtime.featureContext.groupID}',
                                  style: Theme.of(context).textTheme.bodySmall),
                              DropdownButton<int>(
                                  isExpanded: true,
                                  value: _selection,
                                  items: [
                                    const DropdownMenuItem(
                                        value: 0, child: Text('最新经营批次')),
                                    ..._sessions.rows.map((row) => DropdownMenuItem(
                                        value: row['id'] as int,
                                        child: Text(
                                            '${row['batchNo']} · ${row['businessDate']} · ${reportPhase(row['status'])}'))),
                                    if (_sessions.cursor > 0)
                                      const DropdownMenuItem(
                                          value: -1, child: Text('加载更早批次…'))
                                  ],
                                  onChanged: _summary.busy
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          if (value == -1) {
                                            unawaited(
                                                _sessions.load(more: true));
                                            return;
                                          }
                                          setState(() => _selection = value);
                                          unawaited(_refresh());
                                        }),
                              if (_sessions.error != null)
                                TextButton(
                                    onPressed: () => _sessions.load(),
                                    child: Text(
                                        '批次列表加载失败，点击重试：${_sessions.error}')),
                              Text(
                                  '统计按经营批次；更新于 ${reportTime(_summary.data['asOf'])}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ])),
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: List.generate(
                                5,
                                (index) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: ChoiceChip(
                                        label: Text(const [
                                          '总览',
                                          '用户',
                                          '团队',
                                          '账变',
                                          '牌局'
                                        ][index]),
                                        selected: _tab == index,
                                        onSelected: (_) =>
                                            _selectTab(index)))))),
                    Expanded(
                        child: RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  _tab == 0 ? _overview() : _listBody()
                                ]))),
                  ]),
          ));
}
