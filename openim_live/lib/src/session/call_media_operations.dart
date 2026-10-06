/// Serializes native media changes and prevents queued work after shutdown.
class CallMediaOperations {
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  bool get closed => _closed;

  Future<bool> run(Future<void> Function() operation) {
    if (_closed) return Future<bool>.value(false);
    final result = _tail.then((_) async {
      if (_closed) return false;
      await operation();
      return true;
    });
    // A failed operation must not poison the next change or the cleanup barrier.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Closes admission synchronously and waits for the operation already running.
  Future<void> close() {
    _closed = true;
    return _tail;
  }
}

/// Owns a captured resource even before publication succeeds.
class CallMediaResources<T extends Object> {
  CallMediaResources({required this.disposeResource});

  final Future<void> Function(T) disposeResource;
  final Set<T> _owned = Set<T>.identity();
  Future<void>? _releasing;

  Future<void> captureAndPublish({
    required Future<T> Function() capture,
    required Future<void> Function(T) publish,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    final resource = await capture();
    _owned.add(resource);
    try {
      if (!isCurrent()) {
        await _release(resource);
        return;
      }
      await publish(resource);
      if (!isCurrent()) await _release(resource);
    } catch (_) {
      await _release(resource);
      rethrow;
    }
  }

  Future<void> _release(T resource) async {
    if (_owned.remove(resource)) await disposeResource(resource);
  }

  /// Call after the media operation barrier has settled.
  Future<void> release() => _releasing ??= _releaseAll();

  Future<void> _releaseAll() async {
    Object? firstError;
    StackTrace? firstStack;
    for (final resource in _owned.toList()) {
      try {
        await _release(resource);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}
