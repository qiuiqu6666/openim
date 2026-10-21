import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Observes native pointer delivery without taking scrolling away from WebView.
/// Only downward movement after the document reaches its top moves the sheet.
class InAppBrowserEdgeDrag extends StatefulWidget {
  const InAppBrowserEdgeDrag({
    super.key,
    required this.atTop,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required this.child,
  });

  final bool Function() atTop;
  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final ValueChanged<double> onEnd;
  final VoidCallback onCancel;
  final Widget child;

  @override
  State<InAppBrowserEdgeDrag> createState() => _InAppBrowserEdgeDragState();
}

class _InAppBrowserEdgeDragState extends State<InAppBrowserEdgeDrag> {
  final _pointers = <int>{};
  Offset _travel = Offset.zero;
  VelocityTracker? _velocity;
  bool _dragging = false;
  bool _blocked = false;

  void _down(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_pointers.length > 1) {
      if (_dragging) widget.onCancel();
      _dragging = false;
      _blocked = true;
      return;
    }
    _travel = Offset.zero;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _move(PointerMoveEvent event) {
    if (_blocked || _pointers.length != 1) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    if (_dragging) {
      widget.onUpdate(event.delta.dy);
      return;
    }
    if (!widget.atTop()) {
      _travel = Offset.zero;
      return;
    }
    _travel += event.delta;
    _travel = Offset(_travel.dx, _travel.dy.clamp(0.0, double.infinity));
    if (_travel.dx.abs() > kTouchSlop && _travel.dx.abs() > _travel.dy) {
      _blocked = true;
    } else if (_travel.dy > kTouchSlop && _travel.dy > _travel.dx.abs()) {
      _dragging = true;
      widget.onStart();
      // Do not include the touch slop or movement used to scroll to the top.
      widget.onUpdate(_travel.dy - kTouchSlop);
    }
  }

  void _finish(PointerEvent event, {bool cancelled = false}) {
    if (!_pointers.remove(event.pointer)) return;
    if (_dragging) {
      _velocity?.addPosition(event.timeStamp, event.position);
      if (cancelled) {
        widget.onCancel();
      } else {
        widget.onEnd(_velocity?.getVelocity().pixelsPerSecond.dy ?? 0);
      }
    }
    _dragging = false;
    if (_pointers.isEmpty) {
      _blocked = false;
      _velocity = null;
      _travel = Offset.zero;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _finish,
        onPointerCancel: (event) => _finish(event, cancelled: true),
        child: widget.child,
      );
}
