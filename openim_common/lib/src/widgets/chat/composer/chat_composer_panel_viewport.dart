import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../toolbox/chat_toolbox_tokens.dart';

/// The Scaffold already reserves [keyboardHeight]. Reveal only the remaining
/// accessory area so the composer follows max(keyboard, panel), not their sum.
class ChatComposerPanelViewport extends StatefulWidget {
  const ChatComposerPanelViewport({
    super.key,
    required this.visible,
    required this.panelHeight,
    required this.child,
    this.collapsedHeight = 0,
    this.keyboardHeight = 0,
    this.animate = false,
    this.viewportKey,
  });

  final bool visible;
  final double panelHeight;
  final double collapsedHeight;
  final double keyboardHeight;
  final bool animate;
  final Key? viewportKey;
  final Widget child;

  @override
  State<ChatComposerPanelViewport> createState() =>
      _ChatComposerPanelViewportState();
}

class _ChatComposerPanelViewportState extends State<ChatComposerPanelViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: ChatToolboxTokens.panelAnimationDuration,
    value: 1,
  );
  late double _begin = _target;
  late double _end = _target;
  bool _motionEnabled = false;

  double get _target =>
      widget.visible ? widget.panelHeight : widget.collapsedHeight;
  double get _extent =>
      _begin +
      (_end - _begin) * Curves.easeOutCubic.transform(_animation.value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionEnabled = !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent != false;
    _syncTarget();
  }

  @override
  void didUpdateWidget(covariant ChatComposerPanelViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTarget();
  }

  void _syncTarget() {
    final target = _target;
    if (!widget.animate || !_motionEnabled) {
      // A covered route must settle now: muted tickers otherwise retain the
      // old panel height and move the message viewport when the user returns.
      _begin = _end = target;
      _animation.value = 1;
    } else if (_end != target) {
      _begin = _extent;
      _end = target;
      _animation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (context, child) {
          // Native keyboard frames are subtracted directly, never animated twice.
          final height = math.max(0.0, _extent - widget.keyboardHeight);
          return SizedBox(
            key: widget.viewportKey,
            height: height,
            child: ClipRect(
              child: widget.visible && height > 0
                  ? OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: widget.panelHeight,
                      maxHeight: widget.panelHeight,
                      child: child,
                    )
                  : const SizedBox.shrink(),
            ),
          );
        },
      );
}
