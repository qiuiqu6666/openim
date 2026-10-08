import '../../identity/widgets/sangong_identity_view.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../sangong_scope.dart';
import '../../models/sangong_admin_models.dart';
import '../../pages/sangong_user_detail_page.dart';
import '../data/report_query_controller.dart';
import '../widgets/report_widgets.dart';
import '../widgets/report_sections.dart';

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
  late String _type = widget.query['type']?.toString() ?? '';
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
          title: const Text('只看直属成员'),
          subtitle: Text(_direct ? '当前只查询直接下级' : '当前查询所有层级下级'),
          value: _direct,
          onChanged: _controller.busy
              ? null
              : (value) {
                  setState(() => _direct = value);
                  unawaited(_controller
                      .replaceQuery({...widget.query, 'direct': value}));
                }),
      const ReportSection('下级团队汇总',
          icon: Icons.groups_outlined, description: '统计当前筛选范围内的下级，不包含负责人本人。'),
      const ReportNotice('同一成员可能属于多个上级团队，多个团队的金额不能直接相加作为全群总额。'),
      if (summary is Map)
        ReportMetrics({
          '成员数': summary['memberCount'],
          '直属成员': summary['directMemberCount'],
          '批次最后积分': summary['totalBalance'],
          '闲家流水': summary['playerTurnover'],
          '庄家流水': summary['bankerTurnover'],
          '上分 / 划入': summary['totalUp'],
          '下分 / 划出': summary['totalDown'],
          '游戏积分变动': reportSigned(summary['profitLoss']),
          '已入账返水': summary['totalRebate'],
        }),
      if (root is Map)
        ListTile(
            title: Text('负责人：${reportUser(Map<String, dynamic>.from(root))}'),
            subtitle: Text(
                '本人批次最后积分 ${reportValue(root['balance'])} · 当前积分 ${reportValue(root['currentBalance'])}'),
            onTap: () => _openUser(Map<String, dynamic>.from(root))),
      const ReportSection('团队成员',
          icon: Icons.people_outline, description: '点击成员查看个人明细。'),
      ..._controller.rows.map((row) => ReportCard(
          child: ListTile(
              leading: SangongIMAvatar(
                  userID: '${row['imUserId'] ?? ''}',
                  nickname: reportUser(row)),
              title: SangongUserName(
                  userID: '${row['imUserId'] ?? ''}',
                  nickname: reportUser(row)),
              trailing: const Icon(Icons.chevron_right),
              subtitle: Text(
                  '当前积分 ${reportValue(row['currentBalance'])} · 批次最后积分 ${reportValue(row['balance'])}\n闲家流水 ${reportValue(row['playerTurnover'])} · 庄家流水 ${reportValue(row['bankerTurnover'])}\n已入账返水 ${reportValue(row['batchRebate'])}'),
              onTap: () => _openUser(row)))),
    ]);
  }

  Widget _settledPerson(Map<String, dynamic> item, Map round, bool banker) {
    final id = item['imUserId'];
    return ReportCard(
        child: ExpansionTile(
      leading: SangongIMAvatar(userID: '$id', nickname: reportUser(item)),
      title: SangongUserName(userID: '$id', nickname: reportUser(item)),
      subtitle: Text(
          '本局净额 ${reportSigned(item['net'])}\n结算后积分 ${reportValue(item['balanceAfter'])}'),
      children: [
        ReportMetrics({
          '结算前积分': item['balanceBefore'],
          '结算后积分': item['balanceAfter'],
          if (banker) ...{
            '投入金额': item['amount'],
            '合庄占比': item['sharePercent'] == null
                ? null
                : '${item['sharePercent']}%',
            '分摊下注流水': item['betShare'],
            '分摊抽水': item['rakeShare'],
          } else
            '本局下注': item['totalBet'],
          '本局净额': reportSigned(item['net']),
        }),
        if (!banker) ReportNotice(reportDoorBets(item['doorBets'])),
        if (id is String && id.isNotEmpty)
          TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('查看该用户本批次账变'),
              onPressed: () => unawaited(SangongReportDetailPage.open(context,
                  title: '${reportUser(item)} · 账变',
                  resource: 'ledger',
                  listKey: 'entries',
                  query: {'sessionId': round['sessionId'], 'imUserId': id}))),
      ],
    ));
  }

  Widget _round(Map<String, dynamic> data) {
    final round = data['round'] is Map ? data['round'] as Map : const {};
    final settlement =
        data['settlement'] is Map ? data['settlement'] as Map : const {};
    final draws = data['draws'] is List ? data['draws'] as List : const [];
    return Column(children: [
      ReportSection(
          '第${round['periodNo'] ?? '—'}期 · ${reportPhase(round['status'])}',
          icon: Icons.casino_outlined,
          description:
              '庄门 ${round['bankerDoor'] ?? '—'} · 结算时间 ${reportTime(round['settledAt'])}'),
      if (settlement.isNotEmpty) ...[
        ReportMetrics({
          '庄家': sangongDisplayName('${settlement['bankerNickname'] ?? ''}',
              '${settlement['bankerImUserId'] ?? ''}'),
          '闲家总下注': settlement['grandTotal'],
          '庄家净额': reportSigned(settlement['bankerNet']),
          '本局抽水': settlement['rake'],
        }),
        const ReportNotice('本局净额：正数为增加，负数为减少。下方展开可查看每位用户的结算前后积分。'),
      ],
      const ReportSection('各门开奖', icon: Icons.grid_view_outlined),
      if (draws.isEmpty) const ReportNotice('本局尚未录入开奖。'),
      if (draws.isNotEmpty)
        ReportMetrics({
          for (final draw in draws.whereType<Map>())
            '${draw['door']}门${draw['door'] == round['bankerDoor'] ? ' · 庄' : ''}':
                draw['amountHundredths'] is num
                    ? ((draw['amountHundredths'] as num) / 100)
                        .toStringAsFixed(2)
                    : null,
        }),
      for (final key in ['bankers', 'players'])
        if (settlement[key] is List) ...[
          ReportSection(key == 'bankers' ? '庄家与合庄结算' : '闲家结算',
              description: '共 ${(settlement[key] as List).length} 人 · 点击展开明细'),
          ...(settlement[key] as List).whereType<Map>().map((item) =>
              _settledPerson(
                  Map<String, dynamic>.from(item), round, key == 'bankers')),
        ],
      if (settlement.isEmpty) const ReportNotice('本局暂无有效结算。未结算或已作废的牌局不计入结算汇总。'),
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
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom + 24),
                        children: [
                          if (widget.resource == 'team')
                            _team(_controller.data),
                          if (widget.resource == 'management-round')
                            _round(_controller.data),
                          if (widget.resource == 'ledger') ...[
                            const ReportNotice(
                                '按时间从新到旧显示。正数增加积分，负数减少积分；点击记录可查看操作人和备注。'),
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
