import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'chat_message_menu_tokens.dart';

class ChatMessageMenuLayout {
  const ChatMessageMenuLayout(
      {required this.panel, required this.below, required this.arrowLeft});
  final Rect panel;
  final bool below;
  final double arrowLeft;
}

/// Use the message's side and choose the roomier vertical side, as in 99chat.
ChatMessageMenuLayout resolveChatMessageMenuLayout({
  required Rect anchor,
  required bool outgoing,
  required Size viewport,
  required double safeTop,
  required double safeBottom,
  required double desiredHeight,
  Offset? touch,
}) {
  const edge = ChatMessageMenuTokens.edgePadding;
  const gap = ChatMessageMenuTokens.gap;
  final width = math.max(0.0,
      math.min(ChatMessageMenuTokens.panelWidth, viewport.width - edge * 2));
  final bottom = math.max(safeTop, safeBottom);
  var target = anchor;
  // Very tall messages can fill the viewport. Keep all actions reachable near
  // the finger rather than positioning the menu at an off-screen bubble edge.
  if (anchor.height + desiredHeight + gap * 2 > bottom - safeTop) {
    final y = (touch?.dy ?? anchor.center.dy).clamp(safeTop, bottom).toDouble();
    target = Rect.fromLTWH(anchor.left, y, anchor.width, 0);
  }
  final roomBelow = bottom - target.bottom - gap;
  final roomAbove = target.top - safeTop - gap;
  final below = roomBelow >= roomAbove;
  final height = math.min(desiredHeight, math.max(0.0, bottom - safeTop));
  final idealTop = below ? target.bottom + gap : target.top - gap - height;
  final top =
      idealTop.clamp(safeTop, math.max(safeTop, bottom - height)).toDouble();
  final left = (outgoing ? target.right - width : target.left)
      .clamp(math.min(edge, viewport.width),
          math.max(edge, viewport.width - width - edge))
      .toDouble();
  final arrowLeft = (target.center.dx - ChatMessageMenuTokens.arrowWidth / 2)
      .clamp(
          left + ChatMessageMenuTokens.radius,
          math.max(
              left + ChatMessageMenuTokens.radius,
              left +
                  width -
                  ChatMessageMenuTokens.radius -
                  ChatMessageMenuTokens.arrowWidth))
      .toDouble();
  return ChatMessageMenuLayout(
      panel: Rect.fromLTWH(left, top, width, height),
      below: below,
      arrowLeft: arrowLeft);
}
