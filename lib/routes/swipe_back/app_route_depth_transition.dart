import 'package:flutter/material.dart';
import 'app_route_slide.dart';
import 'app_swipe_back_tokens.dart';

/// Subtle parallax and dimming of the page being covered, without scaling.
class AppRouteDepthTransition extends StatelessWidget {
  const AppRouteDepthTransition(
      {super.key,
      required this.animation,
      required this.child,
      this.curve = defaultCurve,
      this.reverseCurve = AppSwipeBackTokens.reverseCurve});
  static const Duration transitionDuration =
      AppSwipeBackTokens.transitionDuration;
  static const Curve defaultCurve = AppSwipeBackTokens.curve;
  final Animation<double> animation;
  final Widget child;
  final Curve curve;
  final Curve reverseCurve;

  static Widget? delegatedTransition(
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          bool allowSnapshotting,
          Widget? child) =>
      child == null
          ? null
          : AppRouteDepthTransition(
              animation: secondaryAnimation, child: child);

  @override
  Widget build(BuildContext context) => AppRouteSlide(
      animation: animation,
      curve: curve,
      reverseCurve: reverseCurve,
      incoming: false,
      child: child);
}
