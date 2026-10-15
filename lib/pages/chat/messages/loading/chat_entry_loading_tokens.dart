import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

abstract final class ChatEntryLoadingTokens {
  static const revealDuration = Duration(milliseconds: 120);
  static const briefLoadThreshold = Duration(milliseconds: 100);
  static const briefRevealDuration = Duration(milliseconds: 80);
  static const pulseDuration = Duration(milliseconds: 1200);
  static const revealCurve = Curves.easeOutCubic;
  static const avatarExtent = 36.0;
  static const rowInset = 10.0;
  static const avatarGap = 10.0;
  static const lineHeightRatio = .65;
  static const minLineHeight = 8.0;
  static const maxLineHeight = 20.0;
  static const nameWidth = 76.0;
  static const timeWidth = 30.0;
  static const dateWidth = 62.0;
  static const rowEstimate = 92.0;
  static const maxRows = 12;
  static const mediaAspectRatio = 1.4;
  static const minPulseOpacity = .72;

  static Color fill(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Color.alphaBlend(
        Theme.of(context)
            .colorScheme
            .onSurface
            .withValues(alpha: dark ? .16 : .09),
        AppTokens.background(dark: dark));
  }

  static BorderRadius get lineRadius => BorderRadius.circular(AppTokens.rSm);

  static Color bubbleFill(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Color.alphaBlend(
        AppTokens.border(dark: dark), AppTokens.background(dark: dark));
  }
}
