import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../data/group_feature_api.dart';
import '../../models/group_feature_context.dart';
import '../data/live_api.dart';
import '../models/live_models.dart';
import '../models/live_summary_events.dart';
import 'live_playback_controller.dart';

class LiveWatchState extends ChangeNotifier {
  LiveWatchState(this.context, this.session,
      {this.videoFactory, DateTime Function()? now, this.schedule})
      : _now = now ?? DateTime.now;
  final GroupFeatureContext context;
  final LiveVideoFactory? videoFactory;
  final LiveCredentialScheduler? schedule;
  final DateTime Function() _now;
  LiveSession session;
  LivePlaybackController? playback;
  bool loading = false, _closed = false;
  bool _foreground = true, _surfaceActive = true, _wasPaused = false;
  Object? error;
  Future<void>? _request;
  CancelToken? _requestCancel;
  int _epoch = 0;
  GroupLiveFeature? _summary;
  final _surfaces = <Object, bool>{};
  bool _muted = false;
  bool get current => !_closed && context.sessionCurrent();
  bool get watchable =>
      current &&
      session.status.active &&
      (_summary == null ||
          (_summary!.isActive && _summary!.sessionID == session.id));
  bool get muted => playback?.muted ?? _muted;

  Future<void> toggleMute() async {
    if (!current) return;
    _muted = !muted;
    final controller = playback;
    if (controller != null) await controller.setMuted(_muted);
    if (current) notifyListeners();
  }

  void setSurfaceVisible(Object surface, bool visible) {
    if (!current) return;
    _surfaces[surface] = visible;
    setSurfaceActive(_surfaces.values.any((value) => value));
  }

  void removeSurface(Object surface) {
    _surfaces.remove(surface);
    if (current) setSurfaceActive(_surfaces.values.any((value) => value));
  }

  bool get _canLoad =>
      watchable &&
      _foreground &&
      (_surfaceActive || playback?.isOwnerVisible(this) == true);

  void _invalidateRequest() {
    ++_epoch;
    _requestCancel?.cancel();
    _requestCancel = null;
    _request = null;
    loading = false;
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) _invalidateRequest();
    final controller = playback;
    if (controller != null) {
      unawaited(controller.setForeground(value));
    } else if (value && _canLoad) {
      unawaited(load());
    }
  }

  void setSurfaceActive(bool value) {
    if (_surfaceActive == value) return;
    _surfaceActive = value;
    if (!_canLoad) _invalidateRequest();
    if (value && playback == null && _canLoad) unawaited(load());
  }

  void acceptSummary(GroupLiveFeature value) {
    if (!current) return;
    _summary = value;
    if (value.sessionID != session.id || !value.isActive) {
      _invalidateRequest();
      _releasePlayback(stopShared: true);
      error = StateError(liveSummaryStopReason(value, session.id));
    }
    notifyListeners();
  }

  bool acceptSession(LiveSession value,
      {bool notify = true, bool invalidateRequest = true}) {
    if (!current ||
        value.id != session.id ||
        value.version < session.version ||
        (session.status == LiveStatus.live &&
            value.version == session.version &&
            const {LiveStatus.scheduled, LiveStatus.authorized}
                .contains(value.status)) ||
        (!session.status.active &&
            value.status.active &&
            value.version <= session.version)) {
      return false;
    }
    session = value;
    if (session.status != LiveStatus.live) {
      if (invalidateRequest) _invalidateRequest();
      _releasePlayback(stopShared: true);
    }
    if (notify) notifyListeners();
    return true;
  }

  Future<void> load({bool refreshCredentials = false}) {
    if (_request != null) return _request!;
    if (!_canLoad) return Future.value();
    loading = true;
    error = null;
    notifyListeners();
    final epoch = _epoch;
    final cancel = CancelToken();
    _requestCancel = cancel;
    late final Future<void> request;
    request = _load(
            refreshCredentials: refreshCredentials,
            epoch: epoch,
            cancel: cancel)
        .whenComplete(() {
      if (!identical(_request, request)) return;
      _request = null;
      _requestCancel = null;
      loading = false;
      if (current) notifyListeners();
    });
    return _request = request;
  }

  Future<void> _load(
      {required bool refreshCredentials,
      required int epoch,
      required CancelToken cancel}) async {
    try {
      final api = LiveApi(context);
      final latest = await api.detail(session.id, cancelToken: cancel);
      if (!_canLoad || epoch != _epoch) return;
      if (!acceptSession(latest, notify: false, invalidateRequest: false)) {
        return;
      }
      final summary = _summary;
      if (summary != null &&
          (summary.sessionID != session.id || !summary.isActive)) {
        error = StateError(liveSummaryStopReason(summary, session.id));
        return;
      }
      if (session.status != LiveStatus.live) return;
      final controller = playback;
      final expiry = controller?.info.expiresAt;
      if (!refreshCredentials &&
          controller?.current == true &&
          (expiry == null ||
              expiry.isAfter(_now().add(const Duration(seconds: 10))))) {
        return;
      }
      final info = await api.play(session.id, cancelToken: cancel);
      if (!_canLoad || epoch != _epoch) return;
      if (info.expiresAt != null && !info.expiresAt!.isAfter(_now())) {
        throw const FormatException('直播播放凭据已过期，请重试');
      }
      if (controller?.current == true) {
        await controller!.updateCredentials(info);
      } else {
        _releasePlayback();
        final next = LivePlaybackOwner.acquire(
            context.currentUserID, info, context.sessionCurrent,
            factory: videoFactory,
            now: _now,
            schedule: schedule,
            muted: _muted);
        playback = next;
        _wasPaused = next.paused;
        next.addListener(_playbackChanged);
        next.registerRenewal(this,
            isCurrent: () =>
                _canLoad &&
                session.status == LiveStatus.live &&
                next.isOwnerVisible(this),
            renew: () => _calibrate(refreshCredentials: true),
            calibrate: _calibrate);
      }
    } catch (failure) {
      if (_canLoad && epoch == _epoch && !cancel.isCancelled) {
        error = failure;
        if (failure is GroupFeatureException &&
            const {'20068', '20070', '20012', '1002', 'FORBIDDEN'}
                .contains(failure.code.toUpperCase())) {
          _releasePlayback(stopShared: true);
        }
      }
    }
  }

  Future<void> _calibrate({bool refreshCredentials = false}) async {
    await load(refreshCredentials: refreshCredentials);
    if (!_canLoad) return;
    if (error != null) throw error!;
  }

  void _playbackChanged() {
    final paused = playback?.paused == true;
    if ((paused && !_wasPaused) || !_canLoad) _invalidateRequest();
    _wasPaused = paused;
  }

  void _releasePlayback({bool stopShared = false}) {
    final old = playback;
    playback = null;
    if (old == null) return;
    _muted = old.muted;
    old.removeListener(_playbackChanged);
    old.unregisterRenewal(this);
    if (stopShared) old.dispose();
    LivePlaybackOwner.release(old);
  }

  @override
  void dispose() {
    _closed = true;
    _surfaces.clear();
    _invalidateRequest();
    _releasePlayback();
    super.dispose();
  }
}
