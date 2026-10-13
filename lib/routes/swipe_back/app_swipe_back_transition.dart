import 'package:flutter/material.dart';
import 'app_route_depth_transition.dart';
import 'app_route_slide.dart';
import 'app_swipe_back_interactor.dart';

class AppSwipeBackTransition extends StatelessWidget {
  const AppSwipeBackTransition(
      {super.key,
      required this.animation,
      required this.secondaryAnimation,
      required this.pushCurve,
      required this.popCurve,
      required this.edgeStartWidthPx,
      required this.enableBackGesture,
      required this.child});
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Curve pushCurve;
  final Curve popCurve;
  final double edgeStartWidthPx;
  final bool enableBackGesture;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppRouteSlide(
        animation: animation,
        curve: pushCurve,
        reverseCurve: popCurve,
        incoming: true,
        child: AppRouteDepthTransition(
            animation: secondaryAnimation,
            curve: pushCurve,
            reverseCurve: popCurve,
            child: AppSwipeBackInteractor(
                edgeStartWidthPx: edgeStartWidthPx,
                enableBackGesture: enableBackGesture,
                child: child)),
      );
}
