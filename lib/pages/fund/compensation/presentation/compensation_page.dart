import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../wallet/host/wallet_navigation.dart';
import '../../../wallet/record/wallet_record_screen.dart';
import '../data/compensation_api.dart';
import '../models/compensation_detail.dart';
import '../state/compensation_controller.dart';
import 'compensation_content.dart';
import 'compensation_tokens.dart';
import 'compensation_artwork.dart';

class CompensationPage extends StatefulWidget {
  const CompensationPage({super.key, required this.activityID, this.source});
  final String activityID;
  final CompensationSource? source;
  @override
  State<CompensationPage> createState() => _CompensationPageState();
}

class _CompensationPageState extends State<CompensationPage>
    with WidgetsBindingObserver {
  late final CompensationController _controller;
  final _rules = GlobalKey();
  final _shareButton = GlobalKey();
  bool _sharing = false;
  Timer? _timer;
  bool _foreground = true;
  Future<void> _share() async {
    final detail = _controller.detail;
    if (_sharing || detail == null) return;
    setState(() => _sharing = true);
    final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await Share.share(
        '${detail.title}\n感谢你一直都在\n老用户补偿总奖池：${detail.poolLabel}\n${detail.description}\n请在99Chat内查看活动详情，参与资格及领取状态以活动页面为准。\n\n下载99Chat：https://99chat.vip',
        subject: detail.title,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法打开系统分享，请重试')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = CompensationController(
        source: widget.source ?? CompensationApi(), id: widget.activityID);
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_schedule);
    unawaited(_controller.refresh());
  }

  void _schedule() {
    if (!_foreground || _controller.detail == null || _controller.expired) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??=
          Timer.periodic(const Duration(seconds: 1), (_) => _controller.tick());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _schedule();
      unawaited(_controller.refresh());
    } else {
      _timer?.cancel();
      _timer = null;
      _controller.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.removeListener(_schedule);
    _controller.dispose();
    super.dispose();
  }

  void _showRules() {
    final d = _controller.detail;
    if (d == null) return;
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (c) => SafeArea(
            child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .8),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(CompensationTokens.inset),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            const Expanded(child: Text('参与规则')),
                            IconButton(
                                tooltip: '关闭',
                                onPressed: () => Navigator.pop(c),
                                icon: const Icon(Icons.close))
                          ]),
                          CompensationRules(detail: d)
                        ])))));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final d = _controller.detail;
        final state = _controller.state;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: CompensationTokens.cream(context),
          body: DecoratedBox(
              decoration: BoxDecoration(
                  image: Theme.of(context).brightness == Brightness.light
                      ? const DecorationImage(
                          image:
                              AssetImage(CompensationTokens.detailBackground),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter)
                      : null,
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        CompensationTokens.cream(context),
                        cs.surfaceContainerLow,
                        cs.surfaceContainerLow
                      ])),
              child: SafeArea(
                  bottom: false,
                  child: Stack(fit: StackFit.expand, children: [
                    Positioned.fill(
                        child: Center(
                            child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    maxWidth: CompensationTokens.maxWidth),
                                child: d == null
                                    ? Center(
                                        child: Padding(
                                            padding: const EdgeInsets.all(
                                                CompensationTokens.inset),
                                            child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (_controller.busy)
                                                    const CircularProgressIndicator(),
                                                  const SizedBox(
                                                      height: CompensationTokens
                                                          .space),
                                                  Text(
                                                      _controller.error ??
                                                          '正在加载活动',
                                                      textAlign:
                                                          TextAlign.center),
                                                  if (!_controller.busy)
                                                    TextButton(
                                                        onPressed:
                                                            _controller.refresh,
                                                        child:
                                                            const Text('重新加载')),
                                                ])))
                                    : ListView(
                                        padding: const EdgeInsets.all(
                                            CompensationTokens.inset),
                                        children: [
                                            CompensationContent(
                                                controller: _controller,
                                                rulesKey: _rules),
                                            if (_controller.error != null)
                                              Semantics(
                                                  liveRegion: true,
                                                  child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical:
                                                              CompensationTokens
                                                                  .space),
                                                      child: Text(
                                                          _controller.error!,
                                                          style: TextStyle(
                                                              color:
                                                                  cs.error))))
                                          ])))),
                    PositionedDirectional(
                      top: 0,
                      end: CompensationTokens.small,
                      child: IconButton(
                        key: _shareButton,
                        tooltip: '分享活动',
                        color: CompensationTokens.ink(context),
                        onPressed: d == null || _sharing ? null : _share,
                        constraints: const BoxConstraints(
                            minWidth: CompensationTokens.touch,
                            minHeight: CompensationTokens.touch),
                        icon: const Icon(Icons.ios_share_rounded),
                      ),
                    ),
                    PositionedDirectional(
                      top: 0,
                      start: CompensationTokens.small,
                      child: IconButton(
                        tooltip: '返回',
                        color: CompensationTokens.ink(context),
                        onPressed: () => Navigator.of(context).maybePop(),
                        constraints: const BoxConstraints(
                            minWidth: CompensationTokens.touch,
                            minHeight: CompensationTokens.touch),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                    ),
                  ]))),
          bottomNavigationBar: d == null
              ? null
              : SafeArea(
                  top: false,
                  child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxWidth: CompensationTokens.maxWidth),
                          child: Padding(
                              padding: const EdgeInsets.all(
                                  CompensationTokens.space),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    CompensationAction(
                                        label: _buttonLabel(state),
                                        onPressed: _controller.busy
                                            ? null
                                            : () => _action(state)),
                                  ]))))),
        );
      });
  String _buttonLabel(CompensationState? state) {
    if (_controller.busy) return _controller.synchronized ? '领取中…' : '正在查询…';
    if (_controller.uncertain) return '查询领取结果';
    if (state == CompensationState.claimed) return '查看入账记录';
    if (!_controller.synchronized) return '重新查询活动';
    return switch (state) {
      CompensationState.unclaimed => '领取补偿红包',
      CompensationState.ended => '返回首页',
      CompensationState.ineligible => '查看参与规则',
      _ => '重新加载'
    };
  }

  Future<void> _action(CompensationState? state) async {
    if (_controller.uncertain) {
      await _controller.refresh();
      return;
    }
    if (state == CompensationState.claimed) {
      if (!_controller.source.sessionValid) {
        await _controller.refresh();
        return;
      }
      await openWalletPage<void>(
          context, const WalletRecordScreen(initialCoin: 'BI99'));
      if (mounted) await _controller.refresh();
      return;
    }
    if (!_controller.synchronized) {
      await _controller.refresh();
      return;
    }
    switch (state) {
      case CompensationState.unclaimed:
        await _controller.claim();
      case CompensationState.ended:
        if (mounted) Navigator.of(context).maybePop();
      case CompensationState.ineligible:
        _showRules();
      default:
        await _controller.refresh();
    }
  }
}
