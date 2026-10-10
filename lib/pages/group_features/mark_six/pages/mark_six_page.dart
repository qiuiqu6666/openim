// Product layout adapted from 99chat settings/test_page.dart and lottery_dashboard.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../models/group_feature_context.dart';
import '../data/mark_six_controller.dart';
import '../data/mark_six_repository.dart';
import '../declaration/mark_six_declaration_panel.dart';
import '../widgets/mark_six_history_table.dart';
import '../widgets/mark_six_latest_card.dart';
import '../widgets/mark_six_opened_statistics.dart';
import '../widgets/mark_six_predictions.dart';
import '../widgets/mark_six_style.dart';
import '../widgets/mark_six_app_bar.dart';

class MarkSixPage extends StatefulWidget {
  const MarkSixPage({super.key, required this.featureContext, this.controller});
  final GroupFeatureContext featureContext;
  final MarkSixController? controller;
  @override
  State<MarkSixPage> createState() => _MarkSixPageState();
}

class _MarkSixPageState extends State<MarkSixPage> {
  late final _controller = widget.controller ??
      MarkSixController(MarkSixRepository(widget.featureContext));
  int _tab = 0;
  bool _closing = false;
  bool get _allowed => widget.featureContext.showMarkSixDrawHistory;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleScopeChange);
    if (_allowed) _controller.attach();
  }

  void _handleScopeChange() {
    if (!mounted || _closing || !_controller.scopeInvalidated) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      final navigator = Navigator.of(context);
      if (route != null && route.isActive && navigator.canPop()) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScopeChange);
    _controller.setPredictionVisible(false);
    _controller.detach();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    return Scaffold(
        backgroundColor: style.lotteryBackground,
        appBar: markSixLotteryAppBar(context),
        body: SafeArea(
            top: false,
            child: !_allowed
                ? const MarkSixEmpty(message: '本群尚未开放六合彩')
                : ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) {
                      if (!_controller.current) {
                        return MarkSixEmpty(
                            message: _controller.scopeInvalidated
                                ? '本群六合彩配置已变更，请重新进入'
                                : '登录状态已变更');
                      }
                      if (!_controller.ready && _controller.loading) {
                        return Center(child: LoadingView.indicator());
                      }
                      if (!_controller.ready) {
                        return MarkSixEmpty(
                            message: _controller.error ?? '暂无开奖数据',
                            onRetry: () => _controller.refresh(force: true));
                      }
                      return RefreshIndicator(
                          onRefresh: () async {
                            await _controller.refresh(force: true);
                            if (_tab == 1) {
                              await _controller.loadPredictions(force: true);
                            }
                          },
                          child: ListView(
                              padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                MarkSixLatestCard(controller: _controller),
                                const SizedBox(height: 10),
                                _tabs(context),
                                const SizedBox(height: 8),
                                if (_controller.error != null)
                                  Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Row(children: [
                                        Expanded(
                                            child: Text(_controller.error!,
                                                style: TextStyle(
                                                    color: style.error))),
                                        TextButton(
                                            onPressed: () => _controller
                                                .refresh(force: true),
                                            child: const Text('重试'))
                                      ])),
                                if (_tab == 0)
                                  MarkSixHistoryTable(draws: _controller.draws),
                                if (_tab == 1)
                                  MarkSixPredictions(controller: _controller),
                                if (_tab == 2)
                                  MarkSixOpenedStatistics(
                                      draws: _controller.draws),
                                if (_tab == 3)
                                  MarkSixDeclarationPanel(
                                      repository: _controller.repository),
                              ]));
                    })));
  }

  Widget _tabs(BuildContext context) {
    final style = MarkSixStyle.of(context);
    const tabs = ['开奖历史', '智能预测', '已开统计', '本群宣言'];
    const icons = [
      Icons.access_time_rounded,
      Icons.auto_awesome_rounded,
      Icons.bar_chart_rounded,
      Icons.campaign_rounded
    ];
    return Container(
        key: const ValueKey('lottery-tab-bar'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            color: style.lotteryAlt,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: style.lotteryBorder)),
        child: Row(children: [
          for (var index = 0; index < tabs.length; index++)
            Expanded(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: _tab == index
                            ? const LinearGradient(
                                colors: [Color(0xFF3A91FA), Color(0xFF1976F3)])
                            : null),
                    child: TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(0, 34),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            foregroundColor: _tab == index
                                ? AppTokens.onAccent
                                : style.secondary),
                        onPressed: () {
                          setState(() => _tab = index);
                          _controller.setPredictionVisible(index == 1);
                        },
                        child: FittedBox(
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icons[index], size: 16),
                          const SizedBox(width: 6),
                          Text(tabs[index],
                              style: const TextStyle(fontSize: 12))
                        ])))))
        ]));
  }
}
