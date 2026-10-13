import 'package:flutter/material.dart';

import 'chat_toolbox_tokens.dart';
import '../composer/chat_composer_panel_viewport.dart';

/// Keeps the composer safe area stable while revealing the mobile more panel.
class ChatComposerToolboxSlot extends StatelessWidget {
  const ChatComposerToolboxSlot({
    super.key,
    required this.visible,
    required this.safeBottom,
    required this.collapsedHeight,
    required this.child,
    this.animate = true,
    this.keyboardHeight = 0,
  });

  final bool visible;
  final double safeBottom;
  final double collapsedHeight;
  final Widget child;
  final bool animate;
  final double keyboardHeight;

  @override
  Widget build(BuildContext context) {
    final panelHeight = ChatToolboxTokens.panelHeight + safeBottom;
    return ChatComposerPanelViewport(
      viewportKey: const ValueKey('chat-toolbox-panel-slot'),
      visible: visible,
      panelHeight: panelHeight,
      collapsedHeight: collapsedHeight,
      keyboardHeight: keyboardHeight,
      animate: animate,
      child: child,
    );
  }
}
