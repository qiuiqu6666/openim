import 'package:flutter/material.dart';

/// A single sweep for a group of placeholders; content owns its geometry.
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer(
      {super.key,
      required this.baseColor,
      required this.highlightColor,
      required this.label,
      required this.child});

  final Color baseColor, highlightColor;
  final String label;
  final Widget child;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.label,
        child: ExcludeSemantics(
            child: IgnorePointer(
                child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _sweep,
            builder: (context, child) {
              if (MediaQuery.disableAnimationsOf(context)) return child!;
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment(-3 + _sweep.value * 6, -1),
                  end: Alignment(-1 + _sweep.value * 6, 1),
                  colors: [
                    widget.baseColor,
                    widget.highlightColor,
                    widget.baseColor
                  ],
                  stops: const [0, .5, 1],
                ).createShader(bounds),
                child: child,
              );
            },
            child: widget.child,
          ),
        ))),
      );
}
