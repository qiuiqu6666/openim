import 'package:flutter/material.dart';

import 'app_swipe_back_tokens.dart';
import 'app_swipe_back_transition.dart';

/// Covers existing MaterialPageRoute call sites without changing their
/// navigator, business scope, result or lifecycle ownership.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppSwipeBackTokens.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      AppSwipeBackTokens.transitionDuration;

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    if (route.fullscreenDialog ||
        route.settings.name == AppSwipeBackTokens.mediaRouteName) {
      // Media owns paging/panning; full-screen pickers retain their modal
      // animation and do not acquire the app's edge recognizer.
      return const PageTransitionsTheme().buildTransitions(
          route, context, animation, secondaryAnimation, child);
    }
    return AppSwipeBackTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      pushCurve: AppSwipeBackTokens.curve,
      popCurve: AppSwipeBackTokens.curve,
      edgeStartWidthPx: AppSwipeBackTokens.edgeWidth,
      enableBackGesture: true,
      child: child,
    );
  }
}

const appPageTransitionsTheme = PageTransitionsTheme(builders: {
  TargetPlatform.android: AppPageTransitionsBuilder(),
  TargetPlatform.iOS: AppPageTransitionsBuilder(),
  TargetPlatform.macOS: AppPageTransitionsBuilder(),
  TargetPlatform.windows: AppPageTransitionsBuilder(),
  TargetPlatform.linux: AppPageTransitionsBuilder(),
  TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
});
