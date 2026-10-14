import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum HomeIconMotion { message, group, contact, wallet, profile }

/// Animates only the artwork; badges and the tab's hit target remain still.
class AnimatedHomeIcon extends StatefulWidget {
  const AnimatedHomeIcon(
      {super.key,
      required this.selected,
      required this.motion,
      required this.child});

  final bool selected;
  final HomeIconMotion motion;
  final Widget child;

  @override
  State<AnimatedHomeIcon> createState() => _AnimatedHomeIconState();
}

class _AnimatedHomeIconState extends State<AnimatedHomeIcon>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AnimatedHomeIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.selected || _reduceMotion) {
      _controller.value = 1;
    } else if (!oldWidget.selected) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (_, child) {
          final t = _controller.value;
          final pulse =
              widget.selected && !_reduceMotion ? math.sin(math.pi * t) : 0.0;
          final wiggle = math.sin(2 * math.pi * t) * pulse;
          final (sx, sy, angle, dy) = switch (widget.motion) {
            HomeIconMotion.message => (
                1 + .1 * pulse,
                1 + .1 * pulse,
                -.08 * wiggle,
                -2 * pulse
              ),
            HomeIconMotion.group => (
                1 + .14 * pulse,
                1 - .06 * pulse,
                0.0,
                -pulse
              ),
            HomeIconMotion.contact => (1 - .12 * pulse, 1.0, .13 * wiggle, 0.0),
            HomeIconMotion.wallet => (
                1 + .08 * pulse,
                1 - .12 * pulse,
                -.06 * wiggle,
                -pulse
              ),
            HomeIconMotion.profile => (
                1.0,
                1 - .08 * pulse,
                .1 * wiggle,
                pulse
              ),
          };
          return Transform.translate(
              offset: Offset(0, dy),
              child: Transform.rotate(
                  angle: angle,
                  child:
                      Transform.scale(scaleX: sx, scaleY: sy, child: child)));
        },
      );
}
