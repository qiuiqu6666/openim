import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:openim_common/openim_common.dart';
import '../casting/live_cast_button.dart';
import '../models/live_errors.dart';
import '../widgets/live_style.dart';
import '../widgets/live_watching_bottom_bar.dart';
import 'live_playback_controller.dart';

class LivePlayerView extends StatefulWidget {
  const LivePlayerView(
      {super.key,
      required this.controller,
      this.onClose,
      this.onFullscreen,
      this.fullscreen = false,
      this.onRetry,
      this.onResume,
      this.onTip,
      this.canTip,
      this.renewalOwner,
      this.roomName = '',
      this.description = '',
      this.anchorID = '',
      this.anchorFaceURL = ''});
  final LivePlaybackController controller;
  final VoidCallback? onClose;
  final VoidCallback? onFullscreen;
  final bool fullscreen;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onResume;
  final VoidCallback? onTip;
  final bool Function()? canTip;
  final Object? renewalOwner;
  final String roomName, description;
  final String anchorID, anchorFaceURL;
  @override
  State<LivePlayerView> createState() => _LivePlayerViewState();
}

class _LivePlayerViewState extends State<LivePlayerView>
    with WidgetsBindingObserver {
  bool _fullscreenOpen = false;
  final _surface = Object(), _fullscreenHandoff = Object();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVisibility();
  }

  void _syncVisibility() {
    final visible = ModalRoute.of(context)?.isCurrent != false;
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(controller, widget.controller)) return;
      unawaited(controller.setSurfaceVisible(_surface, visible,
          owner: widget.renewalOwner));
    });
  }

  @override
  void didUpdateWidget(covariant LivePlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      unawaited(oldWidget.controller.removeSurface(_surface));
      _syncVisibility();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // All surfaces report the same application state; the shared owner merges it.
    unawaited(
        widget.controller.setForeground(state == AppLifecycleState.resumed));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.controller.removeSurface(_surface));
    unawaited(widget.controller.removeSurface(_fullscreenHandoff));
    super.dispose();
  }

  Future<void> _fullscreen() async {
    if (widget.fullscreen) {
      Navigator.of(context).pop();
      return;
    }
    if (_fullscreenOpen || !widget.controller.current) return;
    final controller = widget.controller;
    final navigator = Navigator.of(context, rootNavigator: true);
    final onRetry = widget.onRetry;
    final onTip = widget.onTip;
    final canTip = widget.canTip;
    final renewalOwner = widget.renewalOwner;
    final roomName = widget.roomName;
    final description = widget.description;
    final anchorID = widget.anchorID;
    final anchorFaceURL = widget.anchorFaceURL;
    setState(() => _fullscreenOpen = true);
    // Hold visibility until the fullscreen child owns its lease, without a pause
    // between two views of the same native player.
    unawaited(controller.setSurfaceVisible(_fullscreenHandoff, true,
        owner: renewalOwner));
    final route = MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
            backgroundColor: LiveStyle.screen,
            body: SafeArea(
                child: LivePlayerView(
                    controller: controller,
                    fullscreen: true,
                    onRetry: onRetry,
                    onTip: onTip,
                    canTip: canTip,
                    renewalOwner: renewalOwner,
                    roomName: roomName,
                    description: description,
                    anchorID: anchorID,
                    anchorFaceURL: anchorFaceURL,
                    onClose: () =>
                        Navigator.of(routeContext, rootNavigator: true)
                            .pop()))));
    var closeRequested = false;
    final subscription = controller.closeEvents.listen((_) {
      if (closeRequested) return;
      closeRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!navigator.mounted || !route.isActive) return;
        if (route.isCurrent) {
          navigator.pop<void>();
        } else {
          // A newer route may cover the player. Never pop that unrelated page.
          navigator.removeRoute(route);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    try {
      final completed = navigator.push<void>(route);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // The child registers at the end of this frame too. Release after all
        // frame callbacks so their ordering cannot briefly pause the decoder.
        scheduleMicrotask(
            () => unawaited(controller.removeSurface(_fullscreenHandoff)));
      });
      await completed;
    } finally {
      await subscription.cancel();
      unawaited(controller.removeSurface(_fullscreenHandoff));
      if (mounted) setState(() => _fullscreenOpen = false);
    }
  }

  Future<void> _mute() async {
    final controller = widget.controller;
    if (controller.muteError != null) {
      await controller.setMuted(controller.muted);
    } else {
      await controller.toggleMute();
    }
    if (mounted && controller.current && controller.muteError != null) {
      IMViews.showToast('声音设置失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller;
        final player = state.player;
        return ColoredBox(
            color: LiveStyle.screen,
            child: Stack(fit: StackFit.expand, children: [
              if (!_fullscreenOpen &&
                  player != null &&
                  player.value.isInitialized)
                Center(
                    child: AspectRatio(
                        aspectRatio: player.value.aspectRatio,
                        child: VideoPlayer(player))),
              if (!state.current)
                const Center(
                    child: Text('直播会话已失效',
                        style: TextStyle(color: LiveStyle.screenInk))),
              if (state.current && state.loading)
                const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: LiveStyle.screenInk)),
                  SizedBox(height: 8),
                  Text('正在连接直播…', style: TextStyle(color: LiveStyle.screenInk))
                ])),
              if (state.current && state.error != null)
                Center(
                    child: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(liveErrorMessage(state.error!),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: LiveStyle.screenInk)),
                                  TextButton(
                                      onPressed: () => unawaited(
                                          widget.onRetry?.call() ??
                                              state.open(nextSource: true)),
                                      child: const Text('重新连接'))
                                ])))),
              Positioned(
                  top: 4,
                  left: 8,
                  right: 8,
                  child: Row(children: [
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: LiveStyle.red,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Text('● 直播中',
                            style: TextStyle(
                                color: LiveStyle.screenInk,
                                fontSize: 12,
                                height: 1.1,
                                fontWeight: FontWeight.w600))),
                    const Spacer(),
                    const LiveCastButton(),
                    if (widget.onTip != null &&
                        state.current &&
                        widget.canTip?.call() != false)
                      IconButton(
                          tooltip: '打赏主播',
                          icon: const Icon(Icons.card_giftcard_outlined,
                              color: LiveStyle.screenInk, size: 22),
                          onPressed: widget.onTip),
                    IconButton(
                        tooltip: state.muteError != null
                            ? '重试声音设置'
                            : state.muted
                                ? '打开声音'
                                : '静音',
                        icon: Icon(
                            state.muted
                                ? Icons.volume_off_outlined
                                : Icons.volume_up_outlined,
                            color: LiveStyle.screenInk,
                            size: 22),
                        onPressed:
                            state.current ? () => unawaited(_mute()) : null),
                    if (widget.onClose != null)
                      IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close,
                              color: LiveStyle.screenInk, size: 22),
                          onPressed: widget.onClose),
                  ])),
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 88,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                            Colors.transparent,
                            LiveStyle.screen.withValues(alpha: .6)
                          ])),
                      child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: LiveWatchingBottomBar(
                                  roomName: widget.roomName.isEmpty
                                      ? widget.controller.info.roomName
                                      : widget.roomName,
                                  description: widget.description,
                                  anchorID: widget.anchorID.isEmpty
                                      ? widget.controller.info.anchorID
                                      : widget.anchorID,
                                  anchorFaceURL: widget.anchorFaceURL,
                                  fullscreen: widget.fullscreen,
                                  onFullscreen:
                                      widget.onFullscreen ?? _fullscreen))))),
            ]));
      });
}
