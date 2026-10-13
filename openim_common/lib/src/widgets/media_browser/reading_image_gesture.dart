import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'media_page_gesture.dart';

/// Keep a reading drag on its initial axis, including ExtendedImage's direct
/// image-to-gallery handoff (which bypasses the gallery's drag recognizer).
class ReadingImageGesture extends ExtendedImageGesture {
  const ReadingImageGesture(super.extendedImageState, {super.key});

  @override
  ExtendedImageGestureState createState() => _ReadingImageGestureState();
}

class _ReadingImageGestureState extends ExtendedImageGestureState {
  Offset _start = Offset.zero;
  Axis? _axis;
  bool _canDismiss = false;
  bool _dismiss = false;
  bool _multiplePointers = false;

  @override
  void handleScaleStart(ScaleStartDetails details) {
    super.handleScaleStart(details);
    _start = details.focalPoint;
    _axis = null;
    _dismiss = false;
    _multiplePointers = details.pointerCount > 1;
    final base = imageGestureConfig!.initialScale;
    _canDismiss = base > 1 &&
        (gestureDetails?.totalScale ?? base) <= base * 1.01 &&
        gestureDetails?.boundary.top == true;
  }

  @override
  void handleScaleUpdate(ScaleUpdateDetails details) {
    _multiplePointers |= details.pointerCount > 1 || details.scale != 1;
    final page = extendedImageSlidePageState;
    if (_multiplePointers) {
      if (_dismiss && page?.isSliding == true) {
        // A second finger cancels dismissal rather than closing during a pinch.
        page!.slide(-page.offset, extendedImageGestureState: this);
        page.endSlide(ScaleEndDetails());
      }
      _dismiss = false;
      super.handleScaleUpdate(_filtered(details, delta: Offset.zero));
      return;
    }
    if (_axis == null) {
      final delta = details.focalPoint - _start;
      if (delta.distance < kTouchSlop) return;
      final ratio =
          imageGestureConfig!.initialScale > 1 ? mediaHorizontalDragRatio : 1.0;
      _axis = delta.dx.abs() > delta.dy.abs() * ratio
          ? Axis.horizontal
          : Axis.vertical;
      _dismiss = _axis == Axis.vertical && delta.dy > 0 && _canDismiss;
    }
    if (_dismiss && page != null) {
      page.slide(Offset(0, details.focalPointDelta.dy),
          extendedImageGestureState: this);
      return;
    }
    if (_axis == Axis.vertical) {
      // Filter both displacement and velocity: a horizontal wobble must not
      // hand this drag to the next image or introduce sideways inertia.
      super.handleScaleUpdate(_filtered(
        details,
        focal: Offset(_start.dx, details.focalPoint.dy),
        delta: Offset(0, details.focalPointDelta.dy),
      ));
    } else {
      super.handleScaleUpdate(_filtered(details,
          focal: Offset(details.focalPoint.dx, _start.dy),
          delta: Offset(details.focalPointDelta.dx, 0)));
    }
  }

  ScaleUpdateDetails _filtered(ScaleUpdateDetails details,
          {Offset? focal, required Offset delta}) =>
      ScaleUpdateDetails(
        focalPoint: focal ?? details.focalPoint,
        localFocalPoint: details.localFocalPoint +
            ((focal ?? details.focalPoint) - details.focalPoint),
        focalPointDelta: delta,
        scale: details.scale,
        horizontalScale: details.horizontalScale,
        verticalScale: details.verticalScale,
        rotation: details.rotation,
        pointerCount: details.pointerCount,
        sourceTimeStamp: details.sourceTimeStamp,
      );

  @override
  void handleScaleEnd(ScaleEndDetails details) {
    super.handleScaleEnd(_axis == Axis.vertical && !_multiplePointers
        ? ScaleEndDetails(
            velocity: Velocity(
                pixelsPerSecond:
                    Offset(0, details.velocity.pixelsPerSecond.dy)),
            scaleVelocity: details.scaleVelocity,
            pointerCount: details.pointerCount,
          )
        : details);
  }
}
