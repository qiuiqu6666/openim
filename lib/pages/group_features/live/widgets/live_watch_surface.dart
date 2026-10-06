import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../models/group_feature_context.dart';
import '../models/live_models.dart';
import '../models/live_errors.dart';
import '../models/live_summary_events.dart';
import '../playback/live_playback_controller.dart';
import '../playback/live_player_view.dart';
import '../playback/live_watch_state.dart';
import '../playback/live_fullscreen_page.dart';
import '../pages/live_tip_sheet.dart';
import 'live_style.dart';
import 'live_waiting_view.dart';

class GroupLiveWatchSurface extends StatefulWidget {
  const GroupLiveWatchSurface(
      {super.key,
      required this.featureContext,
      required this.session,
      required this.onClose,
      this.onStateChanged,
      this.videoFactory,
      this.anchorFaceURL = ''});
  final GroupFeatureContext featureContext;
  final LiveSession session;
  final VoidCallback onClose;
  final ValueChanged<LiveSession>? onStateChanged;
  final LiveVideoFactory? videoFactory;
  final String anchorFaceURL;
  @override
  State<GroupLiveWatchSurface> createState() => _GroupLiveWatchSurfaceState();
}

class _GroupLiveWatchSurfaceState extends State<GroupLiveWatchSurface>
    with WidgetsBindingObserver {
  late LiveWatchState _state;
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _debounce;
  late LiveSession _reported;
  late LiveSummaryEvents _summaries;
  bool _tipBusy = false;
  final _inlineSurface = Object(), _fullscreenHandoff = Object();
  MaterialPageRoute<void>? _fullscreenRoute;
  NavigatorState? _fullscreenNavigator;
  LiveWatchState? _fullscreenState;
  bool _closingFullscreen = false;
  void _changed() {
    if (!mounted) return;
    if (!_state.watchable) _closeFullscreen();
    if (!_state.current) return;
    final next = _state.session;
    if (next.status != _reported.status ||
        next.version != _reported.version ||
        next.id != _reported.id) {
      _reported = next;
      widget.onStateChanged?.call(next);
    }
  }

  void _init() {
    _state = LiveWatchState(widget.featureContext, widget.session,
        videoFactory: widget.videoFactory);
    _state.setForeground(WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
    _reported = widget.session;
    _summaries = LiveSummaryEvents(widget.featureContext.features);
    _state.addListener(_changed);
    _events = widget.featureContext.events.listen((event) {
      final action =
          '${event['key'] ?? ''}:${event['action'] ?? ''}'.toLowerCase();
      final summary = _summaries.accept(event, widget.featureContext.groupID);
      if (summary != null) _state.acceptSummary(summary);
      if (summary != null &&
          (summary.sessionID != _state.session.id || !summary.isActive)) {
        _debounce?.cancel();
        return;
      }
      if ((summary != null || action.contains('live')) &&
          _state.session.status.active) {
        _debounce?.cancel();
        _debounce = Timer(
            const Duration(milliseconds: 250), () => unawaited(_state.load()));
      }
    });
    unawaited(_state.load());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _resume() async {
    final controller = _state.playback;
    if (controller != null) {
      await controller.resume();
    } else {
      await _state.load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state.setSurfaceVisible(
        _inlineSurface, ModalRoute.of(context)?.isCurrent != false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void didUpdateWidget(covariant GroupLiveWatchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.featureContext.groupID != widget.featureContext.groupID ||
        !identical(oldWidget.featureContext.api, widget.featureContext.api) ||
        !oldWidget.featureContext.sessionCurrent() ||
        oldWidget.featureContext.currentUserID !=
            widget.featureContext.currentUserID) {
      _closeFullscreen();
      _debounce?.cancel();
      unawaited(_events?.cancel() ?? Future<void>.value());
      _state.removeListener(_changed);
      _state.dispose();
      _init();
      _state.setSurfaceVisible(
          _inlineSurface, ModalRoute.of(context)?.isCurrent != false);
    } else if ((widget.session.status != oldWidget.session.status ||
            widget.session.version != oldWidget.session.version) &&
        (widget.session.status != _state.session.status ||
            widget.session.version != _state.session.version)) {
      final statusChanged = widget.session.status != _state.session.status;
      final accepted = _state.acceptSession(widget.session, notify: false);
      if (accepted) {
        _reported = widget.session;
      }
      // A summary has no DTO version. Calibrate a changed status once, but do
      // not reload on ordinary rebuilds or rejected versions of the same state.
      if (_state.session.status.active && (accepted || statusChanged)) {
        unawaited(_state.load());
      }
    }
    final summary = _summaries.accept({
      'groupID': widget.featureContext.groupID,
      'data': {'groupFeatures': widget.featureContext.features.raw}
    }, widget.featureContext.groupID);
    if (summary != null) _state.acceptSummary(summary);
  }

  bool _canTip(GroupFeatureContext value) =>
      value.sessionCurrent() &&
      value.capabilitiesCurrent() &&
      value.capabilities.live.canTip &&
      value.groupID == widget.featureContext.groupID &&
      value.currentUserID == widget.featureContext.currentUserID &&
      _state.playback?.current == true &&
      _state.session.status == LiveStatus.live &&
      value.features.live.sessionID == _state.session.id &&
      value.features.live.isActive;

  Future<void> _tip() async {
    if (_tipBusy ||
        !_state.current ||
        !mounted ||
        !_canTip(widget.featureContext.readCurrentContext())) {
      return;
    }
    _tipBusy = true;
    final openingState = _state;
    final openingContext = widget.featureContext;
    final expectedSession = openingState.session.id;
    try {
      final refreshed = await openingContext.refreshCapabilities(force: true);
      if (!mounted ||
          !identical(openingState, _state) ||
          !_state.current ||
          _state.session.id != expectedSession ||
          !_canTip(refreshed) ||
          !_canTip(openingContext.readCurrentContext())) {
        return;
      }
      await GroupLiveTipSheet.show(context,
          featureContext: refreshed, session: _state.session);
    } catch (failure) {
      if (mounted && identical(openingState, _state) && _state.current) {
        IMViews.showToast(liveErrorMessage(failure));
      }
    } finally {
      _tipBusy = false;
    }
  }

  @override
  void dispose() {
    _closeFullscreen();
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    unawaited(_events?.cancel() ?? Future<void>.value());
    _state.removeListener(_changed);
    _state.dispose();
    super.dispose();
  }

  void _holdFullscreenHandoff(LiveWatchState state) {
    if (!state.watchable) return;
    state.setSurfaceVisible(_fullscreenHandoff, true);
    unawaited(state.playback
            ?.setSurfaceVisible(_fullscreenHandoff, true, owner: state) ??
        Future<void>.value());
  }

  void _releaseFullscreenHandoff(LiveWatchState state) {
    final controller = state.playback;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        state.removeSurface(_fullscreenHandoff);
        unawaited(controller?.removeSurface(_fullscreenHandoff) ??
            Future<void>.value());
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _closeFullscreen() {
    final route = _fullscreenRoute;
    final navigator = _fullscreenNavigator;
    final state = _fullscreenState;
    if (route == null || navigator == null || _closingFullscreen) return;
    _closingFullscreen = true;
    if (state != null) _holdFullscreenHandoff(state);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted || !route.isActive) return;
      if (route.isCurrent) {
        navigator.pop<void>();
      } else {
        navigator.removeRoute(route);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _fullscreen() async {
    if (_fullscreenRoute != null || !_state.watchable) return;
    final state = _state;
    final navigator = Navigator.of(context, rootNavigator: true);
    _holdFullscreenHandoff(state);
    final route = MaterialPageRoute<void>(
      builder: (_) => LiveFullscreenPage(
        state: state,
        onPopped: () => _holdFullscreenHandoff(state),
        builder: (context) => _content(context, state,
            fullscreen: true, onClose: _closeFullscreen),
      ),
    );
    setState(() {
      _fullscreenRoute = route;
      _fullscreenNavigator = navigator;
      _fullscreenState = state;
    });
    try {
      final completed = navigator.push<void>(route);
      _releaseFullscreenHandoff(state);
      await completed;
    } finally {
      if (identical(_fullscreenRoute, route)) {
        _fullscreenRoute = null;
        _fullscreenNavigator = null;
        _fullscreenState = null;
        _closingFullscreen = false;
        if (mounted) setState(() {});
      }
      _releaseFullscreenHandoff(state);
    }
  }

  Widget _content(BuildContext context, LiveWatchState state,
          {bool fullscreen = false, required VoidCallback onClose}) =>
      AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final canOperate = identical(state, _state) && state.watchable;
          if (state.playback != null) {
            return LivePlayerView(
                controller: state.playback!,
                renewalOwner: state,
                fullscreen: fullscreen,
                onClose: onClose,
                onFullscreen: fullscreen
                    ? _closeFullscreen
                    : () => unawaited(_fullscreen()),
                anchorID: state.session.anchorID,
                anchorFaceURL: widget.anchorFaceURL,
                roomName: state.session.roomName,
                description: state.session.description,
                onRetry: () => state.load(refreshCredentials: true),
                onTip: canOperate &&
                        _canTip(widget.featureContext.readCurrentContext())
                    ? () => unawaited(_tip())
                    : null,
                canTip: () =>
                    canOperate &&
                    _canTip(widget.featureContext.readCurrentContext()),
                onResume: _resume);
          }
          return LiveWaitingView(
            loading: state.loading,
            active: state.session.status.active,
            message: !state.current
                ? '直播会话已失效'
                : state.error != null
                    ? liveErrorMessage(state.error!)
                    : state.session.status == LiveStatus.scheduled
                        ? '直播尚未开始，请稍候'
                        : state.session.status == LiveStatus.authorized
                            ? '直播准备中，请稍候…'
                            : state.session.status.label,
            muted: state.muted,
            fullscreen: fullscreen,
            onClose: onClose,
            onFullscreen:
                fullscreen ? _closeFullscreen : () => unawaited(_fullscreen()),
            onMute: canOperate ? () => unawaited(state.toggleMute()) : null,
            onRefresh: canOperate ? () => unawaited(state.load()) : null,
            roomName: state.session.roomName,
            description: state.session.description,
            anchorID: state.session.anchorID,
            anchorFaceURL: widget.anchorFaceURL,
          );
        },
      );

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: LiveStyle.aspect,
        child: _fullscreenRoute != null
            ? const ColoredBox(color: LiveStyle.screen)
            : _content(context, _state, onClose: widget.onClose),
      );
}
