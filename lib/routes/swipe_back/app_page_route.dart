import 'package:flutter/cupertino.dart';

import 'app_route_depth_transition.dart';
import 'app_swipe_back_tokens.dart';
import 'app_swipe_back_transition.dart';

/// The Cupertino route contract lets GetX's previous route follow our secondary
/// animation. The actual animation and edge recognizer are shared with GetX.
class AppMaterialPageRoute<T> extends PageRouteBuilder<T>
    with CupertinoRouteTransitionMixin<T> {
  // The mixin overrides PageRouteBuilder's duration. Keep our own values too.
  // ignore: use_super_parameters
  AppMaterialPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.maintainState = true,
    super.allowSnapshotting = false,
    super.fullscreenDialog = false,
    super.opaque = true,
    this.edgeStartWidthPx = AppSwipeBackTokens.edgeWidth,
    this.pushCurve = AppSwipeBackTokens.curve,
    this.popCurve = AppSwipeBackTokens.curve,
    this.enableFullScreenBackGesture = true,
    Duration transitionDuration = AppSwipeBackTokens.transitionDuration,
    Duration reverseTransitionDuration = AppSwipeBackTokens.transitionDuration,
  })  : _appTransitionDuration = transitionDuration,
        _appReverseTransitionDuration = reverseTransitionDuration,
        super(
          transitionDuration: transitionDuration,
          reverseTransitionDuration: reverseTransitionDuration,
          pageBuilder: (context, _, __) => builder(context),
        );

  final Duration _appTransitionDuration;
  final Duration _appReverseTransitionDuration;
  @override
  Duration get transitionDuration => _appTransitionDuration;
  @override
  Duration get reverseTransitionDuration => _appReverseTransitionDuration;
  @override
  String? get title => null;
  @override
  Widget buildContent(BuildContext context) =>
      pageBuilder(context, animation!, secondaryAnimation!);

  final double edgeStartWidthPx;
  final Curve pushCurve;
  final Curve popCurve;
  final bool enableFullScreenBackGesture;

  AnimationController? get routeAnimationController => controller;

  @override
  bool get popGestureEnabled => false;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is PageRoute && !nextRoute.fullscreenDialog;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      AppRouteDepthTransition.delegatedTransition;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (fullscreenDialog) {
      return CupertinoFullscreenDialogTransition(
        primaryRouteAnimation: animation,
        secondaryRouteAnimation: secondaryAnimation,
        linearTransition: false,
        child: child,
      );
    }
    return AppSwipeBackTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      pushCurve: pushCurve,
      popCurve: popCurve,
      edgeStartWidthPx: edgeStartWidthPx,
      enableBackGesture: enableFullScreenBackGesture,
      child: child,
    );
  }
}
