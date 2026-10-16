import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

abstract final class ChatEntryLoadingTokens {
  static const revealDuration = Duration(milliseconds: 120);
  static const briefLoadThreshold = Duration(milliseconds: 100);
  static const briefRevealDuration = Duration(milliseconds: 80);
  static const sweepDuration = Duration(milliseconds: 1800);
  static const revealCurve = Curves.easeOutCubic;
  static const avatarExtent = 36.0;
  static const rowInset = 10.0;
  static const avatarGap = 10.0;
  static const lineHeightRatio = .5;
  static const minLineHeight = 8.0;
  static const maxLineHeight = 14.0;
  static const metadataHeight = 6.0;
  static const nameHeight = 8.0;
  static const secondaryStrength = .55;
  static const bubbleWidthFactors = [.62, .9, .76, .54, .84];
  static const lineCounts = [1, 3, 2, 1, 2];
  static const lastLineFactors = [.72, .56, .64, .82, .48];
  static const nameWidth = 76.0;
  static const timeWidth = 30.0;
  static const dateWidth = 62.0;
  static const rowEstimate = 92.0;
  static const maxRows = 12;
  static const mediaAspectRatio = 1.4;
  static Color sweepHighlight(BuildContext context) =>
      AppTokens.onAccent.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .10 : .55);

  static Color fill(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Color.alphaBlend(
        AppTokens.accent.withValues(alpha: dark ? .16 : .09),
        AppTokens.surfaceAlt(dark: dark));
  }

  static Color secondaryFill(BuildContext context) =>
      Color.lerp(bubbleFill(context), fill(context), secondaryStrength)!;

  static BorderRadius get lineRadius => BorderRadius.circular(AppTokens.rSm);

  static Color bubbleFill(BuildContext context, {bool outgoing = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = AppTokens.surface(dark: dark);
    return outgoing
        ? Color.lerp(
            surface, ChatBubbleTokens.outgoing(dark: dark), dark ? .14 : .65)!
        : surface;
  }
}
