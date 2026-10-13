import 'package:flutter/material.dart';

import 'app_back_gesture_recognizer.dart';
import 'app_back_settlement.dart';
import 'app_swipe_back_tokens.dart';

/// Route-owned gesture state shared by GetX, Material and wallet navigation.
class AppSwipeBackInteractor extends StatefulWidget {
  const AppSwipeBackInteractor({
    super.key,
    required this.child,
    required this.edgeStartWidthPx,
    required this.enableBackGesture,
  });

  final Widget child;
  final double edgeStartWidthPx;
  final bool enableBackGesture;

  @override
  State<AppSwipeBackInteractor> createState() => _AppSwipeBackInteractorState();
}

class _AppSwipeBackInteractorState extends State<AppSwipeBackInteractor> {
  ModalRoute<dynamic>? _route;
  NavigatorState? _navigator;
  AnimationController? _controller;
  bool _dragging = false;
  bool _ownsUserGesture = false;
  bool _popRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _controller?.removeStatusListener(_onStatus);
    _route = route;
    _navigator = route?.navigator;
    // Flutter/GetX expose no public interactive-transition controller API.
    // Keep this access in one adapter instead of replacing GetX's route factory
    // (which owns bindings, observers and route results).
    // ignore: invalid_use_of_protected_member
    _controller = route?.controller;
    _controller?.addStatusListener(_onStatus);
  }

  bool _allowed({bool duringDrag = false}) {
    final route = _route;
    final controller = _controller;
    if (!mounted ||
        !widget.enableBackGesture ||
        _popRequested ||
        route == null ||
        controller == null ||
        !route.isCurrent ||
        route.isFirst ||
        route.fullscreenDialog ||
        route.willHandlePopInternally ||
        route.popDisposition != RoutePopDisposition.pop) {
      return false;
    }
    // Existing legacy WillPopScope screens must retain their veto too.
    // ignore: deprecated_member_use, invalid_use_of_protected_member
    if (route.hasScopedWillPopCallback) return false;
    if (!duringDrag &&
        (!controller.isCompleted ||
            route.secondaryAnimation?.isDismissed == false ||
            _navigator?.userGestureInProgress == true)) {
      return false;
    }
    return _navigator?.canPop() == true &&
        controller.status != AnimationStatus.reverse;
  }

  bool _start() {
    if (!_allowed()) return false;
    _dragging = true;
    _ownsUserGesture = true;
    _navigator!.didStartUserGesture();
    return true;
  }

  void _update(double dx) {
    if (!_dragging) return;
    if (!_allowed(duringDrag: true)) {
      _cancel();
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    if (width > 0) {
      _controller!.value = (_controller!.value - dx / width).clamp(0.0, 1.0);
    }
  }

  void _end(double distance, double velocity) {
    if (!_dragging) return;
    final width = MediaQuery.sizeOf(context).width;
    final shouldPop = width > 0 &&
        (velocity > AppSwipeBackTokens.velocity ||
            distance > width * AppSwipeBackTokens.distanceFraction);
    if (!shouldPop || !_allowed(duringDrag: true)) {
      _cancel(velocity: velocity);
      return;
    }
    _dragging = false;
    _popRequested = true;
    // Rechecked synchronously above, including PopScope and local history.
    _navigator!.pop();
    final controller = _controller!;
    if (controller.isAnimating) {
      controller.animateBackWith(AppBackSettlement(
        position: controller.value,
        target: 0,
        velocity: -velocity / width,
        width: width,
      ));
    } else {
      _finishUserGesture();
    }
  }

  void _cancel({double velocity = 0}) {
    if (!_dragging) return;
    _dragging = false;
    final controller = _controller!;
    // A toolbar/system pop or replacement may already be running. Never
    // resurrect the outgoing page by starting a snap-back in that case.
    if (_route?.isCurrent != true ||
        controller.status == AnimationStatus.reverse) {
      if (!controller.isAnimating) _finishUserGesture();
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0 || MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    } else {
      controller.animateWith(AppBackSettlement(
        position: controller.value,
        target: 1,
        velocity: -velocity / width,
        width: width,
      ));
    }
    if (!controller.isAnimating) _finishUserGesture();
  }

  void _onStatus(AnimationStatus status) {
    if (!_dragging &&
        (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed)) {
      _finishUserGesture();
    }
  }

  void _finishUserGesture() {
    if (!_ownsUserGesture) return;
    _ownsUserGesture = false;
    if (_navigator?.mounted == true) _navigator!.didStopUserGesture();
  }

  @override
  void dispose() {
    _controller?.removeStatusListener(_onStatus);
    _finishUserGesture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: widget.child),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: widget.edgeStartWidthPx,
            child: IgnorePointer(
              ignoring: !widget.enableBackGesture,
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: {
                  AppBackGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          AppBackGestureRecognizer>(
                    () => AppBackGestureRecognizer(
                      isAllowed: _allowed,
                      onStart: _start,
                      onUpdate: _update,
                      onEnd: _end,
                      onCancel: _cancel,
                    ),
                    (_) {},
                  ),
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
}
