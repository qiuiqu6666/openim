import 'dart:async';

/// A deadline releases the caller, never the native login slot. Retries join
/// the same operation until it completes; they cannot submit another login.
class PendingLogin<T> {
  Future<T>? _pending;
  Object? _key;

  Future<T> run(Object key, Future<T> Function() operation,
      {required Duration timeout}) {
    if (_pending != null && key != _key) {
      return Future.error(StateError('Previous login is still pending'));
    }
    if (_pending == null) {
      _key = key;
      final pending = Future<T>.sync(operation);
      _pending = pending;
      pending.then((_) {}, onError: (Object _, StackTrace __) {
        _clear(pending);
      });
    }
    final pending = _pending!;
    return pending.timeout(timeout).then((value) {
      _clear(pending);
      return value;
    });
  }

  void _clear(Future<T> pending) {
    if (identical(_pending, pending)) _pending = null;
  }
}
