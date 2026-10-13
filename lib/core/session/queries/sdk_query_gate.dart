import 'dart:async';

/// A UI timeout never frees a slot still occupied by a native SDK request.
class SdkQueryGate<T> {
  SdkQueryGate({this.limit = 1}) : assert(limit > 0);
  final int limit;
  final _pending = <Object, Future<T>>{};
  bool _closed = false;
  bool get isFull => _pending.length >= limit;

  Future<T> run(Object key, Future<T> Function() operation,
      {required Duration timeout, bool Function()? isCurrent}) async {
    final elapsed = Stopwatch()..start();
    while (true) {
      if (_closed || isCurrent?.call() == false) {
        throw StateError('SDK query owner changed');
      }
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('SDK queries are still pending', timeout);
      }
      var request = _pending[key];
      if (request == null && !isFull) {
        request = Future<T>.sync(operation);
        _pending[key] = request;
        final started = request;
        void release() {
          if (identical(_pending[key], started)) _pending.remove(key);
        }

        unawaited(started.then<void>((_) => release(),
            onError: (Object _, StackTrace __) => release()));
      }
      if (request != null) {
        final result = await request.timeout(remaining);
        if (_closed || isCurrent?.call() == false) {
          throw StateError('SDK query owner changed');
        }
        return result;
      }
      await Future.any(_pending.values.map((value) =>
              value.then<void>((_) {}, onError: (Object _, StackTrace __) {})))
          .timeout(remaining);
    }
  }

  void close() => _closed = true;
}
