import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Moves a focused single-line caret with a small intentional horizontal touch.
/// Native long presses, range handles and vertical form scrolling stay intact.
class SensitiveCaretRegion extends StatefulWidget {
  const SensitiveCaretRegion(
      {super.key, required this.child, this.focusNode, this.onDragStart});
  final Widget child;
  final FocusNode? focusNode;
  final VoidCallback? onDragStart;
  @override
  State<SensitiveCaretRegion> createState() => _SensitiveCaretRegionState();
}

class _SensitiveCaretRegionState extends State<SensitiveCaretRegion> {
  final _key = GlobalKey();
  Offset? _origin;
  Duration? _started;
  int? _pointer;
  bool _dragging = false;
  int _revision = 0;

  RenderEditable? _find(RenderObject? object) {
    if (object is RenderEditable) return object;
    RenderEditable? result;
    object?.visitChildren((child) => result ??= _find(child));
    return result;
  }

  void _down(PointerDownEvent event) {
    final editable = _find(_key.currentContext?.findRenderObject());
    if (event.kind != PointerDeviceKind.touch ||
        editable == null ||
        (!editable.hasFocus && widget.focusNode == null) ||
        editable.readOnly ||
        editable.selection?.isCollapsed != true) {
      return;
    }
    final local = editable.globalToLocal(event.position);
    if (!(Offset.zero & editable.size).contains(local)) return;
    _revision++;
    _origin = event.position;
    _started = event.timeStamp;
    _pointer = event.pointer;
    _dragging = false;
  }

  void _move(PointerMoveEvent event) {
    if (_origin == null || event.pointer != _pointer) return;
    final delta = event.position - _origin!;
    if (!_dragging) {
      if (event.timeStamp - _started! >= kLongPressTimeout ||
          delta.dy.abs() > delta.dx.abs()) {
        _reset();
        return;
      }
      if (delta.dx.abs() < 3) return;
      _dragging = true;
      widget.onDragStart?.call();
      widget.focusNode?.requestFocus();
    }
    _apply(event.position);
    // iOS's native drag recognizer also updates selection later in this event.
    // Reapply after it so swiping text moves the caret even away from the handle.
    final revision = _revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == _revision) _apply(event.position);
    });
  }

  void _apply(Offset position) {
    final editable = _find(_key.currentContext?.findRenderObject());
    if (editable == null || !editable.hasFocus || editable.readOnly) return;
    editable.selectPositionAt(
        from: position, cause: SelectionChangedCause.drag);
  }

  void _reset() {
    _origin = null;
    _started = null;
    _pointer = null;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (_) => _reset(),
      onPointerCancel: (_) {
        _revision++;
        _reset();
      },
      child: KeyedSubtree(key: _key, child: widget.child));
}
