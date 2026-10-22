import 'package:flutter/material.dart';
import '../models/group_feature_context.dart';
import '../mark_six/widgets/mark_six_app_bar.dart';
import '../mark_six/widgets/lottery_tab_bar.dart';
import '../mark_six/widgets/mark_six_style.dart';
import 'bingo_controller.dart';
import 'bingo_history_panel.dart';
import 'bingo_live_card.dart';
import 'bingo_rules.dart';
export 'bingo_draw.dart';
export 'bingo_card.dart';

bool bingoContextCurrent(GroupFeatureContext context) {
  final latest = context.readCurrentContext();
  return context.sessionCurrent() &&
      latest.showBingoDrawHistory &&
      latest.groupID == context.groupID &&
      latest.currentUserID == context.currentUserID;
}

class BingoPage extends StatefulWidget {
  const BingoPage({super.key, required this.featureContext, this.controller});
  final GroupFeatureContext featureContext;
  final BingoController? controller;

  static Future<void> open(
      BuildContext context, GroupFeatureContext featureContext,
      {BingoController? controller,
      ValueChanged<VoidCallback?>? onDismissChanged}) async {
    if (!bingoContextCurrent(featureContext) || !context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    await navigator.push<void>(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'bingo_draw_history'),
      builder: (pageContext) {
        final route = ModalRoute.of(pageContext)!;
        onDismissChanged?.call(() {
          if (route.isActive) navigator.removeRoute(route);
        });
        return BingoPage(
            featureContext: featureContext, controller: controller);
      },
    ));
    onDismissChanged?.call(null);
  }

  @override
  State<BingoPage> createState() => _BingoPageState();
}

class _BingoPageState extends State<BingoPage> {
  int _tab = 0;
  final _historyKey = GlobalKey<BingoHistoryPanelState>();
  late final controller = widget.controller ??
      BingoController(
          current: () => bingoContextCurrent(widget.featureContext));

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: MarkSixStyle.of(context).lotteryBackground,
        appBar: markSixLotteryAppBar(context, title: '台湾宾果六合彩', subtitle: null),
        body: SafeArea(
            child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => !controller.current()
              ? const Center(child: Text('群类型或登录状态已变更，请重新进入'))
              : RefreshIndicator(
                  onRefresh: () async {
                    await controller.refresh();
                    await _historyKey.currentState?.refresh();
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      BingoLiveCard(
                          controller: controller,
                          preview: true,
                          showOpenHint: false),
                      const SizedBox(height: 10),
                      LotteryTabBar(
                        rules: true,
                        selectedIndex: _tab,
                        onChanged: (index) => setState(() => _tab = index),
                      ),
                      const SizedBox(height: 12),
                      if (_tab == 0 || _tab == 2)
                        BingoHistoryPanel(
                            key: _historyKey,
                            current: controller.current,
                            statistics: _tab == 2),
                      if (_tab == 1) _tabEmpty(context),
                      if (_tab == 3) const BingoRules(),
                    ],
                  ),
                ),
        )),
      );

  Widget _tabEmpty(BuildContext context) {
    const icons = [
      Icons.access_time_rounded,
      Icons.auto_awesome_rounded,
      Icons.bar_chart_rounded,
      Icons.campaign_rounded,
    ];
    const messages = ['暂无开奖记录', '暂无预测数据', '暂无统计数据', '暂无本群宣言'];
    final style = MarkSixStyle.of(context);
    return Padding(
      key: ValueKey('bingo-tab-content-$_tab'),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(children: [
        ExcludeSemantics(
            child: Icon(icons[_tab], size: 36, color: style.secondary)),
        const SizedBox(height: 12),
        Text(messages[_tab], style: TextStyle(color: style.secondary)),
      ]),
    );
  }
}
