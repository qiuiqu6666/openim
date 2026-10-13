import 'package:flutter/physics.dart';

/// Carries finger velocity into a critically damped, non-bouncing landing.
/// Distances and velocities are normalized to the route width.
class AppBackSettlement extends SpringSimulation {
  AppBackSettlement({
    required double position,
    required this.target,
    required double velocity,
    required double width,
  })  : _start = position,
        super(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: target == 0 ? 625 : 900,
            ratio: 1,
          ),
          position,
          target,
          velocity,
          tolerance: Tolerance(distance: 0.5 / width, velocity: 5 / width),
        );

  final double target;
  final double _start;

  @override
  double x(double time) => isDone(time) ? target : super.x(time);

  @override
  double dx(double time) => isDone(time) ? 0 : super.dx(time);

  @override
  bool isDone(double time) {
    // A fast flick can reach the boundary before the spring settles. Finish
    // there instead of holding an invisible route while its spring catches up.
    final position = super.x(time);
    return (_start == target && super.dx(time).abs() < tolerance.velocity) ||
        (target == 0 && position <= 0) ||
        (target == 1 && position >= 1) ||
        super.isDone(time);
  }
}
