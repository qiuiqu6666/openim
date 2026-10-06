// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_transfers_page.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/widgets/app_back_button.dart';
import '../widgets/authorization/sangong_agent_authorized_view.dart';

class SangongAgentMemberDetailPage extends StatefulWidget {
  const SangongAgentMemberDetailPage({super.key, required this.member});
  final SangongTeamMemberDto member;

  static Future<void> open(BuildContext context, SangongTeamMemberDto member) =>
      Navigator.of(context).push(SangongPageRoute(
        context: context,
        settings: const RouteSettings(name: 'sangong_agent_member_detail'),
        builder: (_) => SangongAgentMemberDetailPage(member: member),
      ));

  @override
  State<SangongAgentMemberDetailPage> createState() => _State();
}

class _State extends State<SangongAgentMemberDetailPage> {
  late final _accountSession = AgentSessionSnapshot(SangongScope.read(context));
  bool get _isCurrentSession => mounted && _accountSession.isCurrent;
  bool get _canViewHistory => SangongScope.read(context).canViewRebateHistory;

  SangongTeamMemberDto? _liveMember;
  Map<String, dynamic>? _daily;
  String? _error;
  bool _loadingDaily = true;
  int _tabIndex = 0;
  bool _summaryView = false;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _loadDaily();
  }

  Future<void> _loadDaily() async {
    if (!mounted || !_isCurrentSession) return;
    setState(() {
      _loadingDaily = true;
      _error = null;
    });
    try {
      String? batchNo;
      String? dashboardError;
      SangongTeamMemberDto? live;
      try {
        final dashboard = await SangongScope.read(context)
            .agent
            .fetchSangongMemberDashboard(imUserId: widget.member.imUserId);
        final batch = dashboard['batch'];
        batchNo = batch is Map ? batch['batchNo']?.toString() : null;
        final member = dashboard['member'];
        if (member is Map) {
          live =
              SangongTeamMemberDto.fromJson(Map<String, dynamic>.from(member));
        }
      } catch (error) {
        // Keep the independent history fallback, but do not hide a failed
        // refresh of the latest member data behind the cached member.
        dashboardError = DioErrorMessage.forApp(error);
      }
      if (!mounted || !_isCurrentSession) return;
      if (!_canViewHistory) {
        setState(() {
          _liveMember = live;
          _error = dashboardError;
          _daily = null;
          _loadingDaily = false;
        });
        return;
      }
      var daily = await SangongScope.read(context)
          .agent
          .fetchSangongMemberDaily(
              imUserId: widget.member.imUserId, batchNo: batchNo);
      if (!mounted || !_isCurrentSession) return;
      if ((daily['days'] is! List || (daily['days'] as List).isEmpty) &&
          batchNo != null) {
        daily = await SangongScope.read(context)
            .agent
            .fetchSangongMemberDaily(imUserId: widget.member.imUserId);
      }
      if (mounted && _isCurrentSession) {
        setState(() {
          _daily = daily;
          _error = dashboardError;
          _loadingDaily = false;
          if (live != null) _liveMember = live;
        });
      }
    } catch (failure) {
      if (mounted && _isCurrentSession) {
        setState(() {
          _error = DioErrorMessage.forApp(failure);
          _loadingDaily = false;
        });
      }
    }
  }

  String money(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  Widget metric(String title, num value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12)),
        const SizedBox(height: 4),
        Text(money(value),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ]);

  bool get _isCurrentLoginMember {
    final selfId = ChatIdFormat.rawUserUid(
        SangongScope.read(context).featureContext.currentUserID);
    final memberId = ChatIdFormat.rawUserUid(widget.member.imUserId);
    return selfId.isNotEmpty && memberId.isNotEmpty && selfId == memberId;
  }

  Future<void> _claimRebate() async {
    if (!mounted || !_isCurrentSession) return;
    if (!_isCurrentLoginMember || _claiming) return;
    setState(() => _claiming = true);
    try {
      final result =
          await SangongScope.read(context).agent.claimSangongRebate();
      if (!mounted || !_isCurrentSession) return;
      final amount = result['amount'];
      if (amount is! num && num.tryParse('$amount') == null) {
        throw const FormatException('Invalid rebate result');
      }
      ToastUtils.toast('返水申请已提交，金额 ¥${money(_dayNum(amount))}，请刷新确认到账',
          context: context);
      await _loadDaily();
    } catch (e) {
      if (mounted && _isCurrentSession) {
        ToastUtils.toast(DioErrorMessage.forApp(e), context: context);
      }
    } finally {
      if (mounted && _isCurrentSession) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _liveMember ?? widget.member;
    final name = m.nickname.trim().isEmpty ? m.imUserId : m.nickname.trim();
    return SangongAgentAuthorizedView(
      runtime: _accountSession.runtime,
      session: _accountSession,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Text(name),
          actions: [
            if (_isCurrentLoginMember && _canViewHistory)
              TextButton(
                onPressed: () {
                  if (_isCurrentSession) {
                    SangongAgentTransfersPage.open(context);
                  }
                },
                child: const Text('划转记录'),
              ),
          ],
        ),
        body: Column(children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: Row(children: [
              _tab('个人最新数据', 0),
              if (_canViewHistory) _tab('个人每天数据', 1),
            ]),
          ),
          if (_loadingDaily) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: Text(_error!)),
                  TextButton(onPressed: _loadDaily, child: const Text('重试'))
                ])),
          Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Row(children: [
                    CircleAvatar(
                        radius: 28,
                        backgroundImage: m.avatarUrl.isEmpty
                            ? null
                            : NetworkImage(m.avatarUrl),
                        child: m.avatarUrl.isEmpty
                            ? Text(name.characters.first)
                            : null),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          Text('第 ${m.levelNo} 级代理 · 返水 ${money(m.rebatePct)}%',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant))
                        ])
                  ]),
                  if (_tabIndex == 0) ...[
                    const SizedBox(height: 20),
                    _panelSwitcher(),
                    const SizedBox(height: 14),
                    const Text('用户数据',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Card(
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: 2,
                                childAspectRatio: 2.7,
                                children: [
                                  metric('余额', m.balance),
                                  metric(
                                      _summaryView ? '本批次盈亏' : '最新盈亏',
                                      _summaryView
                                          ? m.batchProfitLoss
                                          : m.todayProfitLoss),
                                  if (_summaryView) ...[
                                    metric('闲流水', m.playerTurnover),
                                    metric('庄流水', m.bankerTurnover),
                                    metric('总流水', m.batchTotalTurnover),
                                  ] else ...[
                                    metric('闲流水', m.playerTurnover),
                                    metric('庄流水', m.bankerTurnover),
                                    metric('总流水', m.displayTotalTurnover),
                                    metric('最近闲流水', m.latestPlayerTurnover),
                                    metric('最近庄流水', m.latestBankerTurnover),
                                  ],
                                  metric('上分',
                                      _summaryView ? m.batchUp : m.todayUp),
                                  metric('下分',
                                      _summaryView ? m.batchDown : m.todayDown),
                                  metric(
                                      '已返水',
                                      _summaryView
                                          ? m.batchRebate
                                          : m.todayRebate),
                                  metric('待返水', m.pendingRebate),
                                  metric('返水比例', m.rebatePct),
                                ]))),
                    if (_tabIndex == 0 && _isCurrentLoginMember)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _claiming ? null : _claimRebate,
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined),
                            label: Text(_claiming ? '申请中…' : '申请返水'),
                          ),
                        ),
                      ),
                  ],
                  if (_tabIndex == 1 && _canViewHistory) _dailyView(),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _panelSwitcher() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          _panelButton('最新', false),
          _panelButton('汇总', true),
        ]),
      );

  Widget _panelButton(String label, bool summary) => Expanded(
        child: InkWell(
          onTap: () => setState(() => _summaryView = summary),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: _summaryView == summary
                  ? Theme.of(context).colorScheme.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _summaryView == summary
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
      );

  Widget _tab(String label, int index) => Expanded(
        child: InkWell(
          onTap: () {
            setState(() => _tabIndex = index);
            if (index == 1) _loadDaily();
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: _tabIndex == index
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(label,
                style: TextStyle(
                    color: _tabIndex == index
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _dailyView() {
    final days =
        (_daily?['days'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    if (days.isEmpty) {
      return const Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: Text('暂无历史每日数据')));
    }
    return Column(
      children: days.map((day) {
        final metrics = <(String, dynamic)>[
          ('余额', day['balance']),
          ('盈亏', day['profitLoss']),
          ('闲流水', day['playerTurnover']),
          ('庄流水', day['bankerTurnover']),
          ('总流水', day['totalTurnover']),
          ('总上分', day['totalUp']),
          ('总下分', day['totalDown']),
          ('总返水', day['rebate'] ?? day['totalRebate']),
        ];
        return Card(
          color: Theme.of(context).colorScheme.surface,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${day['businessDate'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 5.2,
                mainAxisSpacing: 5,
                crossAxisSpacing: 12,
                children: metrics
                    .map((item) => Row(children: [
                          Expanded(
                              child: Text(item.$1,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant))),
                          Text(item.$2 == null ? '—' : money(_dayNum(item.$2)),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ]))
                    .toList(),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  num _dayNum(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
}
