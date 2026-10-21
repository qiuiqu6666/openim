import 'dart:async';

/// A total deadline cannot be extended by progress. Only increasing progress
/// resets inactivity; cancellation stops observation, never claims native IO ended.
Future<T> waitMediaOperation<T>(
  Future<T> operation, {
  required Duration totalTimeout,
  required Duration idleTimeout,
  required bool Function() isCancelled,
  Stream<double>? progress,
}) async {
  final result = Completer<T>();
  void fail(Object error) {
    if (!result.isCompleted) result.completeError(error);
  }

  Timer? idle;
  void resetIdle() {
    idle?.cancel();
    idle = Timer(
        idleTimeout,
        () => fail(
            TimeoutException('Media operation made no progress', idleTimeout)));
  }

  resetIdle();
  final total = Timer(
      totalTimeout,
      () => fail(TimeoutException(
          'Media operation exceeded total deadline', totalTimeout)));
  final cancellation = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (isCancelled()) fail(StateError('Media operation cancelled'));
  });
  double maximum = -1;
  final subscription = progress?.listen((value) {
    if (value.isFinite && value > maximum && !result.isCompleted) {
      maximum = value;
      resetIdle();
    }
  });
  operation.then((value) {
    if (!result.isCompleted) result.complete(value);
  }, onError: (Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  });
  if (isCancelled()) fail(StateError('Media operation cancelled'));
  try {
    return await result.future;
  } finally {
    idle?.cancel();
    total.cancel();
    cancellation.cancel();
    await subscription?.cancel();
  }
}
