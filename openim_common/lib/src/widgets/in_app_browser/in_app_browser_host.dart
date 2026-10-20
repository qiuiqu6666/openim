import 'package:flutter/material.dart';

import '../../res/app_tokens.dart';
import 'in_app_browser_route.dart';
import 'in_app_browser_return_button.dart';

/// Owns the live browser outside application routes. Navigation never reparents
/// the platform view or recreates its controller.
class InAppBrowserHost extends StatefulWidget {
  const InAppBrowserHost({super.key, required this.child});
  final Widget child;
  static InAppBrowserHostState? _active;
  static InAppBrowserHostState? get active => _active;
  static void close() => _active?._close();

  /// Install before MaterialApp so expanded browser back takes precedence.
  static void installBackHandler() {
    WidgetsBinding.instance.removeObserver(_backHandler);
    WidgetsBinding.instance.addObserver(_backHandler);
  }

  static final _backHandler = _BrowserBackHandler();

  @override
  State<InAppBrowserHost> createState() => InAppBrowserHostState();
}

class InAppBrowserHostState extends State<InAppBrowserHost> {
  InAppBrowserRoute? _route;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _suspended = false;

  @override
  void initState() {
    super.initState();
    InAppBrowserHost._active = this;
  }

  void open(Uri uri) {
    final route = InAppBrowserRoute(
      uri: uri,
      scrim: Theme.of(context).colorScheme.scrim,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
    setState(() {
      _route = route;
      _navigatorKey = GlobalKey<NavigatorState>();
      _suspended = false;
    });
    // install() creates the route animation during the Navigator's first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_route, route)) {
        _navigatorKey!.currentState!.push(route);
        setState(() {});
      }
    });
    route.completed.then((_) {
      if (mounted && identical(_route, route)) _close();
    });
  }

  Future<T> suspendFor<T>(Future<T> Function() action) async {
    final route = _route;
    if (route == null) return action();
    setState(() => _suspended = true);
    try {
      return await action();
    } finally {
      if (mounted && identical(route, _route)) {
        setState(() => _suspended = false);
      }
    }
  }

  void _close() {
    if (!mounted) return;
    setState(() {
      _route = null;
      _navigatorKey = null;
      _suspended = false;
    });
  }

  Future<bool> handleBack() async {
    if (_route == null || _route!.minimized.value || _suspended) return false;
    await _navigatorKey?.currentState?.maybePop();
    return true;
  }

  @override
  void dispose() {
    if (identical(InAppBrowserHost._active, this)) {
      InAppBrowserHost._active = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    // Keep the same app subtree location whether a browser exists or not.
    return AnimatedBuilder(
      animation: route == null
          ? const AlwaysStoppedAnimation<double>(0)
          : Listenable.merge([route.animation, route.minimized]),
      child: widget.child,
      builder: (context, app) {
        final progress = _suspended ? 0.0 : route?.depthProgress ?? 0.0;
        final bottom = !_suspended
            ? (route?.dockProgress ?? 0) *
                (AppTokens.minimumTapSize +
                    AppTokens.s5 +
                    MediaQuery.paddingOf(context).bottom)
            : 0.0;
        return Stack(fit: StackFit.expand, children: [
          ColoredBox(
            color: Theme.of(context).colorScheme.scrim,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Transform.translate(
                offset: Offset(0, AppTokens.browserBackgroundOffset * progress),
                child: Transform.scale(
                  scale: 1 - (1 - AppTokens.browserBackgroundScale) * progress,
                  alignment: Alignment.topCenter,
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppTokens.rLg * progress),
                    child: app,
                  ),
                ),
              ),
            ),
          ),
          if (route != null)
            Offstage(
              offstage: _suspended,
              child: HeroControllerScope.none(
                  child: Navigator(
                key: _navigatorKey,
                onGenerateInitialRoutes: (_, __) => [_BrowserBaseRoute()],
              )),
            ),
          if (route != null && route.minimized.value && !_suspended)
            Positioned(
              right: MediaQuery.paddingOf(context).right,
              top: MediaQuery.paddingOf(context).top +
                  kToolbarHeight +
                  AppTokens.s3,
              child: InAppBrowserReturnButton(
                key: const ValueKey('browser-return-shortcut'),
                onPressed: route.restoreFromShortcut,
              ),
            ),
        ]);
      },
    );
  }
}

class _BrowserBackHandler with WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() async =>
      await InAppBrowserHost.active?.handleBack() ?? false;
}

class _BrowserBaseRoute extends PageRoute<void> {
  @override
  bool get opaque => false;
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildModalBarrier() => const SizedBox.shrink();
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      const SizedBox.shrink();
  // The host applies depth to the real application, not this empty base.
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => false;
}
