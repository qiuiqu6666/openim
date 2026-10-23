import 'package:flutter/material.dart';

/// Horizontal back intent competes normally with the grid's vertical scrolling.
/// The visible back button remains the accessible alternative to this gesture.
class MediaGridBackGesture extends StatefulWidget {
  const MediaGridBackGesture({
    super.key,
    required this.onBack,
    required this.child,
  });

  final VoidCallback onBack;
  final Widget child;

  @override
  State<MediaGridBackGesture> createState() => _MediaGridBackGestureState();
}

class _MediaGridBackGestureState extends State<MediaGridBackGesture> {
  double _distance = 0;
  bool _cancelled = false;
  static const _minimumDistance = 64.0;
  static const _minimumFlingDistance = 20.0;
  static const _minimumVelocity = 700.0;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onHorizontalDragStart: (_) => _distance = 0,
      onHorizontalDragUpdate: (details) =>
          _distance += details.delta.dx * direction,
      onHorizontalDragCancel: () => _distance = 0,
      onHorizontalDragEnd: (details) {
        final velocity = (details.primaryVelocity ?? 0) * direction;
        final shouldBack = _distance >= _minimumDistance ||
            (_distance >= _minimumFlingDistance &&
                velocity >= _minimumVelocity);
        _distance = 0;
        if (shouldBack && !_cancelled) widget.onBack();
      },
      child: Listener(
        onPointerDown: (_) => _cancelled = false,
        onPointerCancel: (_) => _cancelled = true,
        child: widget.child,
      ),
    );
  }
}
