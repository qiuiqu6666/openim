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
  if (delta.distance < kTouchSlop) return false;
  return _pageDragDirections[tracker] =
      delta.dx.abs() > delta.dy.abs();
}
