import 'dart:async';
import 'package:flutter/material.dart';
import '../../sangong_scope.dart';
import '../../models/sangong_admin_models.dart';
import '../../pages/sangong_user_detail_page.dart';
import '../data/report_query_controller.dart';
import '../widgets/report_widgets.dart';

class SangongReportDetailPage extends StatefulWidget {
  const SangongReportDetailPage(
      {super.key,
      required this.title,
      required this.resource,
      this.listKey,
      required this.query});
  final String title, resource;
  final String? listKey;
  final Map<String, dynamic> query;
  static Future<void> open(BuildContext context,
          {required String title,
          required String resource,
          String? listKey,
          required Map<String, dynamic> query}) =>
      Navigator.of(context).push<void>(SangongPageRoute(
          context: context,
          builder: (_) => SangongReportDetailPage(
              title: title,
              resource: resource,
              listKey: listKey,
              query: query)));
  @override
  State<SangongReportDetailPage> createState() =>
      _SangongReportDetailPageState();
}

class _SangongReportDetailPageState extends State<SangongReportDetailPage> {
  late final _controller = ReportQueryController(
      SangongScope.read(context), widget.resource,
      listKey: widget.listKey, query: widget.query);
  bool _direct = false;
  String _type = '';
  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openUser(Map<String, dynamic> user) {
    final id = user['imUserId'];
    if (id is! String || id.isEmpty) return;
    unawaited(Navigator.of(context).push<void>(SangongPageRoute(
        context: context,
        builder: (_) => SangongUserDetailPage(
            user: SangongAdminUserReport.fromJson(user),
            initialSessionId: widget.query['sessionId'] as int?))));
  }

  Widget _team(Map<String, dynamic> data) {
    final summary = data['teamSummary'];
    final root = data['self'];
    return Column(children: [
      SwitchListTile(
          title: const Text('仅直属下级'),
          value: _direct,
          onChanged: _controller.busy
              ? null
              : (value) {
                  setState(() => _direct = value);
                  unawaited(_controller
                      .replaceQuery({...widget.query, 'direct': value}));
                }),
      const ListTile(
          title: Text('下级团队汇总'),
          subtitle: Text('不包含团队负责人本人；不同上级团队可能重叠，不可相加作为全群总额。')),
      if (summary is Map)
        ReportMetrics({
          '成员数': summary['memberCount'],
          '直属成员': summary['directMemberCount'],
          '批次余额': summary['totalBalance'],
          '闲家流水': summary['playerTurnover'],
          '庄家流水': summary['bankerTurnover'],
          '上分 / 划入': summary['totalUp'],
          '下分 / 划出': summary['totalDown'],
          '游戏账变净额': summary['profitLoss'],
          '已入账返水': summary['totalRebate'],
        }),
      if (root is Map)
        ListTile(
            title: Text('负责人：${reportUser(Map<String, dynamic>.from(root))}'),
            subtitle: Text(
                '本人批次余额 ${reportValue(root['balance'])} · 当前余额 ${reportValue(root['currentBalance'])}'),
            onTap: () => _openUser(Map<String, dynamic>.from(root))),
      ..._controller.rows.map((row) => Card(
          child: ListTile(
              title: Text(reportUser(row)),
              subtitle: Text(
                  '层级 ${row['levelNo']} · 上级编号 ${row['parentUserId']}\n批次余额 ${reportValue(row['balance'])} · 当前余额 ${reportValue(row['currentBalance'])}\n闲家 ${reportValue(row['playerTurnover'])} · 庄家 ${reportValue(row['bankerTurnover'])} · 返水 ${reportValue(row['batchRebate'])}'),
              onTap: () => _openUser(row)))),
    ]);
  }

  Widget _round(Map<String, dynamic> data) {
    final round = data['round'] is Map ? data['round'] as Map : const {};
    final settlement =
        data['settlement'] is Map ? data['settlement'] as Map : const {};
    final draws = data['draws'] is List ? data['draws'] as List : const [];
    return Column(children: [
      ReportMetrics({
        '期号': round['periodNo'],
        '状态': reportPhase(round['status']),
        '庄门': round['bankerDoor'],
        '庄家': settlement['bankerNickname'] ?? round['bankerUserId'],
        '总下注': settlement['grandTotal'],
        '抽水': settlement['rake'],
        '庄净': settlement['bankerNet'],
        '结算时间': reportTime(round['settledAt'])
      }),
      ...draws.whereType<Map>().map((draw) => ListTile(
          title: Text('${draw['door']}门'),
          trailing: Text(draw['amountHundredths'] is num
              ? ((draw['amountHundredths'] as num) / 100).toStringAsFixed(2)
              : '—'))),
      for (final key in ['bankers', 'players'])
        if (settlement[key] is List) ...[
          ListTile(title: Text(key == 'bankers' ? '庄家 / 合庄明细' : '闲家明细')),
          ...(settlement[key] as List).whereType<Map>().map((item) => Card(
                  child: ListTile(
                title: Text(reportUser(Map<String, dynamic>.from(item))),
                subtitle: Text(
                    '结算前 ${reportValue(item['balanceBefore'])} → 结算后 ${reportValue(item['balanceAfter'])}\n下注 / 流水 ${reportValue(item['totalBet'] ?? item['betShare'])} · 净额 ${reportValue(item['net'])}\n${key == 'bankers' ? '投入 ${reportValue(item['amount'])} · 占比 ${reportValue(item['sharePercent'])}% · 分摊抽水 ${reportValue(item['rakeShare'])}' : '各门下注 ${reportValue(item['doorBets'])}'}'),
                onTap: () => unawaited(SangongReportDetailPage.open(context,
                    title:
                        '${reportUser(Map<String, dynamic>.from(item))} · 账变',
                    resource: 'ledger',
                    listKey: 'entries',
                    query: {
                      'sessionId': round['sessionId'],
                      if (item['imUserId'] is String)
                        'imUserId': item['imUserId']
                    })),
              ))),
        ],
      if (settlement.isEmpty)
        const ListTile(
            title: Text('本局暂无有效结算明细'), subtitle: Text('未结算或已作废的牌局不会显示为已结算。')),
    ]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Scaffold(
            appBar: AppBar(title: Text(widget.title), actions: [
              IconButton(
                  tooltip: '刷新',
                  onPressed: _controller.busy ? null : () => _controller.load(),
                  icon: const Icon(Icons.refresh))
            ]),
            body: !_controller.current
                ? const Center(child: Text('当前群或管理权限已变化，请重新进入'))
                : RefreshIndicator(
                    onRefresh: () => _controller.load(),
                    child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          if (widget.resource == 'team')
                            _team(_controller.data),
                          if (widget.resource == 'management-round')
                            _round(_controller.data),
                          if (widget.resource == 'ledger') ...[
                            Padding(
                                padding: const EdgeInsets.all(16),
                                child: DropdownButtonFormField<String>(
                                    initialValue: _type,
                                    decoration: const InputDecoration(
                                        labelText: '账变类型'),
                                    items: ledgerKinds.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key, child: Text(e.value)))
                                        .toList(),
                                    onChanged: _controller.busy
                                        ? null
                                        : (value) {
                                            if (value == null) return;
                                            setState(() => _type = value);
                                            unawaited(_controller.replaceQuery({
                                              ...widget.query,
                                              if (value.isNotEmpty)
                                                'type': value
                                            }));
                                          })),
                            ..._controller.rows.map(ReportLedgerTile.new),
                          ],
                          if (widget.listKey != null)
                            ReportPagingFooter(_controller)
                          else if (_controller.busy)
                            const Center(child: CircularProgressIndicator())
                          else if (_controller.error != null)
                            ListTile(
                                title: Text(_controller.error!),
                                trailing: TextButton(
                                    onPressed: () => _controller.load(),
                                    child: const Text('重试'))),
                        ])),
          ));
}
