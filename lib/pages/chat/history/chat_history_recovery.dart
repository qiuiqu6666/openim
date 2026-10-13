import 'dart:async';

/// Retry a failed window, not every healthy foreground/sync notification.
class ChatHistoryRecovery {
  ChatHistoryRecovery(
      {required this.isActive,
      required this.hasError,
      required this.isLoading,
      required this.retry,
      required this.windowRevision});
  final bool Function() isActive, hasError, isLoading;
  final Future<bool> Function() retry;
  final int Function() windowRevision;
  Timer? _timer;
  int _attempts = 0, _revision = -1;
  bool _closed = false, _running = false;
  bool _waitingForHistory = false;
  bool _requestedWhileRunning = false;

  void loadingSettled() {
    if (!_waitingForHistory) return;
    _waitingForHistory = false;
    request();
  }

  void request({bool resetAttempts = false}) {
    if (_closed) return;
    // A new foreground/connection epoch deserves a fresh finite retry budget.
    // Internal completion notifications must never renew it themselves.
    if (resetAttempts) {
      _attempts = 0;
      _timer?.cancel();
      _timer = null;
      if (_running) _requestedWhileRunning = true;
    }
    if (!isActive() || _running) return;
    if (isLoading()) {
      _waitingForHistory = true;
      return;
    }
    if (!hasError()) {
      _attempts = 0;
      return;
    }
    if (_revision != windowRevision()) {
      _revision = windowRevision();
      _attempts = 0;
      _timer?.cancel();
      _timer = null;
    }
    if (_attempts >= 2 || _timer != null) return;
    final revision = _revision;
    _timer = Timer(Duration(seconds: _attempts == 0 ? 1 : 3), () async {
      _timer = null;
      if (_closed || !isActive() || revision != windowRevision()) {
        return;
      }
      if (isLoading()) {
        _waitingForHistory = true;
        return;
      }
      if (!hasError()) return;
      _running = true;
      ++_attempts;
      var retryRevision = revision;
      try {
        final result = retry();
        // Retrying a date seek intentionally creates a new window generation.
        // It must not reset the finite retry budget for the same failed action.
        retryRevision = windowRevision();
        _revision = retryRevision;
        await result;
        if (!_closed && retryRevision == windowRevision() && !hasError()) {
          _attempts = 0;
        }
      } catch (_) {
        // The history owner retains its error and manual retry action.
      } finally {
        _running = false;
        final requested = _requestedWhileRunning;
        _requestedWhileRunning = false;
        if (requested || retryRevision == windowRevision()) request();
      }
    });
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }
}
