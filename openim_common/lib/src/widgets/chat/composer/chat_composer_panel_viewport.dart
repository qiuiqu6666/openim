import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../toolbox/chat_toolbox_tokens.dart';

/// The Scaffold already reserves [keyboardHeight]. Reveal only the remaining
/// accessory area so the composer follows max(keyboard, panel), not their sum.
class ChatComposerPanelViewport extends StatelessWidget {
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
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        // Animate the panel's own target only. Native keyboard frames are
        // subtracted during layout, never fed through a second animation.
        tween: Tween(end: visible ? panelHeight : collapsedHeight),
        duration: animate && !MediaQuery.disableAnimationsOf(context)
            ? ChatToolboxTokens.panelAnimationDuration
            : Duration.zero,
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, extent, child) {
          final height = math.max(0.0, extent - keyboardHeight);
          return SizedBox(
            key: viewportKey,
            height: height,
            child: ClipRect(
              child: visible && height > 0
                  ? OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: panelHeight,
                      maxHeight: panelHeight,
                      child: child,
                    )
                  : const SizedBox.shrink(),
            ),
          );
        },
      );
}
