import 'package:flutter/widgets.dart';

/// Visibility and motion for returns to the latest message edge.
abstract final class ChatLatestScrollTokens {
  static const hintShowViewportRatio = 0.5;
  static const hintHideViewportRatio = 0.45;
  static const fallbackViewportDimension = 600.0;
  static const minDuration = Duration(milliseconds: 300);
  static const maxDuration = Duration(milliseconds: 650);
  static const correctionDuration = Duration(milliseconds: 140);
  static const curve = Curves.easeInCubic;
  static const distanceEpsilon = 1.0;
  static const correctionAttempts = 4;
  static const millisecondsPerViewport = 60;

  static Duration durationFor(double distance, double viewportDimension) {
    final viewports =
        distance.abs() / (viewportDimension > 0 ? viewportDimension : 1);
    final milliseconds = minDuration.inMilliseconds +
        (viewports * millisecondsPerViewport).round();
    return Duration(
        milliseconds: milliseconds.clamp(
            minDuration.inMilliseconds, maxDuration.inMilliseconds));
  }
}
