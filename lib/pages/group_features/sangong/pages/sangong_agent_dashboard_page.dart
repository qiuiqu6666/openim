import 'package:openim_common/localization.dart';
import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_member_detail_page.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/widgets/app_back_button.dart';
import '../agents/dashboard/dashboard_visuals.dart';
import '../agents/dashboard/sangong_team_daily_view.dart';
import '../widgets/authorization/sangong_agent_authorized_view.dart';

class SangongAgentDashboardPage extends StatefulWidget {
  const SangongAgentDashboardPage({super.key, this.imGroupId = ''});

  final String imGroupId;

  static Future<void> open(
    BuildContext context, {
    String imGroupId = '',
  }) =>
      Navigator.of(context).push(
        SangongPageRoute(
          agent: true,
          context: context,
          settings: const RouteSettings(name: 'sangong_agent_dashboard'),
          builder: (_) => SangongAgentDashboardPage(imGroupId: imGroupId),
        ),
      );

  @override
  State<SangongAgentDashboardPage> createState() =>
      _SangongAgentDashboardPageState();
}

class _SangongAgentDashboardPageState extends State<SangongAgentDashboardPage> {
  late final _accountSession = AgentSessionSnapshot(SangongScope.read(context));
  bool get _isCurrentSession => mounted && _accountSession.isCurrent;

  String _search = '';
  int _sort = 0;
  bool _daily = false;
  int _loadRequest = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || !_isCurrentSession) return;
    final request = ++_loadRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SangongScope.read(context).ensureAgentBinding();
      if (!mounted || !_isCurrentSession || request != _loadRequest) return;
      final data =
          await SangongScope.read(context).agent.fetchSangongTeamDashboard(
                direct: false,
              );
      if (!mounted || !_isCurrentSession || request != _loadRequest) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || !_isCurrentSession || request != _loadRequest) return;
      setState(() {
        _error = DioErrorMessage.forApp(error);
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  String _text(dynamic value) => value?.toString() ?? '';
  String _num(dynamic value) {
    final number = value is num ? value : num.tryParse(_text(value));
    if (number == null || !number.isFinite) return '—';
    return number == number.roundToDouble()
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(2);
  }

  String _money(dynamic value) {
    final text = _num(value);
    return text == '—' ? text : '¥$text';
  }

  num? _asNum(dynamic value) {
    final number = value is num ? value : num.tryParse(_text(value));
    return number != null && number.isFinite ? number : null;
  }

  num? _totalTurnover(Map<String, dynamic> summary) {
    final total = _asNum(summary['totalTurnover']);
    if (total != null) return total;
    final player = _asNum(summary['playerTurnover']);
    final banker = _asNum(summary['bankerTurnover']);
    return player == null || banker == null ? null : player + banker;
  }

  String _rebateRate(Map<String, dynamic> member) {
    final per10000 = _asNum(member['rebatePer10000']);
    final value = _asNum(member['rebatePct']) ??
        (per10000 == null ? null : per10000 / 100);
    final rate = _num(value);
    return rate == '—' ? rate : '$rate%';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _map(_data?['summary']);
    final members = (_data?['members'] is List)
        ? (_data!['members'] as List).whereType<Map>().map(_map).toList()
        : const <Map<String, dynamic>>[];
    final visible = members.where((member) {
      final query = _search.trim().toLowerCase();
      return (query.isEmpty ||
          ['nickname', 'imUserId', 'remark', 'account']
              .any((key) => _text(member[key]).toLowerCase().contains(query)));
    }).toList();
    visible.sort((a, b) {
      final left = _sort == 0 ? _asNum(a['balance']) : _totalTurnover(a);
      final right = _sort == 0 ? _asNum(b['balance']) : _totalTurnover(b);
      // Unknown amounts go last; equal amounts retain a deterministic order.
      if (left == null && right != null) return 1;
      if (left != null && right == null) return -1;
      final order = left == null ? 0 : right!.compareTo(left);
      return order != 0
          ? order
          : _text(a['imUserId']).compareTo(_text(b['imUserId']));
    });
    final t = DashboardVisuals(context);
    return SangongAgentAuthorizedView(
      runtime: _accountSession.runtime,
      session: _accountSession,
      child: Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Text(AppCopy.text('团队统计'), style: t.title),
          centerTitle: true,
          bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.only(bottom: DashboardVisuals.gap),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('团队概览')),
                    ButtonSegment(value: true, label: Text('团队每日'))
                  ],
                  selected: {_daily},
                  onSelectionChanged: (value) =>
                      setState(() => _daily = value.first),
                ),
              )),
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
            top: false,
            child: _daily
                ? const SangongTeamDailyView()
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Text(_error!),
                                FilledButton(
                                    onPressed: _load,
                                    child: Text(AppCopy.text('重试')))
                              ]))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding:
                                  const EdgeInsets.all(DashboardVisuals.inset),
                              itemCount: visible.length + 3,
                              itemBuilder: (context, index) {
                                if (index == 0) return _summaryCard(summary);
                                if (index == 1) return _membersHeader(members);
                                if (index == visible.length + 2) {
                                  return Container(
                                      padding: const EdgeInsets.all(
                                          DashboardVisuals.inset),
                                      decoration: t.panel(bottom: true),
                                      child: visible.isEmpty
                                          ? Center(
                                              child: Text(AppCopy.text(
                                                  members.isEmpty
                                                      ? '暂无下级'
                                                      : '没有匹配的下级')))
                                          : null);
                                }
                                return Container(
                                  color: t.surface,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: DashboardVisuals.inset),
                                  child: _memberCard(visible[index - 2]),
                                );
                              },
                            ),
                          )),
      ),
    );
  }

  Widget _membersHeader(List<Map<String, dynamic>> members) {
    final t = DashboardVisuals(context);
    return Container(
      margin: const EdgeInsets.only(top: DashboardVisuals.sectionGap),
      padding: const EdgeInsets.all(DashboardVisuals.inset),
      decoration: t.panel(top: true),
      child: Column(children: [
        Row(children: [
          Icon(Icons.groups_rounded, color: t.blue),
          const SizedBox(width: DashboardVisuals.gap),
          Expanded(child: Text(AppCopy.text('下级明细'), style: t.heading)),
          Text('${members.length} 人', style: t.label),
        ]),
        const SizedBox(height: DashboardVisuals.inset),
        Row(children: [
          Expanded(
              child: TextField(
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: AppCopy.text('搜索下级昵称/ID'),
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: t.soft,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DashboardVisuals.radius),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DashboardVisuals.radius),
                  borderSide: BorderSide.none),
            ),
          )),
          PopupMenuButton<int>(
            tooltip: AppCopy.text('选择排序方式'),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('按积分（从高到低）')),
              PopupMenuItem(value: 1, child: Text('按总流水（从高到低）')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(DashboardVisuals.gap),
              child: Row(children: [
                Icon(Icons.filter_alt_outlined, color: t.blue),
                Text(AppCopy.text(_sort == 0 ? '按积分' : '按流水'), style: t.label)
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _summaryCard(Map<String, dynamic> summary) {
    final t = DashboardVisuals(context);
    final fields = <(String, String, IconData, Color)>[
      (
        '闲流水',
        _money(summary['playerTurnover']),
        Icons.schedule_rounded,
        t.purple
      ),
      (
        '庄流水',
        _money(summary['bankerTurnover']),
        Icons.storage_rounded,
        t.orange
      ),
      (
        '团队人数',
        _num(summary['memberCount']),
        Icons.people_outline_rounded,
        t.blue
      ),
      (
        '直属人数',
        _num(summary['directMemberCount']),
        Icons.person_outline_rounded,
        t.pink
      ),
      ('上分', _money(summary['totalUp']), Icons.trending_up_rounded, t.green),
      ('下分', _money(summary['totalDown']), Icons.arrow_downward_rounded, t.red),
      (
        '团队盈亏',
        _money(summary['totalProfitLoss'] ?? summary['profitLoss']),
        Icons.bar_chart_rounded,
        t.blue
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(DashboardVisuals.inset),
      decoration: t.panel(top: true, bottom: true),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bar_chart_rounded, color: t.blue),
          const SizedBox(width: DashboardVisuals.gap),
          Text(AppCopy.text('团队概览'), style: t.heading)
        ]),
        const SizedBox(height: DashboardVisuals.inset),
        Container(
          decoration: BoxDecoration(
              color: t.soft,
              borderRadius: BorderRadius.circular(DashboardVisuals.radius)),
          child: _metricRow([
            (
              '团队总余额',
              _money(summary['totalBalance']),
              Icons.account_balance_wallet_outlined,
              t.blue
            ),
            (
              '总流水',
              _money(_totalTurnover(summary)),
              Icons.storage_rounded,
              t.green
            ),
          ], hero: true),
        ),
        const SizedBox(height: DashboardVisuals.gap),
        Container(
          decoration: BoxDecoration(
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(DashboardVisuals.radius)),
          child: Column(children: [
            for (var i = 0; i < fields.length; i += 2) ...[
              if (i > 0) Divider(height: 1, color: t.line),
              _metricRow(fields.skip(i).take(2).toList()),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _metricRow(List<(String, String, IconData, Color)> fields,
      {bool hero = false}) {
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(14) > 22;
      final widgets = fields
          .map((f) => DashboardMetric(
              label: f.$1, value: f.$2, icon: f.$3, color: f.$4, hero: hero))
          .toList();
      return stacked
          ? Column(children: widgets)
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...widgets.map((widget) => Expanded(child: widget)),
              if (widgets.length == 1) const Spacer(),
            ]);
    });
  }

  Widget _memberCard(Map<String, dynamic> member) {
    final t = DashboardVisuals(context);
    final name = _text(member['nickname']).trim().isEmpty
        ? AppCopy.text('用户')
        : _text(member['nickname']);
    return Padding(
      padding: const EdgeInsets.only(top: DashboardVisuals.gap),
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DashboardVisuals.radius),
            side: BorderSide(color: t.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (!_isCurrentSession) return;
            SangongAgentMemberDetailPage.open(
                context, SangongTeamMemberDto.fromJson(member));
          },
          child: Padding(
            padding: const EdgeInsets.all(DashboardVisuals.gap),
            child: Row(children: [
              SangongIMAvatar(
                  userID: _text(member['imUserId']),
                  nickname: name,
                  size: DashboardVisuals.avatar),
              const SizedBox(width: DashboardVisuals.gap),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    SangongUserName(
                        userID: _text(member['imUserId']),
                        nickname: name,
                        style: t.memberName),
                    const SizedBox(height: DashboardVisuals.smallGap),
                    Wrap(
                        spacing: DashboardVisuals.gap,
                        runSpacing: DashboardVisuals.smallGap,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: DashboardVisuals.smallGap,
                                  vertical: DashboardVisuals.badgeInset),
                              decoration: BoxDecoration(
                                  color: t.blue.withValues(alpha: .09),
                                  borderRadius: BorderRadius.circular(
                                      DashboardVisuals.badgeRadius)),
                              child: Text(_levelLabel(member['levelNo']),
                                  style: t.detail.copyWith(color: t.blue))),
                          Text('余额 ${_money(member['balance'])}',
                              style: t.detail),
                          Text('返水 ${_rebateRate(member)}', style: t.detail),
                          Text('闲 ${_money(member['playerTurnover'])}',
                              style: t.detail),
                          Text('庄 ${_money(member['bankerTurnover'])}',
                              style: t.detail),
                        ]),
                  ])),
              Icon(Icons.chevron_right_rounded, color: t.secondary),
            ]),
          ),
        ),
      ),
    );
  }

  String _levelLabel(dynamic value) {
    final level = int.tryParse(_text(value)) ?? 0;
    final labels = <String>[
      '',
      AppCopy.text('一级代理'),
      AppCopy.text('二级代理'),
      AppCopy.text('三级代理')
    ];
    return level > 0 && level < labels.length
        ? labels[level]
        : AppCopy.format('第 {#0} 级', [level]);
  }
}
