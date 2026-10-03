import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/wallet_99chat_tokens.dart';

/// Push a Wallet secondary page above OpenIM's PersistentTabView.
///
/// The root navigator boundary keeps the five main tabs out of Wallet child
/// pages, while [AppMaterialPageRoute] mirrors 99chat's edge-swipe interaction.
Future<T?> openWalletPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    AppMaterialPageRoute<T>(builder: (_) => page),
  );
}

Future<T?> replaceWalletPage<T, TO>(BuildContext context, Widget page) {
  return Navigator.of(context, rootNavigator: true).pushReplacement<T, TO>(
    AppMaterialPageRoute<T>(builder: (_) => page),
  );
}

class AppBackButton extends StatelessWidget {
  final Color? color;
  final VoidCallback? onPressed;

  const AppBackButton({super.key, this.color, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
      color: color ?? AppTokens.accent,
      onPressed: onPressed ??
          () => Navigator.of(context, rootNavigator: true).maybePop(),
    );
  }
}

/// Wallet-local equivalent of 99chat's `AppMaterialPageRoute`.
///
/// 99chat routes use a 340 ms slide/depth transition and a dedicated gesture
/// recognizer on the left 24 logical pixels. A dedicated recognizer is
/// important: a plain GestureDetector loses the arena to vertical/scrollable
/// children on real devices, which is why the previous port looked correct in
/// source but right-swipe back was unreliable at runtime.
class AppMaterialPageRoute<T> extends PageRouteBuilder<T> {
  AppMaterialPageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool maintainState = true,
    bool allowSnapshotting = false,
    this.edgeStartWidthPx = 24.0,
    this.pushCurve = _WalletRouteDepthTransition.defaultCurve,
    this.popCurve = _WalletRouteDepthTransition.defaultCurve,
    this.enableFullScreenBackGesture = true,
    Duration transitionDuration =
        _WalletRouteDepthTransition.transitionDuration,
    Duration reverseTransitionDuration =
        _WalletRouteDepthTransition.transitionDuration,
  }) : super(
          settings: settings,
          maintainState: maintainState,
          allowSnapshotting: allowSnapshotting,
          opaque: true,
          barrierColor: Colors.transparent,
          barrierDismissible: false,
          transitionDuration: transitionDuration,
          reverseTransitionDuration: reverseTransitionDuration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _FullScreenBackTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              pushCurve: pushCurve,
              popCurve: popCurve,
              edgeStartWidthPx: edgeStartWidthPx,
              enableBackGesture: enableFullScreenBackGesture,
              child: child,
            );
          },
        );

  final double edgeStartWidthPx;
  final Curve pushCurve;
  final Curve popCurve;
  final bool enableFullScreenBackGesture;

  AnimationController? get routeAnimationController => controller;
}

class _WalletRouteDepthTransition extends StatelessWidget {
  const _WalletRouteDepthTransition({
    required this.animation,
    required this.child,
    this.curve = defaultCurve,
    this.reverseCurve = defaultCurve,
  });

  static const Duration transitionDuration = Duration(milliseconds: 340);
  static const Curve defaultCurve = Curves.fastEaseInToSlowEaseOut;
  static const double recededScale = 0.96;
  static const double maximumScrimOpacity = 0.55;

  final Animation<double> animation;
  final Widget child;
  final Curve curve;
  final Curve reverseCurve;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final activeCurve = animation.status == AnimationStatus.reverse
            ? reverseCurve
            : curve;
        final progress = activeCurve.transform(animation.value.clamp(0.0, 1.0));
        final scrimOpacity = maximumScrimOpacity * progress;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
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
                    color: Color.fromRGBO(0, 0, 0, scrimOpacity),
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

class _FullScreenBackTransition extends StatefulWidget {
  const _FullScreenBackTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.pushCurve,
    required this.popCurve,
    required this.edgeStartWidthPx,
    required this.enableBackGesture,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Curve pushCurve;
  final Curve popCurve;
  final double edgeStartWidthPx;
  final bool enableBackGesture;
  final Widget child;

  @override
  State<_FullScreenBackTransition> createState() =>
      _FullScreenBackTransitionState();
}

class _FullScreenBackTransitionState extends State<_FullScreenBackTransition> {
  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(1.0, 0.0),
    end: Offset.zero,
  );

  late CurvedAnimation _curvedAnimation;
  late Animation<Offset> _position;
  late Widget _stableGestureLayer;

  @override
  void initState() {
    super.initState();
    _bindAnimation();
    _rebuildGestureLayer();
  }

  @override
  void didUpdateWidget(covariant _FullScreenBackTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation) ||
        oldWidget.pushCurve != widget.pushCurve ||
        oldWidget.popCurve != widget.popCurve) {
      _curvedAnimation.dispose();
      _bindAnimation();
    }
    if (!identical(oldWidget.child, widget.child) ||
        oldWidget.edgeStartWidthPx != widget.edgeStartWidthPx ||
        oldWidget.enableBackGesture != widget.enableBackGesture) {
      _rebuildGestureLayer();
    }
  }

  void _bindAnimation() {
    _curvedAnimation = CurvedAnimation(
      parent: widget.animation,
      curve: widget.pushCurve,
      reverseCurve: widget.popCurve,
    );
    _position = _slideTween.animate(_curvedAnimation);
  }

  void _rebuildGestureLayer() {
    _stableGestureLayer = _FullScreenBackInteractor(
      edgeStartWidthPx: widget.edgeStartWidthPx,
      enableBackGesture: widget.enableBackGesture,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _curvedAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _position,
      child: _WalletRouteDepthTransition(
        animation: widget.secondaryAnimation,
        curve: widget.pushCurve,
        reverseCurve: widget.popCurve,
        child: _stableGestureLayer,
      ),
    );
  }
}

class _RouteBackGestureDriver {
  _RouteBackGestureDriver({
    required this.navigator,
    required this.controller,
  }) {
    navigator.didStartUserGesture();
  }

  final NavigatorState navigator;
  final AnimationController controller;

  static const Duration _cancelDuration = Duration(milliseconds: 120);
  static const Curve _cancelCurve = Curves.fastEaseInToSlowEaseOut;

  void dragUpdate(double delta) {
    controller.value = (controller.value - delta).clamp(0.0, 1.0);
  }

  void dragEnd({required bool shouldPop}) {
    if (shouldPop) {
      if (navigator.canPop()) navigator.pop();
      _stopUserGesture();
      return;
    }
    controller.animateTo(
      1.0,
      duration: _cancelDuration,
      curve: _cancelCurve,
    );
    _stopUserGestureWhenSettled();
  }

  void stopUserGestureOnly() => _stopUserGesture();

  void _stopUserGestureWhenSettled() {
    if (controller.isAnimating) {
      late AnimationStatusListener listener;
      listener = (AnimationStatus status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _stopUserGesture();
          controller.removeStatusListener(listener);
        }
      };
      controller.addStatusListener(listener);
    } else {
      _stopUserGesture();
    }
  }

  void _stopUserGesture() {
    if (navigator.mounted) navigator.didStopUserGesture();
  }
}

class _FullScreenBackInteractor extends StatefulWidget {
  const _FullScreenBackInteractor({
    required this.child,
    required this.edgeStartWidthPx,
    required this.enableBackGesture,
  });

  final Widget child;
  final double edgeStartWidthPx;
  final bool enableBackGesture;

  @override
  State<_FullScreenBackInteractor> createState() =>
      _FullScreenBackInteractorState();
}

class _FullScreenBackInteractorState extends State<_FullScreenBackInteractor> {
  late final _FullScreenBackRecognizer _recognizer;
  bool _popRequested = false;
  _RouteBackGestureDriver? _gestureDriver;
  NavigatorState? _navigator;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeAnimationStatusListener;
  bool _gestureEnabled = false;

  AnimationController? _routeAnimationController() {
    final route = ModalRoute.of(context);
    if (route is AppMaterialPageRoute) return route.routeAnimationController;
    return null;
  }

  bool _isPopTransitionInProgress() =>
      ModalRoute.of(context)?.animation?.status == AnimationStatus.reverse;

  bool _gestureAllowed({bool allowingActiveDrag = false}) {
    if (!widget.enableBackGesture || !mounted || _popRequested) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (route?.animation?.status == AnimationStatus.reverse) return false;
    if (!allowingActiveDrag) {
      final controller = _routeAnimationController();
      if (controller != null &&
          controller.isAnimating &&
          _gestureDriver == null) {
        return false;
      }
    }
    final nav = Navigator.maybeOf(context);
    return nav != null && nav.canPop();
  }

  void _releaseDriver({required bool allowSnapBack}) {
    final driver = _gestureDriver;
    if (driver == null) return;
    _gestureDriver = null;
    if (allowSnapBack) {
      driver.dragEnd(shouldPop: false);
    } else {
      driver.stopUserGestureOnly();
    }
  }

  @override
  void initState() {
    super.initState();
    _recognizer = _FullScreenBackRecognizer(
      onAccepted: () {
        if (!_gestureAllowed() || !mounted || _gestureDriver != null) return;
        final nav = Navigator.of(context);
        final controller = _routeAnimationController();
        if (controller == null) {
          if (kDebugMode) {
            debugPrint(
              'Wallet FullScreenBack: route controller is null; gesture ignored',
            );
          }
          return;
        }
        _gestureDriver = _RouteBackGestureDriver(
          navigator: nav,
          controller: controller,
        );
      },
      onDelta: (deltaDx) {
        if (!mounted) return;
        final driver = _gestureDriver;
        if (driver == null) return;
        if (_popRequested || _isPopTransitionInProgress()) {
          _releaseDriver(allowSnapBack: false);
          return;
        }
        if (!_gestureAllowed(allowingActiveDrag: true)) {
          _releaseDriver(allowSnapBack: true);
          return;
        }
        final width = MediaQuery.sizeOf(context).width;
        if (width > 0) driver.dragUpdate(deltaDx / width);
      },
      onEnd: (totalDx, velocity) {
        if (!mounted) return;
        if (_popRequested) {
          _releaseDriver(allowSnapBack: false);
          return;
        }
        final driver = _gestureDriver;
        if (driver == null) return;
        if (_isPopTransitionInProgress()) {
          _releaseDriver(allowSnapBack: false);
          return;
        }
        if (!_gestureAllowed(allowingActiveDrag: true)) {
          _releaseDriver(allowSnapBack: true);
          return;
        }
        final width = MediaQuery.sizeOf(context).width;
        if (width <= 0) {
          _releaseDriver(allowSnapBack: true);
          return;
        }
        final shouldPop = velocity > 320 || totalDx > width * 0.16;
        if (shouldPop) {
          if (!Navigator.of(context).canPop()) {
            _releaseDriver(allowSnapBack: true);
            return;
          }
          _popRequested = true;
          _gestureDriver = null;
          driver.dragEnd(shouldPop: true);
          return;
        }
        _releaseDriver(allowSnapBack: true);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = Navigator.maybeOf(context);
    _bindRouteAnimation();
    _gestureEnabled = _gestureAllowed() || _gestureDriver != null;
  }

  void _bindRouteAnimation() {
    final next = ModalRoute.of(context)?.animation;
    if (identical(next, _routeAnimation)) return;
    final listener = _routeAnimationStatusListener;
    if (listener != null) _routeAnimation?.removeStatusListener(listener);
    _routeAnimation = next;
    _routeAnimationStatusListener = (_) => _syncGestureEnabled();
    next?.addStatusListener(_routeAnimationStatusListener!);
  }

  void _syncGestureEnabled() {
    if (!mounted) return;
    final next = _gestureAllowed() || _gestureDriver != null;
    if (next == _gestureEnabled) return;
    setState(() => _gestureEnabled = next);
  }

  @override
  void dispose() {
    _releaseDriver(allowSnapBack: false);
    final listener = _routeAnimationStatusListener;
    if (listener != null) _routeAnimation?.removeStatusListener(listener);
    _routeAnimationStatusListener = null;
    _routeAnimation = null;
    final nav = _navigator;
    if (nav != null && nav.mounted && nav.userGestureInProgress) {
      nav.didStopUserGesture();
    }
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(child: widget.child);
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: widget.edgeStartWidthPx,
          child: IgnorePointer(
            ignoring: !_gestureEnabled,
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              gestures: {
                _FullScreenBackRecognizer: GestureRecognizerFactoryWithHandlers<
                    _FullScreenBackRecognizer>(
                  () => _recognizer,
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
}

class _FullScreenBackRecognizer extends OneSequenceGestureRecognizer {
  _FullScreenBackRecognizer({
    required this.onAccepted,
    required this.onDelta,
    required this.onEnd,
  });

  final VoidCallback onAccepted;
  final void Function(double deltaDx) onDelta;
  final void Function(double totalDx, double velocity) onEnd;

  Offset? _startGlobal;
  bool _accepted = false;
  double _totalDx = 0.0;
  final VelocityTracker _tracker = VelocityTracker.withKind(
    PointerDeviceKind.touch,
  );

  static const double _minDistance = 0.1;

  @override
  void addPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    _startGlobal = event.position;
    _accepted = false;
    _totalDx = 0.0;
    _tracker.addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _tracker.addPosition(event.timeStamp, event.position);
      if (_startGlobal == null) return;
      final delta = event.position - _startGlobal!;
      final dx = delta.dx;
      final dy = delta.dy.abs();
      if (!_accepted) {
        final movedEnough = delta.distance >= _minDistance;
        final isRight = dx > 0;
        final horizontalDominant = dx.abs() > dy * 0.8;
        if (movedEnough && isRight && horizontalDominant) {
          _accepted = true;
          resolve(GestureDisposition.accepted);
          onAccepted();
        } else if (movedEnough && !horizontalDominant) {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
        } else if (movedEnough && !isRight && horizontalDominant) {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
        }
      }
      if (_accepted) {
        _totalDx += event.delta.dx;
        onDelta(event.delta.dx);
      }
    } else if (event is PointerUpEvent) {
      final vx = _tracker.getVelocity().pixelsPerSecond.dx;
      if (_accepted) {
        onEnd(_totalDx, vx);
      } else {
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
      _accepted = false;
      _startGlobal = null;
      _totalDx = 0.0;
    } else if (event is PointerCancelEvent) {
      if (_accepted) {
        onEnd(_totalDx, _tracker.getVelocity().pixelsPerSecond.dx);
      } else {
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
      _accepted = false;
      _startGlobal = null;
      _totalDx = 0.0;
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    _accepted = false;
    _startGlobal = null;
    _totalDx = 0.0;
  }

  @override
  String get debugDescription => 'FullScreenBack';
}
