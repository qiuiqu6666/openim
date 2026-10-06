import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../models/live_models.dart';
import 'live_credential_renewal.dart';
export 'live_credential_renewal.dart'
    show LiveCredentialScheduler, LiveScheduledTask;

typedef LiveVideoFactory = VideoPlayerController Function(Uri source);

/// One native player for small-screen, room and fullscreen surfaces.
class LivePlaybackController extends ChangeNotifier {
  LivePlaybackController(this.info,
      {required this.sessionCurrent,
      this.muted = false,
      LiveVideoFactory? factory,
      DateTime Function()? now,
      LiveCredentialScheduler? schedule})
      : _factory = factory ?? VideoPlayerController.networkUrl {
    _renewal = LiveCredentialRenewal(
        isActive: () => current && _canDisplay && !paused,
        expiresAt: () => info.expiresAt,
        onExpired: _credentialsExpired,
        now: now,
        schedule: schedule);
    _renewal.credentialsChanged();
  }
  LivePlayInfo info;
  final bool Function() sessionCurrent;
  final LiveVideoFactory _factory;
  final _closed = StreamController<void>.broadcast();
  VideoPlayerController? player;
  Timer? _startup;
  late final LiveCredentialRenewal _renewal;
  final _surfaces = <Object, ({bool visible, Object? owner})>{};
  bool _surfaceTracking = false,
      _foreground = true,
      _expiredCredentials = false;
  Future<void>? _resumeWork;
  Future<void>? _muteWork;
  VideoPlayerController? _muteOwner;
  int _muteGeneration = 0, _muteRevision = 0;
  int _generation = 0, _source = 0;
  bool disposed = false, ready = false, loading = false, paused = false;
  bool muted;
  Object? muteError;
  Object? error;
  bool get current => !disposed && sessionCurrent();
  bool get _canDisplay =>
      _foreground &&
      (!_surfaceTracking || _surfaces.values.any((surface) => surface.visible));
  bool isOwnerVisible(Object owner) =>
      !_surfaceTracking ||
      _surfaces.values.any((surface) =>
          surface.visible &&
          (surface.owner == null || identical(surface.owner, owner)));

  void registerRenewal(Object owner,
          {required bool Function() isCurrent,
          required Future<void> Function() renew,
          required Future<void> Function() calibrate}) =>
      _renewal.register(owner,
          isCurrent: isCurrent, renew: renew, calibrate: calibrate);
  void unregisterRenewal(Object owner) => _renewal.unregister(owner);

  Future<void> setSurfaceVisible(Object surface, bool visible,
      {Object? owner}) {
    if (!current) return Future.value();
    _surfaceTracking = true;
    _surfaces[surface] = (visible: visible, owner: owner);
    return _visibilityChanged();
  }

  Future<void> removeSurface(Object surface) {
    _surfaces.remove(surface);
    return _visibilityChanged();
  }

  Future<void> setForeground(bool value) {
    if (_foreground == value) {
      // An earlier surface may report resume before its watch owner is active.
      // A later surface retries the same shared, merged resume operation.
      return value && paused ? _visibilityChanged() : Future.value();
    }
    _foreground = value;
    return _visibilityChanged();
  }

  Future<void> _visibilityChanged() {
    if (!current) return Future.value();
    if (!_canDisplay) return suspend();
    if (paused) return resume();
    _renewal.refresh();
    return Future.value();
  }

  // A route must close even when its surface is removed during the same build.
  // Async delivery keeps navigation and ChangeNotifier disposal independent.
  Stream<void> get closeEvents => _closed.stream;

  Future<void> updateCredentials(LivePlayInfo value) {
    if (!current || value.id != info.id) return Future.value();
    info = value;
    _source = 0;
    _expiredCredentials = false;
    _renewal.credentialsChanged();
    return open();
  }

  Future<void> open({bool nextSource = false}) async {
    if (!current || !_canDisplay || _expiredCredentials) return;
    final generation = ++_generation;
    _startup?.cancel();
    final old = player;
    player = null;
    old?.removeListener(_changed);
    await old?.dispose();
    if (!current || !_canDisplay || generation != _generation) return;
    final sources = info.supportedSources;
    if (nextSource && _source + 1 < sources.length) _source++;
    if (sources.isEmpty) {
      error = StateError('未配置可播放的 HTTP FLV/HLS 直播地址');
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    ready = false;
    paused = false;
    _renewal.refresh();
    error = null;
    notifyListeners();
    final candidate = _factory(sources[_source]);
    player = candidate;
    candidate.addListener(_changed);
    _startup = Timer(const Duration(seconds: 12), () {
      if (current && generation == _generation && !ready) {
        _failed(StateError('直播连接较慢，请重试'));
      }
    });
    try {
      await candidate.initialize();
      if (!current || generation != _generation) return;
      await _applyMute(candidate, generation);
      if (!current || generation != _generation) return;
      if (muteError != null) throw muteError!;
      await candidate.play();
    } catch (failure) {
      if (!current || generation != _generation) return;
      _startup?.cancel();
      _failed(failure);
    }
  }

  void _changed() {
    if (!current || player == null) return;
    if (_expiredCredentials) {
      notifyListeners();
      return;
    }
    final value = player!.value;
    if (value.hasError) {
      _failed(StateError('直播播放异常，请重试'));
      return;
    } else if (!ready &&
        value.isInitialized &&
        value.position > Duration.zero) {
      // video_player exposes position, not a first-rendered-frame callback.
      ready = true;
      loading = false;
      error = null;
      _startup?.cancel();
    }
    notifyListeners();
  }

  void _failed(Object failure) {
    _startup?.cancel();
    loading = false;
    error = failure;
    if (_source + 1 < info.supportedSources.length) {
      // Try the finite list of backend-provided HTTP fallbacks, without new HTTP
      // credential requests or simultaneous native players.
      unawaited(open(nextSource: true));
    } else if (current) {
      notifyListeners();
    }
  }

  Future<void> toggleMute() => setMuted(!muted);

  /// Keep the choice before initialization and across fullscreen/source changes.
  /// Native writes are serialized so a slower earlier click cannot restore sound.
  Future<void> setMuted(bool value) {
    if (!current || (muted == value && muteError == null)) {
      return Future.value();
    }
    muted = value;
    muteError = null;
    ++_muteRevision;
    notifyListeners();
    final candidate = player;
    if (candidate == null || !candidate.value.isInitialized) {
      return Future.value();
    }
    return _applyMute(candidate, _generation);
  }

  Future<void> _applyMute(VideoPlayerController candidate, int generation) {
    if (!current ||
        generation != _generation ||
        !identical(player, candidate)) {
      return Future.value();
    }
    final existing = _muteWork;
    if (existing != null &&
        identical(_muteOwner, candidate) &&
        _muteGeneration == generation) {
      return existing;
    }
    _muteOwner = candidate;
    _muteGeneration = generation;
    late final Future<void> work;
    work = _writeMute(candidate, generation).whenComplete(() {
      if (identical(_muteWork, work)) _muteWork = null;
    });
    return _muteWork = work;
  }

  Future<void> _writeMute(
      VideoPlayerController candidate, int generation) async {
    while (
        current && generation == _generation && identical(player, candidate)) {
      final revision = _muteRevision;
      final requested = muted;
      Object? failure;
      try {
        await candidate.setVolume(requested ? 0 : 1);
      } catch (_) {
        failure = StateError('声音设置失败，请重试');
      }
      if (!current ||
          generation != _generation ||
          !identical(player, candidate)) {
        return;
      }
      if (revision != _muteRevision) continue;
      muteError = failure;
      notifyListeners();
      return;
    }
  }

  Future<void> suspend() async {
    if (!current) return;
    final wasPaused = paused;
    paused = true;
    ++_generation;
    _renewal.cancel();
    _resumeWork = null;
    loading = false;
    _startup?.cancel();
    notifyListeners();
    if (!wasPaused) await player?.pause();
    if (current) notifyListeners();
  }

  Future<void> resume() {
    if (!paused ||
        !current ||
        !_canDisplay ||
        (_renewal.hasClients && !_renewal.hasActiveClient)) {
      return Future.value();
    }
    final existing = _resumeWork;
    if (existing != null) return existing;
    late final Future<void> work;
    work = _resume().whenComplete(() {
      if (identical(_resumeWork, work)) _resumeWork = null;
    });
    return _resumeWork = work;
  }

  Future<void> _resume() async {
    final generation = _generation;
    try {
      await _renewal.calibrate();
      if (!current || !_canDisplay || generation != _generation) return;
      if (paused) await open();
      _renewal.refresh();
    } catch (_) {
      if (current && _canDisplay && generation == _generation) {
        error = StateError('暂时无法更新直播播放状态，请重试');
        notifyListeners();
      }
    }
  }

  void _credentialsExpired() {
    if (!current || !_canDisplay) return;
    _expiredCredentials = true;
    ++_generation;
    _startup?.cancel();
    ready = loading = false;
    error = StateError('直播播放凭据已过期，请重试');
    unawaited(player?.pause() ?? Future.value());
    notifyListeners();
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    _closed.add(null);
    unawaited(_closed.close());
    ++_generation;
    _renewal.dispose();
    _surfaces.clear();
    _startup?.cancel();
    player?.removeListener(_changed);
    unawaited(player?.dispose() ?? Future<void>.value());
    player = null;
    super.dispose();
  }
}

/// A room and its inline surface may share a decoder; a different room replaces it.
abstract final class LivePlaybackOwner {
  static LivePlaybackController? _active;
  static String? _key;
  static int _leases = 0;
  static LivePlaybackController acquire(
      String accountID, LivePlayInfo info, bool Function() sessionCurrent,
      {LiveVideoFactory? factory,
      bool muted = false,
      DateTime Function()? now,
      LiveCredentialScheduler? schedule}) {
    final key = '$accountID|${info.id}';
    if (_active?.current == true && _key == key) {
      _leases++;
      if (_active!.info.playURL != info.playURL ||
          _active!.info.expiresAt != info.expiresAt) {
        unawaited(_active!.updateCredentials(info));
      }
      return _active!;
    }
    _active?.dispose();
    _active = LivePlaybackController(info,
        sessionCurrent: sessionCurrent,
        muted: muted,
        factory: factory,
        now: now,
        schedule: schedule);
    _key = key;
    _leases = 1;
    unawaited(_active!.open());
    return _active!;
  }

  static void release(LivePlaybackController controller) {
    if (!identical(_active, controller)) return;
    if (--_leases <= 0) {
      _active = null;
      _key = null;
      controller.dispose();
    }
  }
}
