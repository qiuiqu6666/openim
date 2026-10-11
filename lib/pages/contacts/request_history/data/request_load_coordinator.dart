import 'dart:async';

/// Share an active read; notifications may queue one fresh read behind it.
/// The follow-up runs even if the old request failed, so changes are not lost.
class RequestLoadCoordinator {
  Future<void>? _active;
  Future<void> Function()? _next;
  bool _closed = false;
  bool get busy => _active != null;

  Future<void> run(Future<void> Function() load, {bool refreshAfter = false}) {
    if (_closed) return Future.value();
    if (_active != null) {
      if (refreshAfter) _next = load;
      return _active!;
    }
    final completion = Completer<void>();
    _active = completion.future;
    unawaited(_drain(load, completion));
    return completion.future;
  }

  Future<void> _drain(
      Future<void> Function() load, Completer<void> completion) async {
    Object? failure;
    StackTrace? trace;
    Future<void> Function()? next = load;
    while (next != null && !_closed) {
      try {
        await next();
        failure = null;
      } catch (error, stack) {
        failure = error;
        trace = stack;
      }
      next = _next;
      _next = null;
    }
    _active = null;
    if (failure == null) {
      completion.complete();
    } else {
      completion.completeError(failure, trace);
    }
  }

  void close() {
    _closed = true;
    _next = null;
  }
}
