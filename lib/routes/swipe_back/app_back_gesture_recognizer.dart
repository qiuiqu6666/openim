import 'package:flutter/gestures.dart';

/// Same edge direction arbitration as 99chat, with pointer cancellation and
/// multiple fingers isolated from the active route gesture.
class AppBackGestureRecognizer extends OneSequenceGestureRecognizer {
  AppBackGestureRecognizer({
    required this.isAllowed,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final bool Function() isAllowed;
  final bool Function() onStart;
  final void Function(double) onUpdate;
  final void Function(double distance, double velocity) onEnd;
  final void Function() onCancel;
  int? _pointer;
  Offset? _start;
  VelocityTracker? _tracker;
  bool _accepted = false;
  double _distance = 0;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _pointer == null && isAllowed() && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _start = event.position;
    _distance = 0;
    _accepted = false;
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    startTrackingPointer(event.pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _tracker!.addPosition(event.timeStamp, event.position);
      if (!_accepted) {
        final delta = event.position - _start!;
        // Decide intent after touch slop, not sub-pixel finger jitter. Rejecting
        // immediately lets a scrollable win even when the next move is right.
        if (delta.distance < computeHitSlop(event.kind, gestureSettings)) {
          return;
        }
        if (delta.dx <= 0 || delta.dx.abs() <= delta.dy.abs() * 0.8) {
          resolve(GestureDisposition.rejected);
          return;
        }
        _accepted = true;
        resolve(GestureDisposition.accepted);
        if (!_accepted) return;
        if (!onStart()) {
          _clear();
          return;
        }
        _distance = delta.dx;
        onUpdate(delta.dx);
        return;
      }
      _distance += event.delta.dx;
      onUpdate(event.delta.dx);
    } else if (event is PointerUpEvent) {
      if (_accepted) {
        onEnd(_distance, _tracker!.getVelocity().pixelsPerSecond.dx);
      } else {
        resolve(GestureDisposition.rejected);
      }
      _clear();
    } else if (event is PointerCancelEvent) {
      if (_accepted) onCancel();
      resolve(GestureDisposition.rejected);
      _clear();
    }
  }

  void _clear() {
    final pointer = _pointer;
    _pointer = null;
    _accepted = false;
    _start = null;
    _tracker = null;
    _distance = 0;
    if (pointer != null) stopTrackingPointer(pointer);
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    if (_accepted) onCancel();
    _clear();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'appEdgeBack';
}
