import 'package:flutter/widgets.dart';

/// Visibility and motion for returns to the latest message edge.
abstract final class ChatLatestScrollTokens {
  static const hintShowViewportRatio = 0.5;
  static const hintHideViewportRatio = 0.45;
  static const fallbackViewportDimension = 600.0;
  static const correctionDuration = Duration(milliseconds: 140);
  static const curve = Curves.easeOutCubic;
  static const distanceEpsilon = 1.0;
  static const leaveLatestDistance = 48.0;
  static const rejoinLatestDistance = 24.0;
  static const correctionAttempts = 4;
  static const farViewportThreshold = 3.0;

  static Duration durationFor(double distance, double viewportDimension) {
    final viewports =
        distance.abs() / (viewportDimension > 0 ? viewportDimension : 1);
    return Duration(milliseconds: viewports <= 1 ? 220 : 300);
  }
}
