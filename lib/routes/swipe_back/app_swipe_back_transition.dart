import 'package:flutter/material.dart';
import 'app_route_depth_transition.dart';
import 'app_swipe_back_interactor.dart';

class AppSwipeBackTransition extends StatefulWidget {
  const AppSwipeBackTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.pushCurve,
    required this.popCurve,
    required this.edgeStartWidthPx,
    required this.enableBackGesture,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Curve pushCurve;
  final Curve popCurve;
  final double edgeStartWidthPx;
  final bool enableBackGesture;
  final Widget child;

  @override
  State<AppSwipeBackTransition> createState() => _AppSwipeBackTransitionState();
}

class _AppSwipeBackTransitionState extends State<AppSwipeBackTransition> {
  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(1.0, 0.0),
    end: Offset.zero,
  );

  late CurvedAnimation _curvedAnimation;
  late Animation<Offset> _position;
  late Widget _stableGestureLayer;

  @override
  void initState() {
    super.initState();
    _bindAnimation();
    _rebuildGestureLayer();
  }

  @override
  void didUpdateWidget(covariant AppSwipeBackTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation) ||
        oldWidget.pushCurve != widget.pushCurve ||
        oldWidget.popCurve != widget.popCurve) {
      _curvedAnimation.dispose();
      _bindAnimation();
    }
    if (!identical(oldWidget.child, widget.child) ||
        oldWidget.edgeStartWidthPx != widget.edgeStartWidthPx ||
        oldWidget.enableBackGesture != widget.enableBackGesture) {
      _rebuildGestureLayer();
    }
  }

  void _bindAnimation() {
    _curvedAnimation = CurvedAnimation(
      parent: widget.animation,
      curve: widget.pushCurve,
      reverseCurve: widget.popCurve,
    );
    _position = _slideTween.animate(_curvedAnimation);
  }

  void _rebuildGestureLayer() {
    _stableGestureLayer = AppSwipeBackInteractor(
      edgeStartWidthPx: widget.edgeStartWidthPx,
      enableBackGesture: widget.enableBackGesture,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _curvedAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: MediaQuery.disableAnimationsOf(context)
          ? const AlwaysStoppedAnimation(Offset.zero)
          : _position,
      child: AppRouteDepthTransition(
        animation: widget.secondaryAnimation,
        curve: widget.pushCurve,
        reverseCurve: widget.popCurve,
        child: _stableGestureLayer,
      ),
    );
  }
}
