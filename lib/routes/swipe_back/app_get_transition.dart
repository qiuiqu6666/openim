import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_swipe_back_tokens.dart';
import 'app_swipe_back_transition.dart';

/// GetX keeps ownership of bindings, arguments and disposal. Only its visual
/// transition/gesture is replaced; native GetX popGesture must be false.
class AppGetTransition extends CustomTransition {
  AppGetTransition({
    this.enableBackGesture = true,
    this.edgeWidth = AppSwipeBackTokens.edgeWidth,
  });

  final bool enableBackGesture;
  final double edgeWidth;

  @override
  Widget buildTransition(
      BuildContext context,
      Curve? curve,
      Alignment? alignment,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    // The global GetX fallback supplies an already-curved animation. Use the
    // original route animation so push and interactive pop share one curve.
    final route = ModalRoute.of(context);
    return AppSwipeBackTransition(
      animation: route?.animation ?? animation,
      secondaryAnimation: secondaryAnimation,
      pushCurve: AppSwipeBackTokens.curve,
      popCurve: AppSwipeBackTokens.reverseCurve,
      edgeStartWidthPx: edgeWidth,
      enableBackGesture: enableBackGesture,
      child: child,
    );
  }
}
