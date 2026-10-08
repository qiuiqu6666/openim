import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_member_detail_page.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/widgets/app_back_button.dart';
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SangongScope.read(context).ensureAgentBinding();
      if (!mounted || !_isCurrentSession) return;
      final data =
          await SangongScope.read(context).agent.fetchSangongTeamDashboard(
                direct: false,
              );
      if (!mounted || !_isCurrentSession) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || !_isCurrentSession) return;
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
    final batch = _map(_data?['batch']);
    final members = (_data?['members'] is List)
        ? (_data!['members'] as List).whereType<Map>().map(_map).toList()
        : const <Map<String, dynamic>>[];
    return SangongAgentAuthorizedView(
      runtime: _accountSession.runtime,
      session: _accountSession,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: const AppBackButton(),
          title:
              const Text('团队统计', style: TextStyle(fontWeight: FontWeight.w700)),
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('重试'))
                  ]))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _batchCard(batch),
                        const SizedBox(height: 18),
                        _sectionTitle('团队概览', Icons.insights_rounded),
                        const SizedBox(height: 10),
                        _summaryCard(summary),
                        const SizedBox(height: 22),
                        _sectionTitle('下级明细', Icons.groups_2_rounded,
                            trailing: '${members.length} 人'),
                        const SizedBox(height: 10),
                        if (members.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('暂无下级'))),
                        ...members.map(_memberCard),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _batchCard(Map<String, dynamic> batch) {
    final running = _text(batch['status']).toLowerCase() == 'running';
    final start = _text(batch['startedAt']);
    final stop = _text(batch['stoppedAt']);
    String time(String value) => value.length >= 16
        ? value.substring(5, 16).replaceFirst('T', ' ')
        : value;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Icon(Icons.calendar_today_rounded,
              size: 19, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('当前业务批次',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                    _text(batch['batchNo']).isEmpty
                        ? '未指定'
                        : _text(batch['batchNo']),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                if (start.isNotEmpty)
                  Text('${time(start)} ～ ${running ? '至今' : time(stop)}',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
          Text(
              running
                  ? '● 开机中'
                  : _text(batch['status']).isEmpty
                      ? '状态未知'
                      : '已结算',
              style: TextStyle(
                  color: running
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.shade300
                          : Colors.green.shade800)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon, {String? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 7),
        Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (trailing != null)
          Text(trailing,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _summaryCard(Map<String, dynamic> summary) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _heroMetric('团队总余额', _money(summary['totalBalance']), null),
          const SizedBox(height: 12),
          _heroMetric(
            '总流水',
            _money(_totalTurnover(summary)),
            null,
          ),
          const SizedBox(height: 14),
          _compactGrid(summary),
        ]),
      ),
    );
  }

  Widget _heroMetric(String label, String value, dynamic state) {
    final number = state is num ? state : num.tryParse(_text(state)) ?? 0;
    final color = state == null
        ? Theme.of(context).colorScheme.onSurface
        : number > 0
            ? (Theme.of(context).brightness == Brightness.dark
                ? Colors.green.shade300
                : Colors.green.shade800)
            : number < 0
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurface;
    return Row(children: [
      Expanded(
          child: Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant))),
      Text(value,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, color: color))
    ]);
  }

  Widget _compactGrid(Map<String, dynamic> summary) {
    final fields = <(String, String, bool)>[
      ('闲流水', _money(summary['playerTurnover']), false),
      ('庄流水', _money(summary['bankerTurnover']), false),
      ('团队人数', _num(summary['memberCount']), false),
      ('直属人数', _num(summary['directMemberCount']), false),
      ('上分', _money(summary['totalUp']), false),
      ('下分', _money(summary['totalDown']), false),
      (
        '团队盈亏',
        _money(summary['totalProfitLoss'] ?? summary['profitLoss']),
        false
      ),
    ];
    return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 3.8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 12,
        children: fields
            .map((item) => Row(children: [
                  Expanded(
                      child: Text(item.$1,
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant))),
                  Text(item.$2,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700))
                ]))
            .toList());
  }

  Widget _memberCard(Map<String, dynamic> member) {
    final name = _text(member['nickname']).trim().isEmpty
        ? '用户'
        : _text(member['nickname']);
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: SangongIMAvatar(
            userID: _text(member['imUserId']), nickname: name, size: 48),
        title: SangongUserName(
            userID: _text(member['imUserId']),
            nickname: name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '${_levelLabel(member['levelNo'])} · 余额 ${_money(member['balance'])} · 返水 ${_rebateRate(member)} · 闲 ${_money(member['playerTurnover'])} · 庄 ${_money(member['bankerTurnover'])}'),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          if (!_isCurrentSession) return;
          SangongAgentMemberDetailPage.open(
            context,
            SangongTeamMemberDto.fromJson(member),
          );
        },
      ),
    );
  }

  String _levelLabel(dynamic value) {
    final level = int.tryParse(_text(value)) ?? 0;
    const labels = <String>['', '一级代理', '二级代理', '三级代理'];
    return level > 0 && level < labels.length ? labels[level] : '第 $level 级';
  }
}
