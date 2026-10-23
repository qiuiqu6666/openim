import 'package:flutter/widgets.dart';

/// Travel is based on measured viewport geometry, never message counts.
abstract final class ChatPositionMotion {
  static const curve = Curves.easeOutCubic;
  static const farViewportThreshold = 3.0;
  static const entranceViewportRatio = .28;
  static const entranceDuration = Duration(milliseconds: 200);
  static const correctionDuration = Duration(milliseconds: 100);

  static Duration durationFor(double distance, double viewport,
      {bool latest = false}) {
    final screens = distance.abs() / (viewport > 0 ? viewport : 1);
    if (latest) {
      return Duration(milliseconds: screens <= 1 ? 220 : 300);
    }
    return Duration(milliseconds: screens <= 1 ? 220 : 300);
  }
}
