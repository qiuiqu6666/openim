import 'package:flutter/animation.dart';

/// Shared motion tuned against IMG_0076.MP4; gesture thresholds stay unchanged.
abstract final class AppSwipeBackTokens {
  static const edgeWidth = 24.0;
  static const chatEdgeWidth = 40.0;
  static const walletOverlayEdgeWidth = 96.0;
  static const distanceFraction = 0.16;
  static const velocity = 320.0;
  static const transitionDuration = Duration(milliseconds: 480);
  static const curve = Curves.fastEaseInToSlowEaseOut;
  static const reverseCurve = FlippedCurve(curve);
  static const parallaxFraction = 0.25;
  static const scrimOpacity = 0.08;
  static const edgeShadowOpacity = 0.12;
  static const edgeShadowBlur = 12.0;

  /// Opt-out for media viewers/players that own their horizontal gestures.
  static const mediaRouteName = '/media_preview';
}
