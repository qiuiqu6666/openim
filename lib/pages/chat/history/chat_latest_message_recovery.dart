import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Reconcile persisted conversation updates when an individual delivery was
/// missed. Give ordinary live callbacks time to arrive before reading history.
class ChatLatestMessageRecovery {
  ChatLatestMessageRecovery({
    required this.isClosed,
    required this.latestMessage,
    required this.containsMessage,
    required this.isRemoved,
    required this.refresh,
    required this.canRefresh,
    Duration Function()? elapsed,
    this.diagnostic,
  }) : _elapsed = elapsed ?? _monotonicClock();

  static Duration Function() _monotonicClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }

  static const minimumRefreshInterval = Duration(seconds: 1);
  final Duration Function() _elapsed;
  final void Function(Map<String, Object?>)? diagnostic;
  Duration? _nextRefreshAt;

  final bool Function() isClosed;
  final Message? Function() latestMessage;
  final bool Function(String) containsMessage, isRemoved;
  final Future<bool> Function() refresh;
  final bool Function() canRefresh;
  Timer? _timer;
  bool _closed = false;
  bool _refreshing = false;
  int _revision = 0;
  int _attempts = 0;
  String? _targetID;

  bool get _missing {
    if (_closed || isClosed()) return false;
    final latest = latestMessage();
    final id = latest?.clientMsgID;
    return id != null &&
        id.isNotEmpty &&
        latest!.contentType != MessageType.typing &&
        latest.status != MessageStatus.sending &&
        latest.status != MessageStatus.failed &&
        !isRemoved(id) &&
        !containsMessage(id);
  }

  void conversationChanged({bool resetAttempts = false}) {
    if (_closed || isClosed()) return;
    final targetID = latestMessage()?.clientMsgID;
    if (resetAttempts || targetID != _targetID) {
      _attempts = 0;
      _targetID = targetID;
    }
    if (_refreshing || _timer != null || !_missing || !canRefresh()) return;
    if (_attempts >= 3) return;
    var delay = _attempts == 0
        ? const Duration(milliseconds: 100)
        : Duration(seconds: _attempts == 1 ? 1 : 3);
    // A new latest ID resets its retry count, not the conversation's budget.
    // Use monotonic elapsed time so wall-clock corrections cannot bypass it.
    final remaining = (_nextRefreshAt ?? Duration.zero) - _elapsed();
    if (remaining > delay) delay = remaining;
    _timer = Timer(delay, () {
      _timer = null;
      if (_missing && canRefresh()) unawaited(_reconcile());
    });
  }

  Future<void> _reconcile() async {
    final targetID = latestMessage()?.clientMsgID;
    final revision = _revision;
    _refreshing = true;
    ++_attempts;
    final started = _elapsed();
    _nextRefreshAt = started + minimumRefreshInterval;
    _record('latest_recovery_start', {'attempt': _attempts});
    var applied = false;
    try {
      applied = await refresh();
    } finally {
      _record('latest_recovery_end', {
        'applied': applied,
        'elapsedMs': (_elapsed() - started).inMilliseconds,
      });
      // A newer persisted snapshot can arrive while the loader is coalescing
      // requests. It needs a fresh read after that older request completes.
      if (revision == _revision) {
        _refreshing = false;
        if (applied || targetID != latestMessage()?.clientMsgID) {
          conversationChanged();
        }
      }
    }
  }

  void _record(String phase, Map<String, Object?> values) {
    try {
      diagnostic?.call({'phase': phase, 'source': 'latest_message', ...values});
    } catch (_) {
      // Optional diagnostics must never interrupt message recovery.
    }
  }

  void cancel() {
    ++_revision;
    _attempts = 0;
    _targetID = null;
    _refreshing = false;
    _timer?.cancel();
    _timer = null;
  }

  void close() {
    _closed = true;
    cancel();
  }
}
