import 'package:flutter/animation.dart';

/// Interaction values from reference-99chat's full_screen_back_route.dart.
abstract final class AppSwipeBackTokens {
  static const edgeWidth = 24.0;
  static const chatEdgeWidth = 40.0;
  static const walletOverlayEdgeWidth = 96.0;
  static const distanceFraction = 0.16;
  static const velocity = 320.0;
  static const transitionDuration = Duration(milliseconds: 340);
  static const cancelDuration = Duration(milliseconds: 120);
  static const curve = Curves.fastEaseInToSlowEaseOut;
  static const recededScale = 0.96;
  static const scrimOpacity = 0.55;

  /// Opt-out for media viewers/players that own their horizontal gestures.
  static const mediaRouteName = '/media_preview';
}
