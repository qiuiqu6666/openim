import 'dart:async';

/// One native attempt; cancellation settles Dart immediately, and the FIFO
/// cancel acknowledgement precedes any subsequent native start.
class NativeShieldPreparation {
  NativeShieldPreparation(
      {required this.startNative,
      required this.cancelNative,
      this.timeout = const Duration(seconds: 20)});
  final Future<void> Function(bool Function() isCurrent) startNative;
  final Future<void> Function() cancelNative;
  final Duration timeout;
  Future<void> _barrier = Future.value();
  _Attempt? _active;

  Future<void> prepare() {
    final previous = _active;
    if (previous != null) return previous.result.future;
    final attempt = _active = _Attempt();
    unawaited(_run(attempt));
    return attempt.result.future;
  }

  Future<void> _run(_Attempt attempt) async {
    bool current() => identical(_active, attempt);
    try {
      await _barrier;
      if (!current()) return;
      await Future.any<void>([
        Future.sync(() => startNative(current)),
        attempt.cancelled.future,
      ]).timeout(timeout);
      if (current() && !attempt.result.isCompleted) {
        attempt.result.complete();
      }
    } catch (error, stack) {
      if (current()) {
        _enqueueCancel();
        if (!attempt.result.isCompleted) {
          attempt.result.completeError(error, stack);
        }
      }
    } finally {
      if (current()) _active = null;
    }
  }

  Future<void> cancel() {
    final attempt = _active;
    if (attempt == null) return _barrier;
    _active = null;
    attempt.cancelled.complete();
    if (!attempt.result.isCompleted) {
      attempt.result.completeError(StateError('Shield preparation cancelled'));
    }
    return _enqueueCancel();
  }

  Future<void> _enqueueCancel() => _barrier = _barrier.then((_) async {
        try {
          await cancelNative().timeout(const Duration(seconds: 2));
        } catch (_) {}
      });
}

class _Attempt {
  final result = Completer<void>();
  final cancelled = Completer<void>();
}
