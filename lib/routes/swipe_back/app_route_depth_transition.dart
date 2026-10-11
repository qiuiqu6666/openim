import 'package:flutter/material.dart';
import 'app_swipe_back_tokens.dart';

class AppRouteDepthTransition extends StatelessWidget {
  const AppRouteDepthTransition({
    super.key,
    required this.animation,
    required this.child,
    this.curve = defaultCurve,
    this.reverseCurve = defaultCurve,
  });

  static const Duration transitionDuration =
      AppSwipeBackTokens.transitionDuration;
  static const Curve defaultCurve = AppSwipeBackTokens.curve;
  static const double recededScale = AppSwipeBackTokens.recededScale;
  static const double maximumScrimOpacity = AppSwipeBackTokens.scrimOpacity;

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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final activeCurve =
            animation.status == AnimationStatus.reverse ? reverseCurve : curve;
        final progress = MediaQuery.disableAnimationsOf(context)
            ? 0.0
            : activeCurve.transform(animation.value.clamp(0.0, 1.0));
        final scrimOpacity = maximumScrimOpacity * progress;
        return ColoredBox(
          color: ModalRoute.of(context)?.opaque == false
              ? Colors.transparent
              : Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.scale(
                scale: 1.0 - (1.0 - recededScale) * progress,
                child: child!,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .scrim
                        .withValues(alpha: scrimOpacity),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
