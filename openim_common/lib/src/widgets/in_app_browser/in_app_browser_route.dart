import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../res/app_tokens.dart';
import 'in_app_browser_page.dart';

/// A sheet route whose transition also moves the existing page into the back.
/// Cupertino route identity lets both GetX and Material routes coordinate it.
class InAppBrowserRoute extends PageRoute<void>
    with CupertinoRouteTransitionMixin<void> {
  InAppBrowserRoute(
      {required Uri uri, required Color scrim, required bool reduced})
      : _uri = uri,
        _reduced = reduced,
        _scrim = scrim,
        super(
          settings: const RouteSettings(name: '/in-app-browser'),
        );

  final Uri _uri;
  final _minimized = ValueNotifier(false);
  ValueListenable<bool> get minimized => _minimized;

  /// Reserve the dock's space continuously while dragging/settling, instead
  /// of changing the underlying chat's viewport at the minimized-state flip.
  double get dockProgress => _minimized.value
      ? 1
      : _interactive
          ? ((1 - (animation?.value ?? 1)) / .999).clamp(0.0, 1.0)
          : 0;
  double get depthProgress => _interactive
      ? animation?.value ?? 0
      : AppTokens.browserBackgroundCurve.transform(animation?.value ?? 0);
  late final _address = ValueNotifier(_uri.host);
  late String _host = _uri.host;
  final _icon = ValueNotifier<Uri?>(null);
  static const _barHeight = AppTokens.minimumTapSize + AppTokens.s5;

  Future<void> _minimizeFromBarrier() async {
    if (!isCurrent ||
        _minimized.value ||
        _dragging ||
        controller == null ||
        !controller!.isCompleted) {
      return;
    }
    _interactive = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await controller!
          .animateBack(.001,
              duration:
                  _reduced ? Duration.zero : AppTokens.browserCloseDuration,
              curve: Curves.easeOutCubic)
          .orCancel;
      _minimized.value = true;
      changedInternalState();
    } on TickerCanceled {
      // Closing the browser can interrupt settling.
    } finally {
      _interactive = false;
    }
  }

  Future<void> _restore() async {
    _interactive = true;
    _minimized.value = false;
    changedInternalState();
    try {
      await controller!
          .animateTo(1,
              duration:
                  _reduced ? Duration.zero : AppTokens.browserOpenDuration,
              curve: Curves.easeOutCubic)
          .orCancel;
    } on TickerCanceled {
      // Route was closed while restoring.
    } finally {
      _interactive = false;
    }
  }

  void restoreFromShortcut() {
    if (_minimized.value && isCurrent && controller?.isAnimating == false) {
      _restore();
    }
  }

  bool _interactive = false;
  bool _dragging = false;
  bool _fromMinimized = false;
  double _restoreTravel = 1;
  double _dragHeight = 1;

  void _startDrag(BuildContext context) {
    if (!isCurrent ||
        controller == null ||
        controller!.isAnimating ||
        (!_minimized.value && !controller!.isCompleted)) {
      return;
    }
    _dragHeight = MediaQuery.sizeOf(context).height;
    _fromMinimized = _minimized.value;
    if (_fromMinimized) {
      final padding = MediaQuery.paddingOf(context);
      final pageTop = padding.top +
          (_dragHeight - padding.top) *
              (1 - AppTokens.browserSheetHeightFactor);
      _restoreTravel =
          (_dragHeight - _barHeight - padding.bottom - pageTop) / _dragHeight;
      _minimized.value = false;
      changedInternalState();
    }
    _interactive = _dragging = true;
    navigator?.didStartUserGesture();
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_dragging) return;
    controller!.value = (controller!.value -
            details.delta.dy /
                (_dragHeight * (_fromMinimized ? _restoreTravel : 1)))
        .clamp(.001, 1.0);
  }

  Future<void> _endDrag({double velocity = 0, bool cancelled = false}) async {
    if (!_dragging) return;
    _dragging = false;
    final owner = navigator;
    final dismiss = _fromMinimized
        ? cancelled ||
            !(velocity < -AppTokens.browserDismissVelocity ||
                (velocity <= AppTokens.browserDismissVelocity &&
                    controller!.value > AppTokens.browserDismissFraction))
        : !cancelled &&
            (velocity > AppTokens.browserDismissVelocity ||
                (velocity >= -AppTokens.browserDismissVelocity &&
                    controller!.value < 1 - AppTokens.browserDismissFraction));
    try {
      if (dismiss && isCurrent) {
        FocusManager.instance.primaryFocus?.unfocus();
        await controller!
            .animateBack(.001,
                duration:
                    _reduced ? Duration.zero : AppTokens.browserCloseDuration,
                curve: Curves.easeOutCubic)
            .orCancel;
        _minimized.value = true;
        changedInternalState();
      } else {
        await controller!
            .animateTo(1,
                duration:
                    _reduced ? Duration.zero : AppTokens.browserCloseDuration,
                curve: Curves.easeOutCubic)
            .orCancel;
      }
    } on TickerCanceled {
      // The navigator can remove the route while a gesture is settling.
    } finally {
      _interactive = false;
      _fromMinimized = false;
      if (owner?.mounted == true && owner!.userGestureInProgress) {
        owner.didStopUserGesture();
      }
    }
  }

  @override
  String? get title => null;
  @override
  bool get maintainState => true;
  @override
  String? get barrierLabel => null;
  @override
  Widget buildContent(BuildContext context) => GestureDetector(
      onVerticalDragStart: (_) => _startDrag(context),
      onVerticalDragUpdate: _updateDrag,
      onVerticalDragEnd: (details) =>
          _endDrag(velocity: details.primaryVelocity ?? 0),
      onVerticalDragCancel: () => _endDrag(cancelled: true),
      child: ValueListenableBuilder<bool>(
        valueListenable: _minimized,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: AppTokens.browserSheetHeightFactor,
              widthFactor: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTokens.rLg)),
                child: InAppBrowserPage(
                    uri: _uri,
                    onLocationChanged: (uri) {
                      _host = uri.host;
                      _address.value = uri.host;
                      _icon.value = null;
                    },
                    onMetadataChanged: (title, icon) {
                      _address.value = title ?? _host;
                      _icon.value = icon;
                    }),
              ),
            ),
          ),
        ),
        builder: (context, minimized, page) => AnimatedBuilder(
            animation: animation!,
            child: page,
            builder: (context, page) => Stack(
                  children: [
                    if (dockProgress > 0)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: IgnorePointer(
                          ignoring: !minimized,
                          child: ClipRect(
                              child: Align(
                            alignment: Alignment.bottomCenter,
                            heightFactor: dockProgress,
                            child: Material(
                              key: const ValueKey('browser-dock-surface'),
                              color: Theme.of(context).colorScheme.surface,
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(AppTokens.rLg))),
                              clipBehavior: Clip.antiAlias,
                              child: SafeArea(
                                  top: false,
                                  child: SizedBox(
                                    height: _barHeight,
                                    child: Row(children: [
                                      IconButton(
                                          tooltip:
                                              Localizations.localeOf(context)
                                                          .languageCode ==
                                                      'zh'
                                                  ? '关闭网页'
                                                  : 'Close page',
                                          onPressed: () => navigator?.pop(),
                                          icon: const Icon(Icons.close)),
                                      Expanded(
                                          child: TextButton(
                                              onPressed: _restore,
                                              child:
                                                  ValueListenableBuilder<
                                                          String>(
                                                      valueListenable: _address,
                                                      builder:
                                                          (_, address, __) =>
                                                              Row(children: [
                                                                ValueListenableBuilder<
                                                                    Uri?>(
                                                                  valueListenable:
                                                                      _icon,
                                                                  builder: (_,
                                                                          icon,
                                                                          __) =>
                                                                      ExcludeSemantics(
                                                                    child:
                                                                        SizedBox(
                                                                      width: AppTokens
                                                                          .chevronSize,
                                                                      height: AppTokens
                                                                          .chevronSize,
                                                                      child: icon ==
                                                                              null
                                                                          ? const Icon(Icons
                                                                              .language)
                                                                          : Image.network(
                                                                              icon.toString(),
                                                                              fit: BoxFit.contain,
                                                                              errorBuilder: (_, __, ___) => const Icon(Icons.language),
                                                                              loadingBuilder: (_, child, progress) => progress == null ? child : const Icon(Icons.language)),
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    width:
                                                                        AppTokens
                                                                            .s3),
                                                                Expanded(
                                                                    child: Text(
                                                                        address,
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis)),
                                                              ])))),
                                      IconButton(
                                          tooltip:
                                              Localizations.localeOf(context)
                                                          .languageCode ==
                                                      'zh'
                                                  ? '展开网页'
                                                  : 'Expand page',
                                          onPressed: _restore,
                                          icon: const Icon(
                                              Icons.keyboard_arrow_up)),
                                    ]),
                                  )),
                            ),
                          )),
                        ),
                      ),
                    Offstage(
                      offstage: minimized,
                      child: FractionalTranslation(
                        translation: Offset(
                            0,
                            minimized
                                ? 0
                                : (_fromMinimized ? _restoreTravel : 1) *
                                    (1 -
                                        (_interactive
                                            ? animation!.value
                                            : AppTokens.browserSheetCurve
                                                .transform(animation!.value)))),
                        child: TickerMode(enabled: !minimized, child: page!),
                      ),
                    ),
                  ],
                )),
      ));

  @override
  Widget buildModalBarrier() => ValueListenableBuilder<bool>(
        valueListenable: _minimized,
        builder: (context, minimized, __) => minimized
            ? const SizedBox.shrink()
            : AnimatedModalBarrier(
                color: ColorTween(
                        begin: _scrim.withValues(alpha: 0), end: barrierColor)
                    .animate(animation!),
                dismissible: true,
                onDismiss: _minimizeFromBarrier,
                semanticsLabel:
                    Localizations.localeOf(context).languageCode == 'zh'
                        ? '收起网页'
                        : 'Minimize page',
              ),
      );

  @override
  void dispose() {
    _icon.dispose();
    _minimized.dispose();
    _address.dispose();
    super.dispose();
  }

  final bool _reduced;
  final Color _scrim;

  @override
  bool get opaque => false;
  @override
  Color? get barrierColor => _scrim.withValues(alpha: .32);
  @override
  bool get barrierDismissible => false;
  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : AppTokens.browserOpenDuration;
  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : AppTokens.browserCloseDuration;

  @override
  DelegatedTransitionBuilder get delegatedTransition =>
      (context, animation, secondaryAnimation, allowSnapshotting, child) {
        if (child == null) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: Listenable.merge([secondaryAnimation, _minimized]),
          child: child,
          builder: (context, child) {
            final progress = _interactive
                ? secondaryAnimation.value
                : AppTokens.browserBackgroundCurve
                    .transform(secondaryAnimation.value);
            final scale = 1 - (1 - AppTokens.browserBackgroundScale) * progress;
            return ColoredBox(
              key: const ValueKey('browser-depth-background'),
              color: _scrim,
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: dockProgress *
                        (_barHeight + MediaQuery.paddingOf(context).bottom)),
                child: Transform.translate(
                  offset:
                      Offset(0, AppTokens.browserBackgroundOffset * progress),
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topCenter,
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppTokens.rLg * progress),
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      };

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}
