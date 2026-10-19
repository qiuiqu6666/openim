import 'dart:async';

/// The server badge and the launcher badge have independent completion times.
/// Serialize each destination without making the launcher wait for the network.
class AppBadgeCoordinator {
  AppBadgeCoordinator({
    required Future<void> Function(int) updateRemote,
    required Future<bool> Function() isSystemSupported,
    required Future<void> Function(int) updateSystem,
    required void Function(Object) onError,
    DateTime Function()? now,
  }) {
    _remote = _BadgeWriter(
      write: (count, _) => updateRemote(count),
      onError: onError,
      minimumInterval: const Duration(seconds: 1),
      now: now,
    );
    _system = _BadgeWriter(
      write: (count, isCurrent) async {
        _systemSupported ??= await isSystemSupported();
        if (isCurrent() && _systemSupported!) await updateSystem(count);
      },
      onError: onError,
      now: now,
    );
  }

  late final _BadgeWriter _remote;
  late final _BadgeWriter _system;
  bool? _systemSupported;
  Object? _session;
  bool _closed = false;

  void beginSession(Object session) {
    if (_closed || _session == session) return;
    resetSession();
    _session = session;
  }

  void setCount(int count) {
    if (_closed || _session == null) return;
    final normalized = count < 0 ? 0 : count;
    _remote.setCount(normalized);
    _system.setCount(normalized);
  }

  void onForeground() {
    if (_closed || _session == null) return;
    // APNs can change the launcher while Dart is suspended. Restore it once,
    // without sending the unchanged count to the server again.
    _system.invalidate();
    _remote.retryPending();
  }

  void resetSession() {
    _session = null;
    _remote.reset();
    _system.reset();
  }

  void close() {
    _closed = true;
    resetSession();
    _remote.close();
    _system.close();
  }
}

class _BadgeWriter {
  _BadgeWriter({
    required this.write,
    required this.onError,
    this.minimumInterval = Duration.zero,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration minimumInterval;
  final DateTime Function() _now;
  DateTime? _nextWriteAt;
  final Future<void> Function(int, bool Function()) write;
  final void Function(Object) onError;
  int? _desired;
  int? _lastWritten;
  int _generation = 0;
  bool _running = false;
  bool _closed = false;
  Timer? _scheduled;
  DateTime? _retryAfter;

  void setCount(int count) {
    if (_closed) return;
    _desired = count;
    _schedule();
  }

  void invalidate() {
    ++_generation;
    _lastWritten = null;
    _schedule();
  }

  void retryPending() => _schedule();

  void reset() {
    ++_generation;
    _desired = null;
    _lastWritten = null;
    _retryAfter = null;
    _nextWriteAt = null;
    _scheduled?.cancel();
    _scheduled = null;
    // An already submitted native request still owns its slot until completion.
  }

  void close() {
    _closed = true;
    reset();
  }

  void _schedule() {
    if (_closed ||
        _running ||
        _scheduled != null ||
        _desired == null ||
        _desired == _lastWritten) {
      return;
    }
    var delay = _retryAfter?.difference(_now()) ?? Duration.zero;
    final rateDelay = _nextWriteAt?.difference(_now()) ?? Duration.zero;
    if (rateDelay > delay) delay = rateDelay;
    // Keep this deadline fixed during a burst: sustained arrivals must not
    // postpone the trailing latest value indefinitely.
    _scheduled = Timer(delay.isNegative ? Duration.zero : delay, () {
      _scheduled = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    final count = _desired;
    if (_closed || _running || count == null || count == _lastWritten) return;
    final generation = _generation;
    bool isCurrent() =>
        !_closed && generation == _generation && count == _desired;
    _running = true;
    _nextWriteAt = _now().add(minimumInterval);
    // A -> B -> A while B is in flight must restore A after B completes,
    // even though A was the last value confirmed before this request.
    _lastWritten = null;
    var failed = false;
    try {
      await write(count, isCurrent);
      if (isCurrent()) {
        _lastWritten = count;
        _retryAfter = null;
      }
    } catch (error) {
      failed = true;
      if (!_closed && generation == _generation) {
        _lastWritten = null;
        _retryAfter = _now().add(const Duration(seconds: 5));
        onError(error);
      }
    } finally {
      _running = false;
      // Failure is retried by the next observation/foreground event, with a
      // cooldown. Never create a self-sustaining retry loop while offline.
      if (!failed || generation != _generation || count != _desired) {
        _schedule();
      }
    }
  }
}
