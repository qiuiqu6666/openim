import 'package:flutter/material.dart';

import 'chat_toolbox_tokens.dart';

/// Keeps the composer safe area stable while revealing the mobile more panel.
class ChatComposerToolboxSlot extends StatelessWidget {
  const ChatComposerToolboxSlot({
    super.key,
    required this.visible,
    required this.safeBottom,
    required this.collapsedHeight,
    required this.child,
    this.animate = true,
  });

  final bool visible;
  final double safeBottom;
  final double collapsedHeight;
  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final panelHeight = ChatToolboxTokens.panelHeight + safeBottom;
    return AnimatedContainer(
      key: const ValueKey('chat-toolbox-panel-slot'),
      duration: animate && !MediaQuery.disableAnimationsOf(context)
          ? ChatToolboxTokens.panelAnimationDuration
          : Duration.zero,
      curve: Curves.easeOutCubic,
      height: visible ? panelHeight : collapsedHeight,
      alignment: Alignment.topCenter,
      decoration: const BoxDecoration(),
      clipBehavior: Clip.hardEdge,
      child: visible
          ? OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: panelHeight,
              maxHeight: panelHeight,
              child: child,
            )
          : const SizedBox.shrink(),
    );
  }
}
