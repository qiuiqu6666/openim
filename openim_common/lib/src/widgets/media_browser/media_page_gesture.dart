import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';

const mediaHorizontalDragRatio = 2.0;
final _pageDragDirections = Expando<bool>();

/// Use normal horizontal intent for gallery paging. ReadingImageGesture owns
/// the stricter axis lock needed while panning tall images.
bool acceptMediaPageDrag(Map<int, VelocityTracker> trackers) {
  if (trackers.length != 1) return false;
  final tracker = trackers.values.single;
  if (tracker is! ExtendedVelocityTracker) return false;
  final accepted = _pageDragDirections[tracker];
  if (accepted != null) return accepted;
  final delta = tracker.getSamplesDelta();
  // The page recognizer has already applied the device's touch slop before
  // calling this predicate. A second fixed threshold lets the image's scale
  // recognizer win on devices with a smaller slop, blocking fit-scale paging.
  if (delta == Offset.zero) return false;
  return _pageDragDirections[tracker] = delta.dx.abs() > delta.dy.abs();
}
