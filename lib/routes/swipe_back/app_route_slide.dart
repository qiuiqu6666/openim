import 'package:flutter/material.dart';
import 'app_swipe_back_tokens.dart';

/// Shares position, parallax and shading throughout a gesture settlement.
class AppRouteSlide extends StatefulWidget {
  const AppRouteSlide(
      {super.key,
      required this.animation,
      required this.curve,
      required this.reverseCurve,
      required this.incoming,
      required this.child});
  final Animation<double> animation;
  final Curve curve;
  final Curve reverseCurve;
  final bool incoming;
  final Widget child;

  @override
  State<AppRouteSlide> createState() => _AppRouteSlideState();
}

class _AppRouteSlideState extends State<AppRouteSlide> {
  late CurvedAnimation _progress;

  void _bind() {
    _progress = CurvedAnimation(
        parent: widget.animation,
        curve: widget.curve,
        reverseCurve: widget.reverseCurve);
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant AppRouteSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.curve != widget.curve ||
        oldWidget.reverseCurve != widget.reverseCurve) {
      _progress.dispose();
      _bind();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    final disabled = MediaQuery.disableAnimationsOf(context);
    final scrim = Theme.of(context).colorScheme.scrim;
    return AnimatedBuilder(
      animation: Listenable.merge(
          [widget.animation, navigator.userGestureInProgressNotifier]),
      child: widget.child,
      builder: (context, child) {
        final progress = (navigator.userGestureInProgress
                ? widget.animation.value
                : _progress.value)
            .clamp(0.0, 1.0);
        if (disabled) return child!;
        Widget surface = child!;
        if (widget.incoming) {
          surface = DecoratedBox(
            decoration: BoxDecoration(boxShadow: [
              BoxShadow(
                color: scrim.withValues(
                    alpha: AppSwipeBackTokens.edgeShadowOpacity),
                blurRadius: AppSwipeBackTokens.edgeShadowBlur,
              )
            ]),
            child: surface,
          );
        } else {
          surface = Stack(fit: StackFit.expand, children: [
            surface,
            Positioned.fill(
                child: IgnorePointer(
                    child: ColoredBox(
              color: scrim.withValues(
                  alpha: AppSwipeBackTokens.scrimOpacity * progress),
            ))),
          ]);
        }
        return FractionalTranslation(
          translation: Offset(
              widget.incoming
                  ? 1 - progress
                  : -AppSwipeBackTokens.parallaxFraction * progress,
              0),
          child: surface,
        );
      },
    );
  }
}
