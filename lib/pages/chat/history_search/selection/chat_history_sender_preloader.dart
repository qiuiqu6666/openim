import 'dart:async';

/// Serial, paced continuation for the member picker. Both requesting a page
/// and applying its response wait while the user scrolls or the route is hidden.
class ChatHistorySenderPreloader {
  ChatHistorySenderPreloader({required this.load, required this.canLoad});

  final Future<void> Function() load;
  final bool Function() canLoad;
  static const _delay = Duration(milliseconds: 350);
  Timer? _timer;
  Completer<bool>? _idleWaiter;
  final _pointers = <int>{};
  bool _active = true, _scrolling = false, _running = false, _disposed = false;
  int _generation = 0;

  bool get isIdle => !_disposed && _active && !_scrolling && _pointers.isEmpty;

  void setActive(bool value) {
    _active = value;
    if (!value) {
      // A covered list may not dispatch its final pointer/scroll notification.
      resetInteraction();
    } else {
      _sync();
    }
  }

  void resetInteraction() {
    _pointers.clear();
    _scrolling = false;
    _sync();
  }

  void pointerChanged(int pointer, {required bool down}) {
    if (down) {
      _pointers.add(pointer);
    } else {
      _pointers.remove(pointer);
    }
    _sync();
  }

  void setScrolling(bool value) {
    _scrolling = value;
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    if (!isIdle) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    final waiter = _idleWaiter;
    _idleWaiter = null;
    waiter?.complete(true);
    schedule();
  }

  Future<bool> waitUntilIdle() {
    if (_disposed) return Future.value(false);
    if (isIdle) return Future.value(true);
    return (_idleWaiter ??= Completer<bool>()).future;
  }

  void schedule() {
    if (!isIdle || _running || _timer != null || !canLoad()) return;
    _timer = Timer(_delay, () {
      _timer = null;
      if (isIdle && canLoad()) unawaited(_loadNext());
    });
  }

  Future<void> _loadNext() async {
    final generation = _generation;
    _running = true;
    try {
      await load();
    } finally {
      if (generation == _generation) {
        _running = false;
        schedule();
      }
    }
  }

  /// Invalidate a search's queued continuation and any deferred old response.
  /// An SDK request already in flight is discarded by the page's generation.
  void cancel() {
    ++_generation;
    _running = false;
    _timer?.cancel();
    _timer = null;
    final waiter = _idleWaiter;
    _idleWaiter = null;
    waiter?.complete(false);
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
