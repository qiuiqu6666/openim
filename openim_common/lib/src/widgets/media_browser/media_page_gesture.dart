import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';

/// Reserve diagonal/vertical drags and multi-touch for the image recognizer.
bool acceptMediaPageDrag(Map<int, VelocityTracker> trackers) {
  if (trackers.length != 1) return false;
  final tracker = trackers.values.single;
  if (tracker is! ExtendedVelocityTracker) return false;
  final delta = tracker.getSamplesDelta();
  return delta.dx.abs() > delta.dy.abs() * 1.5;
}
