import 'dart:async';

import 'package:dio/dio.dart';

import '../../data/group_feature_store.dart';
import '../../models/group_features.dart';
import 'live_api.dart';

/// Reconciles only visible list groups against the existing single-group API.
/// Avatar widgets register visibility; this owner handles networking and timers.
class GroupLiveListSync {
  GroupLiveListSync({
    required this.store,
    required this.userID,
    required this.sessionCurrent,
    this.interval = const Duration(seconds: 45),
    this.maxConcurrent = 2,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    assert(interval > Duration.zero);
    assert(maxConcurrent > 0);
    store.addListener(_checkScope);
  }

  final GroupFeatureStore store;
  final String userID;
  final bool Function() sessionCurrent;
  final Duration interval;
  final int maxConcurrent;
  final DateTime Function() _clock;
  final _sources = <Object, String>{};
  final _subscriptions = <String, StreamSubscription<Map<String, dynamic>>>{};
  final _debounces = <String, Timer>{};
  final _reads = <String, _LiveListRead>{};
  final _queued = <String>{};
  final _followUps = <String>{};
  final _freshUntil = <String, DateTime>{};
  final _retryAfter = <String, DateTime>{};
  Timer? _poll;
  bool _enabled = false, _disposed = false, _drainScheduled = false;

  bool get _scopeCurrent => !_disposed && store.active && sessionCurrent();
  bool get _active => _enabled && _scopeCurrent;
  bool _visible(String id) => _sources.containsValue(id);

  void setVisible(Object source, String groupID, bool visible) {
    if (_disposed) return;
    final id = groupID.trim();
    final previous = _sources[source];
    if (visible && id.isNotEmpty) {
      if (previous == id) return;
      _sources[source] = id;
      if (previous != null && !_visible(previous)) _unwatch(previous);
      if (!_subscriptions.containsKey(id)) {
        _subscriptions[id] =
            store.events(id).listen((event) => _onEvent(id, event));
        _enqueue(id);
      }
    } else if (previous == id) {
      _sources.remove(source);
      if (!_visible(id)) _unwatch(id);
    }
    _updatePolling();
  }

  /// The list scope supplies tab, route and app visibility together.
  void setActive(bool active) {
    if (_disposed) return;
    if (!active || !_scopeCurrent) {
      _stop();
      return;
    }
    if (_enabled) return;
    _enabled = true;
    refreshVisible();
    _updatePolling();
  }

  void refreshVisible() {
    if (!_active) {
      _checkScope();
      return;
    }
    for (final id in _sources.values.toSet()) {
      _enqueue(id, force: true);
    }
  }

  void _checkScope() {
    if (!_disposed && !_scopeCurrent) _stop();
  }

  void _updatePolling() {
    if (!_active || _sources.isEmpty) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(interval, (_) => refreshVisible());
  }

  void _onEvent(String id, Map<String, dynamic> event) {
    if (!_active || !_visible(id)) return;
    if (event['action'] == 'left') {
      _cancelRead(id);
      _queued.remove(id);
      _followUps.remove(id);
      _debounces.remove(id)?.cancel();
      return;
    }
    if (!const {
      'groupLiveChanged',
      'groupFeaturesChanged',
      'groupFeatureCapabilitiesChanged',
    }.contains(event['key'])) {
      return;
    }
    final data = featureMap(event['data']);
    final summary =
        GroupFeatures.fromJson(event['groupFeatures'] ?? data['groupFeatures']);
    // Store already accepted complete snapshots. In particular, our own current
    // response publishes this event and must not trigger another current read.
    if (summary.valid) return;
    if (_reads.containsKey(id)) _followUps.add(id);
    _debounces.remove(id)?.cancel();
    _debounces[id] = Timer(const Duration(milliseconds: 250), () {
      _debounces.remove(id);
      if (_reads.containsKey(id)) {
        _followUps.add(id);
      } else {
        _followUps.remove(id);
        _enqueue(id, force: true);
      }
    });
  }

  void _enqueue(String id, {bool force = false}) {
    if (!_active || !_visible(id)) return;
    final now = _clock();
    if (_retryAfter[id]?.isAfter(now) == true ||
        (!force && _freshUntil[id]?.isAfter(now) == true)) {
      return;
    }
    // List activation, refresh and polling reuse the in-flight request. Only a
    // newer business notice requests a follow-up, rather than every rebuild.
    if (_reads.containsKey(id)) return;
    _queued.add(id);
    if (_drainScheduled) return;
    _drainScheduled = true;
    scheduleMicrotask(() {
      _drainScheduled = false;
      _drain();
    });
  }

  void _drain() {
    if (!_active) {
      _checkScope();
      return;
    }
    while (_reads.length < maxConcurrent && _queued.isNotEmpty) {
      final id = _queued.first;
      _queued.remove(id);
      if (!_visible(id)) continue;
      final context = store.context(
        id: id,
        name: '',
        userID: userID,
        admin: false,
        current: () => _active && _visible(id),
      );
      if (!context.sessionCurrent()) continue;
      final read = _LiveListRead();
      _reads[id] = read;
      unawaited(_read(id, read));
    }
  }

  bool _readCurrent(String id, _LiveListRead read) =>
      _active && _visible(id) && identical(_reads[id], read);

  Future<void> _read(String id, _LiveListRead read) async {
    final context = store.context(
      id: id,
      name: '',
      userID: userID,
      admin: false,
      current: () => _readCurrent(id, read),
    );
    try {
      await LiveApi(context).current(cancelToken: read.cancel);
      if (!_readCurrent(id, read)) return;
      _freshUntil[id] = _clock().add(interval);
      _retryAfter.remove(id);
    } catch (_) {
      if (!_readCurrent(id, read)) return;
      // Missing services, denied membership and transport errors retain the
      // last verified state and cannot flood retries during scrolling.
      _retryAfter[id] = _clock().add(const Duration(seconds: 30));
    } finally {
      if (identical(_reads[id], read)) {
        _reads.remove(id);
        if (_followUps.remove(id) && _active && _visible(id)) {
          _debounces.remove(id)?.cancel();
          _debounces[id] = Timer(const Duration(milliseconds: 250), () {
            _debounces.remove(id);
            _enqueue(id, force: true);
          });
        }
        _drain();
      }
    }
  }

  void _cancelRead(String id) {
    _reads.remove(id)?.cancel.cancel('Live list group is no longer visible');
  }

  void _unwatch(String id) {
    _subscriptions.remove(id)?.cancel();
    _debounces.remove(id)?.cancel();
    _queued.remove(id);
    _followUps.remove(id);
    _cancelRead(id);
    if (_active) _drain();
  }

  void _stop() {
    _enabled = false;
    // Returning to the list may activate its scope before the first row reports
    // visibility. That row still needs a fresh read, unlike brief scroll jitter.
    _freshUntil.clear();
    _poll?.cancel();
    _poll = null;
    for (final timer in _debounces.values) {
      timer.cancel();
    }
    _debounces.clear();
    _queued.clear();
    _followUps.clear();
    for (final id in _reads.keys.toList()) {
      _cancelRead(id);
    }
  }

  void dispose() {
    if (_disposed) return;
    _stop();
    _disposed = true;
    store.removeListener(_checkScope);
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _sources.clear();
    _freshUntil.clear();
    _retryAfter.clear();
  }
}

class _LiveListRead {
  final cancel = CancelToken();
}
