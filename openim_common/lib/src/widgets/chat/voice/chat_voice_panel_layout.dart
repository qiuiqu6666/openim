import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../res/chat_voice_tokens.dart';

enum ChatVoiceReleaseZone { send, cancel, convertText }

/// One geometry source for the visible controls and release hit testing.
class ChatVoiceControlsLayout {
  const ChatVoiceControlsLayout({
    required this.panelSize,
    required this.bottomInset,
    this.anchorCenter,
  });

  final Size panelSize;
  final double bottomInset;
  final Offset? anchorCenter;

  /// Idle and recording share this position; hints do not affect it.
  Offset get mainCenter =>
      anchorCenter ?? Offset(panelSize.width / 2, ChatVoiceTokens.mainCenterY);

  double get _sideDistance =>
      ChatVoiceTokens.micSize / 2 +
      ChatVoiceTokens.sideGap +
      ChatVoiceTokens.sideSize / 2;

  double _safeSideX(double desired) {
    final minimum = math.min(panelSize.width / 2,
        ChatVoiceTokens.horizontalInset + ChatVoiceTokens.sideSize / 2);
    final maximum = math.max(minimum, panelSize.width - minimum);
    return desired.clamp(minimum, maximum).toDouble();
  }

  Offset get cancelCenter =>
      Offset(_safeSideX(mainCenter.dx - _sideDistance), mainCenter.dy);

  Offset get convertCenter =>
      Offset(_safeSideX(mainCenter.dx + _sideDistance), mainCenter.dy);

  /// Status and waveform are contained inside the panel, above the controls.
  double get statusTopY => ChatVoiceTokens.headerTop;

  ChatVoiceReleaseZone hitTest(Offset local) {
    const radius = ChatVoiceTokens.sideSize / 2 + ChatVoiceTokens.hitOutset;
    if ((local - cancelCenter).distance <= radius) {
      return ChatVoiceReleaseZone.cancel;
    }
    if ((local - convertCenter).distance <= radius) {
      return ChatVoiceReleaseZone.convertText;
    }
    return ChatVoiceReleaseZone.send;
  }
}
