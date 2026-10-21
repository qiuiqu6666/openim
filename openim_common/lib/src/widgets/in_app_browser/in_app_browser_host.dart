import 'package:flutter/material.dart';

import '../../res/app_tokens.dart';
import 'in_app_browser_route.dart';
import 'in_app_browser_return_button.dart';
import 'in_app_browser_dock_stack.dart';
import 'in_app_browser_page_picker.dart';

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
  final _entries = <_BrowserEntry>[];
  int _suspensions = 0;
  bool _showPages = false;
  bool get _suspended => _suspensions > 0;

  _BrowserEntry? get _expanded {
    for (final entry in _entries.reversed) {
      if (!entry.route.minimized.value) return entry;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    InAppBrowserHost._active = this;
  }

  void open(Uri uri) {
    _showPages = false;
    for (final entry in _entries) {
      entry.route.retainInDock();
    }
    final entry = _BrowserEntry(InAppBrowserRoute(
      uri: uri,
      scrim: Theme.of(context).colorScheme.scrim,
      reduced: MediaQuery.disableAnimationsOf(context),
      externalDock: true,
    ));
    setState(() => _entries.add(entry));
    // Each page retains its navigator and platform view for its whole lifetime.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_entries.contains(entry)) return;
      entry.navigatorKey.currentState!.push(entry.route);
      setState(() {});
    });
    entry.route.completed.then((_) {
      if (mounted && _entries.contains(entry)) {
        setState(() => _entries.remove(entry));
      }
    });
  }

  Future<T> suspendFor<T>(Future<T> Function() action) async {
    if (_entries.isEmpty) return action();
    setState(() => _suspensions++);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _suspensions--);
    }
  }

  void _close() {
    if (mounted) {
      setState(() {
        _showPages = false;
        _entries.clear();
      });
    }
  }

  void _selectPage(InAppBrowserRoute route) {
    final index = _entries.indexWhere((entry) => identical(entry.route, route));
    if (index < 0) return;
    for (final entry in _entries) {
      entry.route.retainInDock();
    }
    setState(() {
      _showPages = false;
      _entries.add(_entries.removeAt(index));
    });
    route.restoreFromShortcut();
  }

  Future<bool> handleBack() async {
    if (_showPages && !_suspended) {
      setState(() => _showPages = false);
      return true;
    }
    final entry = _expanded;
    if (entry == null || _suspended) return false;
    await entry.navigatorKey.currentState?.maybePop();
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
    // Keep the same app subtree location whether a browser exists or not.
    return AnimatedBuilder(
      animation: Listenable.merge([
        for (final entry in _entries) ...[
          entry.route.animation,
          entry.route.minimized,
        ],
      ]),
      child: widget.child,
      builder: (context, app) {
        final expanded = _expanded;
        final route = expanded?.route;
        final progress = _suspended ? 0.0 : route?.depthProgress ?? 0.0;
        // Only the front page owns the dock. Older pages stay retained behind
        // it and become visible after the front page closes.
        final dockRoute = _entries.isEmpty ? null : _entries.last.route;
        final bottom = _suspended
            ? 0.0
            : (dockRoute?.dockProgress ?? 0) *
                (AppTokens.minimumTapSize +
                    AppTokens.s5 +
                    InAppBrowserDockStack.depth(_entries.length) +
                    MediaQuery.paddingOf(context).bottom);
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
          if (bottom > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottom,
              child: _BrowserDockOverlay(
                child: InAppBrowserDockStack(
                  count: _entries.length,
                  progress: dockRoute!.dockProgress,
                  child: dockRoute.buildDock(context,
                      pageCount: _entries.length,
                      onShowPages: () => setState(() => _showPages = true)),
                ),
              ),
            ),
          for (final entry in _entries)
            Offstage(
              key: ObjectKey(entry),
              offstage: _suspended || !identical(entry, expanded),
              child: HeroControllerScope.none(
                child: Navigator(
                  key: entry.navigatorKey,
                  onGenerateInitialRoutes: (_, __) => [_BrowserBaseRoute()],
                ),
              ),
            ),
          if (_entries.isNotEmpty && expanded == null && !_suspended)
            Positioned(
              right: MediaQuery.paddingOf(context).right,
              top: MediaQuery.paddingOf(context).top +
                  kToolbarHeight +
                  AppTokens.s3,
              child: InAppBrowserReturnButton(
                key: const ValueKey('browser-return-shortcut'),
                onPressed: _entries.last.route.restoreFromShortcut,
              ),
            ),
          if (_showPages && _entries.isNotEmpty && !_suspended)
            Positioned.fill(
              child: InAppBrowserPagePicker(
                pages: _entries.reversed.map((entry) => entry.route).toList(),
                selected: _entries.last.route,
                onSelect: _selectPage,
                onDismiss: () => setState(() => _showPages = false),
              ),
            ),
        ]);
      },
    );
  }
}

class _BrowserEntry {
  _BrowserEntry(this.route);
  final InAppBrowserRoute route;
  final navigatorKey = GlobalKey<NavigatorState>();
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

/// MaterialApp.builder sits above the app Navigator's tooltip overlay.
class _BrowserDockOverlay extends StatefulWidget {
  const _BrowserDockOverlay({required this.child});
  final Widget child;
  @override
  State<_BrowserDockOverlay> createState() => _BrowserDockOverlayState();
}

class _BrowserDockOverlayState extends State<_BrowserDockOverlay> {
  late final _entry = OverlayEntry(builder: (_) => widget.child);
  @override
  void didUpdateWidget(_BrowserDockOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }
}
