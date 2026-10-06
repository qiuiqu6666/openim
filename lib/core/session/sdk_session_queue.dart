import 'dart:async';

/// An obsolete request cannot publish a login result into a newer session.
class SdkSessionCancelled extends StateError {
  SdkSessionCancelled() : super('SDK session changed');
}

class SdkSessionBusy implements Exception {}

/// SDK login and logout must finish in order: timing out an await does not
/// cancel the native operation, so a later login may never bypass cleanup.
class SdkSessionQueue {
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _closed = false;
  int get generation => _generation;
  bool isCurrent(int generation) => !_closed && generation == _generation;
  void invalidate() => ++_generation;
  void close() {
    _closed = true;
    invalidate();
  }

  Future<T> login<T>(
    Future<T> Function() operation, {
    Future<void> Function()? prepare,
    Duration startTimeout = const Duration(seconds: 15),
  }) {
    final generation = ++_generation;
    final result = Completer<T>();
    var started = false;
    final timer = Timer(startTimeout, () {
      if (started) return;
      if (isCurrent(generation)) invalidate();
      result.completeError(SdkSessionBusy());
    });
    _enqueue(() async {
      if (!isCurrent(generation)) throw SdkSessionCancelled();
      await prepare?.call();
      if (!isCurrent(generation)) throw SdkSessionCancelled();
      started = true;
      timer.cancel();
      final value = await operation();
      if (!isCurrent(generation)) throw SdkSessionCancelled();
      return value;
    }).then((value) {
      if (!result.isCompleted) result.complete(value);
    }, onError: (Object error, StackTrace trace) {
      timer.cancel();
      if (!result.isCompleted) result.completeError(error, trace);
    });
    return result.future;
  }

  Future<void> logout(Future<void> Function() operation) {
    invalidate();
    return _enqueue(operation);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final pending = _tail.then((_) => operation());
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return pending;
  }
}
