import 'package:openim_common/localization.dart';
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
import '../widgets/lottery_tab_bar.dart';

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
  final _scrollController = ScrollController();
  bool _paginationCheckScheduled = false;
  bool _closing = false;
  bool get _allowed => widget.featureContext.showMarkSixDrawHistory;
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_schedulePaginationCheck);
    _controller.addListener(_handleScopeChange);
    if (_allowed) _controller.attach();
  }

  void _schedulePaginationCheck() {
    if (_paginationCheckScheduled) return;
    _paginationCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paginationCheckScheduled = false;
      if (!mounted ||
          _closing ||
          _tab != 1 ||
          !_controller.current ||
          _controller.loading ||
          _controller.predictionsLoading ||
          _controller.predictionError != null ||
          !_controller.predictionsHasMore ||
          !_scrollController.hasClients ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (_scrollController.position.extentAfter <= 300) {
        _controller.loadPredictions(more: true);
      }
    });
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
    _scrollController.dispose();
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
                ? MarkSixEmpty(message: AppCopy.text('本群尚未开放六合彩'))
                : ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) {
                      _schedulePaginationCheck();
                      if (!_controller.current) {
                        return MarkSixEmpty(
                            message: _controller.scopeInvalidated
                                ? AppCopy.text('本群六合彩配置已变更，请重新进入')
                                : AppCopy.text('登录状态已变更'));
                      }
                      if (!_controller.ready && _controller.loading) {
                        return Center(child: LoadingView.indicator());
                      }
                      if (!_controller.ready) {
                        return MarkSixEmpty(
                            message:
                                _controller.error ?? AppCopy.text('暂无开奖数据'),
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
                              controller: _scrollController,
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
                                            child: Text(AppCopy.text('重试')))
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

  Widget _tabs(BuildContext context) => LotteryTabBar(
        selectedIndex: _tab,
        onChanged: (index) {
          setState(() => _tab = index);
          _controller.setPredictionVisible(index == 1);
        },
      );
}
