import 'dart:async';

/// Reconciles SDK aggregate notifications with the page-owned SDK row snapshot.
/// A count is a refresh signal, never permission to clear individual rows.
class ConversationUnreadSync {
  ConversationUnreadSync({
    required this.isActive,
    required this.isReading,
    required this.flushChanges,
    required this.localUnreadCount,
    required this.reload,
    this.onError,
  });

  final bool Function() isActive;
  final bool Function() isReading;
  final void Function() flushChanges;
  final int Function() localUnreadCount;
  final Future<void> Function() reload;
  final void Function(Object error, StackTrace stack)? onError;
  static const settleDelay = Duration(milliseconds: 220);

  Timer? _timer;
  int? _sdkTotal;
  int _generation = 0;
  bool _queued = false;
  bool _force = false;
  bool _running = false;
  bool _waitingForSnapshot = false;
  bool _followupAvailable = false;
  bool _closed = false;

  bool get _active => !_closed && isActive();

  void onTotalUnreadChanged(int count) {
    if (!_active || count < 0 || count == _sdkTotal) return;
    _sdkTotal = count;
    _followupAvailable = true;
    _queued = true;
    _schedule();
  }

  /// A foreground/reconnection may follow read changes made while offline.
  void reconcile() {
    if (!_active) return;
    _force = true;
    _followupAvailable = true;
    _queued = true;
    _schedule();
  }

  void snapshotFinished() {
    if (!_active || !_waitingForSnapshot) return;
    _waitingForSnapshot = false;
    _schedule();
  }

  /// A row changed during the read cannot use its older snapshot to clear
  /// unread. If that fence left a mismatch, allow one fresh pass per signal.
  void snapshotReconciled({required bool hadChanges}) {
    if (!_active || !hadChanges || !_followupAvailable || _queued) return;
    if (_sdkTotal != null && localUnreadCount() == _sdkTotal) return;
    _followupAvailable = false;
    _queued = true;
    _force = true;
    _schedule();
  }

  void _schedule() {
    if (!_active || !_queued || _running || _waitingForSnapshot) return;
    _timer ??= Timer(settleDelay, () => unawaited(_check()));
  }

  Future<void> _check() async {
    _timer = null;
    if (!_active) return;
    if (isReading()) {
      _waitingForSnapshot = true;
      return;
    }
    final generation = _generation;
    final force = _force;
    _force = false;
    _queued = false;
    _running = true;
    try {
      // Row callbacks commonly follow the aggregate in the same SDK burst.
      flushChanges();
      if (!force && (_sdkTotal == null || localUnreadCount() == _sdkTotal)) {
        return;
      }
      await reload();
    } catch (error, stack) {
      if (_active && generation == _generation) onError?.call(error, stack);
    } finally {
      if (generation == _generation) {
        _running = false;
        // Only a new signal can request another pass. Repeated notifications
        // emitted by the query itself cannot create a refresh/retry loop.
        _schedule();
      }
    }
  }

  void reset() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _sdkTotal = null;
    _queued = false;
    _force = false;
    _running = false;
    _waitingForSnapshot = false;
    _followupAvailable = false;
  }

  void close() {
    _closed = true;
    reset();
  }
}
