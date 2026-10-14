import 'dart:async';

/// A connection epoch refreshes one latest window. Older history belongs to
/// explicit paging; resuming never walks forward from a stale message cursor.
class ChatBackgroundMessageRecovery {
  ChatBackgroundMessageRecovery({
    required this.canRead,
    required this.refreshLatest,
    required this.onError,
  });

  final bool Function() canRead;
  final Future<bool> Function() refreshLatest;
  final void Function(Object) onError;
  Future<bool>? _request;
  Timer? _retry;
  int _revision = 0, _attempts = 0;
  bool _pending = false, _closed = false, _rerun = false;

  bool get hasCheckpoint => _pending;

  void suspend() {
    if (_closed) return;
    _pending = true;
    restart();
  }

  void restart({bool verifyCheckpoint = false}) {
    _attempts = 0;
    _retry?.cancel();
    _retry = null;
    if (_request != null) _rerun = true;
  }

  Future<bool> recover() {
    if (_closed || !_pending || !canRead()) return Future.value(false);
    if (_request != null) {
      _rerun = true;
      return _request!;
    }
    _retry?.cancel();
    _retry = null;
    final revision = _revision;
    final completer = Completer<bool>();
    _request = completer.future;
    ++_attempts;
    () async {
      var applied = false;
      try {
        applied = await refreshLatest();
      } catch (error) {
        if (!_closed && revision == _revision) onError(error);
      }
      if (!_closed && revision == _revision) {
        _request = null;
        // Two finite rechecks cover a native commit completing just after a
        // foreground query. A new connection epoch can renew this budget.
        if (canRead() && (_rerun || _attempts < 3)) {
          final delay = _rerun
              ? Duration.zero
              : Duration(seconds: _attempts == 1 ? 1 : 3);
          _retry = Timer(delay, () {
            _retry = null;
            unawaited(recover());
          });
        }
        _rerun = false;
      }
      completer.complete(applied && !_closed && revision == _revision);
    }();
    return completer.future;
  }

  void cancel() {
    ++_revision;
    _pending = false;
    _request = null;
    _rerun = false;
    restart();
  }

  void close() {
    _closed = true;
    cancel();
  }
}
