import 'dart:async';
import 'chat_history_diagnostics.dart';

/// Retry a failed window, not every healthy foreground/sync notification.
class ChatHistoryRecovery {
  ChatHistoryRecovery(
      {required this.isActive,
      required this.hasError,
      required this.isLoading,
      required this.retry,
      this.diagnostic,
      required this.windowRevision});
  final bool Function() isActive, hasError, isLoading;
  final Future<bool> Function() retry;
  final int Function() windowRevision;
  final HistoryDiagnostic? diagnostic;
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

  void request({bool resetAttempts = false, String source = 'history_state'}) {
    if (_closed) return;
    // A new foreground/connection epoch deserves a fresh finite retry budget.
    // Internal completion notifications must never renew it themselves.
    if (resetAttempts) {
      diagnostic?.call({
        'event': 'retry_reset',
        'source': source,
        'reason': 'external_event',
        'previousAttempts': _attempts,
        'revision': windowRevision()
      });
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
      if (_attempts > 0) {
        diagnostic?.call({
          'event': 'retry_reset',
          'source': source,
          'reason': 'error_cleared',
          'previousAttempts': _attempts,
          'revision': windowRevision()
        });
      }
      _attempts = 0;
      return;
    }
    if (_revision != windowRevision()) {
      if (_revision >= 0) {
        diagnostic?.call({
          'event': 'retry_reset',
          'source': source,
          'reason': 'window_changed',
          'previousAttempts': _attempts,
          'previousRevision': _revision,
          'revision': windowRevision()
        });
      }
      _revision = windowRevision();
      _attempts = 0;
      _timer?.cancel();
      _timer = null;
    }
    if (_attempts >= 2 || _timer != null) return;
    diagnostic?.call({
      'event': 'retry_scheduled',
      'source': source,
      'attempt': _attempts + 1,
      'revision': _revision
    });
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
      diagnostic?.call({
        'event': 'retry_started',
        'source': source,
        'attempt': _attempts,
        'revision': revision
      });
      var retryRevision = revision;
      try {
        final result = retry();
        // Retrying a date seek intentionally creates a new window generation.
        // It must not reset the finite retry budget for the same failed action.
        retryRevision = windowRevision();
        _revision = retryRevision;
        await result;
        if (!_closed && retryRevision == windowRevision() && !hasError()) {
          diagnostic?.call({
            'event': 'retry_reset',
            'source': source,
            'reason': 'retry_succeeded',
            'previousAttempts': _attempts,
            'revision': retryRevision
          });
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
