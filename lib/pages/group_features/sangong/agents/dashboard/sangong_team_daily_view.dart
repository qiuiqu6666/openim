import 'package:flutter/material.dart';
import '../../sangong_scope.dart';
import '../../support/sangong_ui.dart';
import 'dashboard_visuals.dart';

/// Date-paged team history. The server owns team membership and aggregation.
class SangongTeamDailyView extends StatefulWidget {
  const SangongTeamDailyView({super.key});
  @override
  State<SangongTeamDailyView> createState() => _SangongTeamDailyViewState();
}

class _SangongTeamDailyViewState extends State<SangongTeamDailyView> {
  late final _session = AgentSessionSnapshot(SangongScope.read(context));
  final _days = <Map<String, dynamic>>[];
  bool _loading = false;
  String? _error;
  String _next = '';
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || !_session.isCurrent) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _session.runtime.agent
          .fetchSangongTeamDaily(to: reset ? null : _next);
      if (!mounted || !_session.isCurrent || request != _request) return;
      final rows = (data['days'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final next = data['nextTo'] as String;
      if (!reset && next.isNotEmpty && next.compareTo(_next) >= 0) {
        throw const FormatException('分页日期未前进');
      }
      setState(() {
        if (reset) _days.clear();
        final seen = _days.map((d) => d['businessDate']).toSet();
        _days.addAll(rows.where((d) => seen.add(d['businessDate'])));
        _next = next;
        _loading = false;
      });
    } catch (error) {
      if (mounted && _session.isCurrent && request == _request) {
        setState(() {
          _loading = false;
          _error = DioErrorMessage.forApp(error);
        });
      }
    }
  }

  String _number(dynamic value) {
    final n = value is num ? value : num.tryParse('$value');
    if (n == null || !n.isFinite) return '—';
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final t = DashboardVisuals(context);
    return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DashboardVisuals.inset),
          itemCount: _days.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                  padding: const EdgeInsets.only(bottom: DashboardVisuals.gap),
                  child: Text('按当前团队范围统计，包含本人', style: t.detail));
            }
            if (index == _days.length + 1) {
              if (_loading) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(DashboardVisuals.inset),
                        child: CircularProgressIndicator()));
              }
              if (_error != null) {
                return Column(children: [
                  Text(_error!),
                  TextButton(
                      onPressed: () => _load(reset: _days.isEmpty),
                      child: const Text('重试'))
                ]);
              }
              if (_days.isEmpty) return const Center(child: Text('暂无团队每日数据'));
              if (_next.isNotEmpty) {
                return TextButton(
                    onPressed: _load, child: const Text('加载更早日期'));
              }
              return Padding(
                  padding: const EdgeInsets.all(DashboardVisuals.inset),
                  child: Center(child: Text('已显示全部日期', style: t.detail)));
            }
            final day = _days[index - 1];
            final fields = <(String, String, IconData, Color)>[
              (
                '团队余额',
                'totalBalance',
                Icons.account_balance_wallet_outlined,
                t.blue
              ),
              ('团队盈亏', 'totalProfitLoss', Icons.bar_chart_rounded, t.blue),
              ('闲流水', 'playerTurnover', Icons.schedule_rounded, t.purple),
              ('庄流水', 'bankerTurnover', Icons.storage_rounded, t.orange),
              ('总流水', 'totalTurnover', Icons.equalizer_rounded, t.green),
              ('上分', 'totalUp', Icons.trending_up_rounded, t.green),
              ('下分', 'totalDown', Icons.arrow_downward_rounded, t.red),
              ('已返水', 'totalRebate', Icons.replay_rounded, t.pink),
            ];
            return Container(
                margin: const EdgeInsets.only(bottom: DashboardVisuals.inset),
                padding: const EdgeInsets.all(DashboardVisuals.inset),
                decoration: t.panel(top: true, bottom: true),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${day['businessDate']}', style: t.heading),
                      const SizedBox(height: DashboardVisuals.gap),
                      for (var i = 0; i < fields.length; i += 2)
                        LayoutBuilder(builder: (context, c) {
                          final children = fields
                              .skip(i)
                              .take(2)
                              .map((f) => DashboardMetric(
                                  label: f.$1,
                                  value: _number(day[f.$2]),
                                  icon: f.$3,
                                  color: f.$4))
                              .toList();
                          return MediaQuery.textScalerOf(context).scale(14) > 22
                              ? Column(children: children)
                              : Row(
                                  children: children
                                      .map((w) => Expanded(child: w))
                                      .toList());
                        }),
                    ]));
          },
        ));
  }
}
