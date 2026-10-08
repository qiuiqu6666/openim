import 'package:openim_common/openim_common.dart'
    show normalizePublicAccountSearch;
import '../../services/account_identity/sangong_account_identity_resolver.dart';
import '../../identity/widgets/sangong_identity_view.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../sangong_scope.dart';
import '../../models/sangong_admin_models.dart';
import '../../pages/sangong_user_detail_page.dart';
import '../data/report_query_controller.dart';
import '../widgets/report_widgets.dart';
import '../widgets/report_sections.dart';
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
  String _type = '', _searchValue = '';
  String? _searchError;
  bool _searching = false;
  int _searchRequest = 0;
  late final _accountSearch = SangongAccountIdentityResolver(
      isCurrent: () => mounted && _summary.current,
      scopeToken: () => _summary.scope.token);
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
    _accountSearch.close();
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
          if ((_tab == 1 || _tab == 2) && _searchValue.isNotEmpty)
            'search': _searchValue,
          if (_tab == 3 && _type.isNotEmpty) 'type': _type,
        });
    unawaited(_list!.load());
  }

  void _selectTab(int value) {
    if (value == _tab) return;
    _search.clear();
    _searchRequest++;
    _accountSearch.cancel();
    _searchValue = '';
    _searching = false;
    _searchError = null;
    _type = '';
    _list?.dispose();
    _list = null;
    setState(() => _tab = value);
    if (value != 0 && _summary.data.isNotEmpty) _makeList();
  }

  Future<void> _searchReports() async {
    if (!_summary.current) return;
    final request = ++_searchRequest;
    final input = _search.text.trim();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final term = normalizePublicAccountSearch(input) == null
          ? input
          : await _accountSearch.resolve(input, allowInternalUserId: false);
      if (!mounted ||
          !_summary.current ||
          request != _searchRequest ||
          term == null) {
        return;
      }
      setState(() {
        _searchValue = term;
        _makeList();
      });
    } catch (failure) {
      if (mounted && _summary.current && request == _searchRequest) {
        setState(() => _searchError = '$failure');
      }
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => _searching = false);
      }
    }
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
      ReportBalanceCard(s['currentBalance'], users: s['userCount']),
      const ReportSection('所选批次 · 经营结果', description: '仅统计有效结算，已冲正牌局不计入。'),
      ReportMetrics({
        '已结算下注': s['totalBets'],
        '庄家净额': reportSigned(s['bankerNet']),
        '抽水合计': s['rake'],
        '已入账返水': s['paidRebate'],
      }, hints: const {
        '已结算下注': '闲家下注总额',
        '庄家净额': '正数增加，负数减少',
        '抽水合计': '结算时向庄家收取',
        '已入账返水': '包含冲正后的净额',
      }),
      ReportMetrics({
        '牌局总数': s['roundCount'],
        '有效结算': s['settledCount'],
        '当前团队负责人': s['teamCount'],
        '账变记录': s['ledgerCount'],
      }),
      const ReportSection('现在正在进行',
          icon: Icons.schedule_outlined, description: '当前局实时数据，不随历史批次切换。'),
      ReportMetrics({
        '运行状态': reportPhase(state['status']),
        '当前有效下注': placed['grandTotal'],
      }),
      ExpansionTile(
        title: const Text('查看当前游戏规则'),
        children: [
          ReportMetrics({
            '门数': rules['doorCount'],
            '最小下注': rules['minBet'],
            '最大下注': rules['maxBet'] == 0 ? '不限' : rules['maxBet'],
            '庄抽水比例': rules['rakePercent'] == null
                ? null
                : '${rules['rakePercent']}%',
          })
        ],
      ),
      const ReportSection('积分为什么变化',
          icon: Icons.receipt_long_outlined,
          description: '所选批次的账变合计。正数为增加，负数为减少。'),
      ...(data['ledgerTypes'] as List? ?? []).whereType<Map>().map((row) =>
          ReportCard(
              child: ListTile(
                  title: Text(ledgerLabel(row['type'])),
                  subtitle: Text('${row['count']} 笔 · 点击查看记录'),
                  trailing: Text(reportSigned(row['amount']),
                      style: Theme.of(context).textTheme.titleMedium),
                  onTap: () => unawaited(SangongReportDetailPage.open(context,
                      title: ledgerLabel(row['type']),
                      resource: 'ledger',
                      listKey: 'entries',
                      query: {..._batchQuery, 'type': row['type']}))))),
      if ((data['ledgerTypes'] as List? ?? []).isEmpty)
        const ReportNotice('所选批次暂无账变记录。'),
      if (_summary.error != null) ReportNotice(_summary.error!),
      const SizedBox(height: 20),
    ]);
  }

  Widget _userTile(Map<String, dynamic> row, {required bool team}) {
    final parent = row['parent'] is Map ? row['parent'] as Map : const {};
    return ReportCard(
        child: ExpansionTile(
      leading: SangongIMAvatar(
          userID: '${row['imUserId'] ?? ''}', nickname: reportUser(row)),
      title: SangongUserName(
          userID: '${row['imUserId'] ?? ''}', nickname: reportUser(row)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SangongPublicAccount(
            userID: '${row['imUserId'] ?? ''}',
            style: Theme.of(context).textTheme.bodySmall),
        Text(
            team
                ? '直属下级 ${reportValue(row['childrenCount'])} 人'
                : '当前积分 ${reportValue(row['balance'])}',
            style: Theme.of(context).textTheme.titleSmall),
        Text(
            team
                ? '点击展开负责人信息，或查看团队明细'
                : '本批次游戏变动 ${reportSigned(row['profitLoss'])}',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: SangongPublicAccount(userID: '${row['imUserId'] ?? ''}')),
        const ReportNotice('当前积分为实时余额；批次最后积分为该批次最后一次账变后的余额。游戏变动包含下注扣款、退款及结算。'),
        ReportMetrics({
          '批次最后积分': row['closingBalance'],
          '闲家流水': row['playerTurnover'],
          '庄家流水': row['bankerTurnover'],
          '上分 / 划入': row['totalUp'],
          '下分 / 划出': row['totalDown'],
          '游戏积分变动': reportSigned(row['profitLoss']),
          '已入账返水': row['paidRebate'],
          '直属下级': row['childrenCount'],
          '上级': parent['nickname'] ?? '无',
        }),
        Wrap(children: [
          TextButton(
              onPressed: () => _openUser(row), child: const Text('用户详情')),
          TextButton(
              onPressed: () => _openLedger(row), child: const Text('查看全部账变')),
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
                    hintText: '输入昵称或完整公开账号',
                    prefixIcon: const Icon(Icons.person_search_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                        tooltip: '搜索',
                        icon: const Icon(Icons.search),
                        onPressed: list.busy || _searching
                            ? null
                            : () {
                                unawaited(_searchReports());
                              })),
                onSubmitted: list.busy
                    ? null
                    : (_) {
                        unawaited(_searchReports());
                      })),
      if (_searching) const LinearProgressIndicator(),
      if (_searchError != null) ReportNotice(_searchError!),
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
      if (_tab == 2) const ReportNotice('每张卡片是一位团队负责人。进入团队明细可查看下级成员及团队汇总。'),
      ...list.rows.map((row) {
        if (_tab == 1 || _tab == 2) return _userTile(row, team: _tab == 2);
        if (_tab == 3) return ReportLedgerTile(row);
        return ReportCard(
            child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.casino_outlined)),
                title: Text('第${row['periodNo']}期'),
                subtitle: Text(
                    '${reportPhase(row['status'])} · 庄门 ${row['bankerDoor'] ?? '—'}\n${reportTime(row['settledAt'] ?? row['betWindowOpenAt'])}'),
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
                              Text(
                                  _runtime.featureContext.groupName.isEmpty
                                      ? '当前游戏群'
                                      : _runtime.featureContext.groupName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 8),
                              Text('查看范围',
                                  style: Theme.of(context).textTheme.bodySmall),
                              DropdownButton<int>(
                                  isExpanded: true,
                                  value: _selection,
                                  items: [
                                    const DropdownMenuItem(
                                        value: 0, child: Text('最新批次')),
                                    ..._sessions.rows.map((row) => DropdownMenuItem(
                                        value: row['id'] as int,
                                        child: Text(
                                            '${row['businessDate']} · 批次 ${row['batchNo']} · ${reportPhase(row['status'])}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis))),
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
                                  _summary.data['session'] is Map
                                      ? '批次 ${(_summary.data['session'] as Map)['batchNo']} · 更新 ${reportTime(_summary.data['asOf'])}'
                                      : '更新 ${reportTime(_summary.data['asOf'])}',
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
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                const [
                                  '先看全群经营结果，再按需查询明细',
                                  '点击用户展开积分、流水和上下分',
                                  '查负责人、下级成员和团队汇总',
                                  '逐笔核对积分增减，展开查看操作信息',
                                  '点击牌局查看开奖和每位用户结算',
                                ][_tab],
                                style: Theme.of(context).textTheme.bodySmall))),
                    Expanded(
                        child: RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.only(
                                    bottom:
                                        MediaQuery.paddingOf(context).bottom +
                                            24),
                                children: [
                                  _tab == 0 ? _overview() : _listBody()
                                ]))),
                  ]),
          ));
}
