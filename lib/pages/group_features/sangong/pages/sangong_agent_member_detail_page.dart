import 'package:openim_common/localization.dart';
import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_transfers_page.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/widgets/app_back_button.dart';
import '../widgets/authorization/sangong_agent_authorized_view.dart';
import '../agents/widgets/sangong_agent_user_actions.dart';

class SangongAgentMemberDetailPage extends StatefulWidget {
  const SangongAgentMemberDetailPage({super.key, required this.member});
  final SangongTeamMemberDto member;

  static Future<void> open(BuildContext context, SangongTeamMemberDto member) =>
      Navigator.of(context).push(SangongPageRoute(
        agent: true,
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
  Map<String, dynamic>? _lifetime;
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
      String? dashboardError;
      SangongTeamMemberDto? live;
      Map<String, dynamic>? lifetime;
      try {
        final dashboard = await SangongScope.read(context)
            .agent
            .fetchSangongMemberDashboard(imUserId: widget.member.imUserId);
        final rawLifetime = dashboard['lifetime'];
        if (rawLifetime is Map && rawLifetime['aggregation'] == 'all_time') {
          lifetime = Map<String, dynamic>.from(rawLifetime);
        }
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
          _lifetime = lifetime;
          _error = dashboardError;
          _daily = null;
          _loadingDaily = false;
        });
        return;
      }
      final daily = await SangongScope.read(context)
          .agent
          .fetchSangongMemberDaily(imUserId: widget.member.imUserId);
      if (mounted && _isCurrentSession) {
        setState(() {
          _daily = daily;
          _lifetime = lifetime;
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
  Widget metric(String title, num value, {String suffix = ''}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12)),
        const SizedBox(height: 4),
        Text('${money(value)}$suffix',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ]);

  Widget _lifetimeMetric(String label, String key) {
    final raw = _lifetime?[key];
    final value = raw is num ? raw : num.tryParse('$raw');
    if (value != null && value.isFinite) {
      return metric(AppCopy.text(label), value);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(AppCopy.text(label), style: Theme.of(context).textTheme.bodySmall),
      Text('—', style: Theme.of(context).textTheme.titleMedium),
    ]);
  }

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
      final claimedAmount = _dayNum(amount);
      ToastUtils.toast(
          claimedAmount == 0
              ? AppCopy.text('当前暂无可领取返水')
              : AppCopy.format(
                  '返水申请已提交，金额 ¥{#0}，请刷新确认到账', [money(claimedAmount)]),
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
    final name = sangongDisplayName(m.nickname, m.imUserId);
    return SangongAgentAuthorizedView(
      runtime: _accountSession.runtime,
      session: _accountSession,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          centerTitle: true,
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
                child: Text(AppCopy.text('划转记录')),
              ),
          ],
        ),
        body: Column(children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: Row(children: [
              _tab(AppCopy.text('个人最新数据'), 0),
              if (_canViewHistory) _tab(AppCopy.text('个人每天数据'), 1),
            ]),
          ),
          if (_loadingDaily) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: Text(_error!)),
                  TextButton(
                      onPressed: _loadDaily, child: Text(AppCopy.text('重试')))
                ])),
          Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Row(children: [
                    SangongIMAvatar(
                        userID: m.imUserId, nickname: name, size: 56),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SangongUserName(
                              userID: m.imUserId,
                              nickname: name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          SangongPublicAccount(
                              userID: m.imUserId,
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(
                              AppCopy.format('第 {#0} 级代理 · 返水 {#1}%',
                                  [m.levelNo, money(m.rebatePct)]),
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant))
                        ])
                  ]),
                  if (_liveMember != null && _error == null)
                    SangongAgentUserActions(
                        userId: m.userId,
                        imUserId: m.imUserId,
                        nickname: m.nickname,
                        rebatePct: m.rebatePct,
                        parentUserId: m.parentUserId,
                        agent: true,
                        onChanged: _loadDaily),
                  if (_tabIndex == 0) ...[
                    const SizedBox(height: 20),
                    _panelSwitcher(),
                    const SizedBox(height: 14),
                    Text(AppCopy.text('用户数据'),
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
                                  if (_summaryView)
                                    _lifetimeMetric('余额', 'balance')
                                  else
                                    metric(AppCopy.text('余额'), m.balance),
                                  if (_summaryView) ...[
                                    _lifetimeMetric('累计盈亏', 'profitLoss'),
                                    _lifetimeMetric('闲流水', 'playerTurnover'),
                                    _lifetimeMetric('庄流水', 'bankerTurnover'),
                                    _lifetimeMetric('总流水', 'totalTurnover'),
                                    _lifetimeMetric('上分', 'totalUp'),
                                    _lifetimeMetric('下分', 'totalDown'),
                                    _lifetimeMetric('已返水', 'rebate'),
                                  ] else ...[
                                    metric(AppCopy.text('最新盈亏'),
                                        m.todayProfitLoss),
                                    metric(
                                        AppCopy.text('闲流水'), m.playerTurnover),
                                    metric(
                                        AppCopy.text('庄流水'), m.bankerTurnover),
                                    metric(AppCopy.text('总流水'),
                                        m.displayTotalTurnover),
                                    metric('上分', m.todayUp),
                                    metric('下分', m.todayDown),
                                    metric('已返水', m.todayRebate),
                                  ],
                                  metric('待返水', m.pendingRebate),
                                  metric('返水比例', m.rebatePct, suffix: '%'),
                                ]))),
                    if (_tabIndex == 0 && _isCurrentLoginMember)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTokens.accent,
                              foregroundColor: AppTokens.onAccent,
                            ),
                            onPressed: _claiming ? null : _claimRebate,
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined),
                            label: Text(_claiming
                                ? AppCopy.text('申请中…')
                                : AppCopy.text('申请返水')),
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
          _panelButton(AppCopy.text('汇总'), true),
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
                      ? AppTokens.accent
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(label,
                style: TextStyle(
                    color: _tabIndex == index
                        ? AppTokens.accent
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _dailyView() {
    final days =
        (_daily?['days'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    if (days.isEmpty) {
      return Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: Text(AppCopy.text('暂无历史每日数据'))));
    }
    return Column(
      children: days.map((day) {
        final metrics = <(String, dynamic)>[
          (AppCopy.text('余额'), day['balance']),
          (AppCopy.text('盈亏'), day['profitLoss']),
          (AppCopy.text('闲流水'), day['playerTurnover']),
          (AppCopy.text('庄流水'), day['bankerTurnover']),
          (AppCopy.text('总流水'), day['totalTurnover']),
          (AppCopy.text('总上分'), day['totalUp']),
          (AppCopy.text('总下分'), day['totalDown']),
          (AppCopy.text('总返水'), day['rebate'] ?? day['totalRebate']),
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
