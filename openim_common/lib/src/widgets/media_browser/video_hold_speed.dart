import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../res/app_tokens.dart';

/// Temporary edge-hold speed, with serialized native calls so release wins
/// even when the platform is still applying the initial speed change.
class VideoHoldSpeed extends StatefulWidget {
  const VideoHoldSpeed(
      {super.key,
      required this.controller,
      required this.blocked,
      required this.onBusyChanged});

  final VideoPlayerController controller;
  final bool blocked;
  final ValueChanged<bool> onBusyChanged;

  @override
  State<VideoHoldSpeed> createState() => _VideoHoldSpeedState();
}

class _VideoHoldSpeedState extends State<VideoHoldSpeed>
    with WidgetsBindingObserver {
  double? _originalSpeed;
  bool _holding = false;
  Future<void> _pending = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _start() {
    if (widget.blocked ||
        _originalSpeed != null ||
        !widget.controller.value.isPlaying) {
      return;
    }
    final controller = widget.controller;
    _originalSpeed = controller.value.playbackSpeed;
    widget.onBusyChanged(true);
    setState(() => _holding = true);
    _pending = _pending.then((_) async {
      try {
        await controller.setPlaybackSpeed(2);
      } catch (_) {
        _end();
      }
    });
  }

  void _end() {
    if (!_holding) return;
    _holding = false;
    final original = _originalSpeed!;
    final controller = widget.controller;
    if (mounted) setState(() {});
    _pending = _pending.then((_) async {
      try {
        await controller.setPlaybackSpeed(original);
      } catch (_) {
        // A failed restore must not leave a playing video at temporary speed.
        try {
          await controller.pause();
        } catch (_) {}
      } finally {
        _originalSpeed = null;
        if (mounted) widget.onBusyChanged(false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _end();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Do not notify or rebuild while the parent tree is being removed.
    if (_holding) {
      _holding = false;
      final controller = widget.controller;
      final original = _originalSpeed!;
      unawaited(_pending.then((_) async {
        try {
          await controller.setPlaybackSpeed(original);
        } catch (_) {}
      }));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        for (final alignment in [Alignment.centerLeft, Alignment.centerRight])
          Positioned.fill(
              child: Align(
            alignment: alignment,
            child: FractionallySizedBox(
              widthFactor: AppTokens.videoHoldEdgeFraction,
              heightFactor: 1,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                excludeFromSemantics: true,
                onLongPressStart: (_) => _start(),
                onLongPressEnd: (_) => _end(),
                onLongPressCancel: _end,
                child: const SizedBox.expand(),
              ),
            ),
          )),
        if (_holding)
          Positioned(
            top: MediaQuery.paddingOf(context).top + AppTokens.videoHoldHintTop,
            left: 0,
            right: 0,
            child: IgnorePointer(
                child: Center(
                    child: Semantics(
              liveRegion: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: AppTokens.videoHoldHintBackground,
                    borderRadius:
                        BorderRadius.circular(AppTokens.videoHoldHintRadius)),
                child: Padding(
                    padding: AppTokens.videoHoldHintPadding,
                    child: Text('2倍速播放',
                        style: AppTokens.videoSpeedTextStyle
                            .copyWith(color: AppTokens.onAccent))),
              ),
            ))),
          ),
      ]);
}
