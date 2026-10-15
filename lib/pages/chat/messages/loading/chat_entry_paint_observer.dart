import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Observes actual content paint, including opacity/route animation frames.
/// Does not change geometry, hit testing, or receipt visibility.
class ChatEntryPaintObserver extends SingleChildRenderObjectWidget {
  const ChatEntryPaintObserver(
      {super.key,
      required this.animation,
      required this.onPainted,
      required this.shouldObserve,
      required super.child});
  final Listenable animation;
  final VoidCallback onPainted;
  final bool Function() shouldObserve;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintObserver(animation, onPainted, shouldObserve);
  @override
  void updateRenderObject(
      BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _PaintObserver)
      ..animation = animation
      ..shouldObserve = shouldObserve
      ..onPainted = onPainted;
  }
}

class _PaintObserver extends RenderProxyBox {
  _PaintObserver(this._animation, this.onPainted, this.shouldObserve);
  Listenable _animation;
  VoidCallback onPainted;
  bool Function() shouldObserve;
  void _tick() {
    if (shouldObserve()) markNeedsPaint();
  }

  set animation(Listenable value) {
    if (identical(value, _animation)) return;
    if (attached) _animation.removeListener(_tick);
    _animation = value;
    if (attached) _animation.addListener(_tick);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_tick);
  }

  @override
  void detach() {
    _animation.removeListener(_tick);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!shouldObserve()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && shouldObserve()) onPainted();
    });
  }
}
