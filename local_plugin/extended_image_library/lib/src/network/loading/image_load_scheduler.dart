import 'dart:async';
import 'dart:collection';

/// Cancellation belongs to one decoded image task, never to a shared client.
class ImageLoadCancelled implements Exception {
  const ImageLoadCancelled();
}

class ImageLoadSignal {
  bool _cancelled = false;
  final _callbacks = <void Function()>{};
  bool get isCancelled => _cancelled;

  void check() {
    if (isCancelled) throw const ImageLoadCancelled();
  }

  void Function() onCancel(void Function() callback) {
    if (isCancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
    return () => _callbacks.remove(callback);
  }

  Future<T> bind<T>(Future<T> future) {
    final cancelled = Completer<T>();
    final unregister = onCancel(
      () => cancelled.completeError(const ImageLoadCancelled()),
    );
    return Future.any([future, cancelled.future]).whenComplete(unregister);
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled = true;
    for (final callback in _callbacks.toList()) {
      callback();
    }
    _callbacks.clear();
  }

  void finish() => _callbacks.clear();
}

/// Bounds active downloads/decodes, while cancelled queued work starts no I/O.
class ImageLoadScheduler {
  ImageLoadScheduler({this.maximumActive = 4}) : assert(maximumActive > 0);
  static final shared = ImageLoadScheduler();
  final int maximumActive;
  final _queue = Queue<_ImageLoadJob>();
  int _active = 0;

  Future<T> run<T>(ImageLoadSignal signal, Future<T> Function() operation) {
    signal.check();
    final result = Completer<T>();
    late final _ImageLoadJob job;
    void Function()? unregister;
    job = _ImageLoadJob(() async {
      unregister?.call();
      _active++;
      try {
        signal.check();
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _active--;
        _pump();
      }
    });
    unregister = signal.onCancel(() {
      if (_queue.remove(job)) {
        result.completeError(const ImageLoadCancelled());
      }
    });
    _queue.add(job);
    _pump();
    return result.future;
  }

  void _pump() {
    while (_active < maximumActive && _queue.isNotEmpty) {
      unawaited(_queue.removeFirst().start());
    }
  }
}

class _ImageLoadJob {
  _ImageLoadJob(this.start);
  final Future<void> Function() start;
}
