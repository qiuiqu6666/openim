import 'dart:async';

import 'package:flutter/widgets.dart';

/// Directional, best-effort gallery warmup with one real image load at a time.
///
/// Navigation replaces the remaining work, but cannot cancel a codec/network
/// operation that Flutter has already started. That operation retains the only
/// slot until its first frame or error, even if it takes longer than a timeout.
class ImagePreviewGalleryPrecache {
  int _lastCenterIndex = -1;
  int _lastDirection = 1;
  bool _running = false;
  bool _disposed = false;
  _GalleryPrecacheRequest? _pending;
  _GalleryImageLoad? _activeLoad;

  void precacheAdjacent({
    required BuildContext context,
    required int centerIndex,
    required int itemCount,
    required ImageProvider? Function(int index) resolveProvider,
    int radius = 3,
  }) {
    if (_disposed) return;
    if (radius <= 0 || itemCount <= 1) {
      invalidate();
      return;
    }
    final direction = centerIndex > _lastCenterIndex
        ? 1
        : centerIndex < _lastCenterIndex
            ? -1
            : _lastDirection;
    _lastCenterIndex = centerIndex;
    _lastDirection = direction;

    final indices = <int>[];
    for (var offset = 1; offset <= radius; offset++) {
      final forward = centerIndex + direction * offset;
      if (forward >= 0 && forward < itemCount) indices.add(forward);
      final backward = centerIndex - direction * offset;
      if (backward >= 0 && backward < itemCount) indices.add(backward);
    }
    _pending = _GalleryPrecacheRequest(
      configuration: createLocalImageConfiguration(context),
      indices: indices,
      resolveProvider: resolveProvider,
    );
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed) {
        // Resolve synchronously in a separate scope so the suspended task does
        // not retain the request's page closure after dispose clears _pending.
        final load = _startNextLoad();
        if (load == null) break;
        try {
          await load.done;
        } finally {
          load.detach();
          _activeLoad = null;
        }
        // Read _pending again: quick navigation keeps only the latest center.
      }
    } finally {
      _running = false;
    }
  }

  _GalleryImageLoad? _startNextLoad() {
    while (!_disposed) {
      final request = _pending;
      if (request == null) return null;
      if (request.cursor >= request.indices.length) {
        _pending = null;
        continue;
      }
      final index = request.indices[request.cursor++];
      try {
        final provider = request.resolveProvider(index);
        if (provider == null) continue;
        final load = _GalleryImageLoad();
        _activeLoad = load;
        load.start(provider, request.configuration);
        return load;
      } catch (_) {
        // A bad provider must not interrupt page disposal or other warmups.
        _activeLoad?.detach();
        _activeLoad = null;
      }
    }
    return null;
  }

  /// Drop queued work. The non-cancellable active load still owns its slot.
  void invalidate() {
    _pending = null;
  }

  /// Terminal cleanup: release our image listener and captured page callbacks.
  /// Flutter may finish an already-started load; this helper starts no more.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending = null;
    _activeLoad?.detach(suppressLateErrors: true);
  }
}

class _GalleryPrecacheRequest {
  _GalleryPrecacheRequest({
    required this.configuration,
    required this.indices,
    required this.resolveProvider,
  });

  final ImageConfiguration configuration;
  final List<int> indices;
  final ImageProvider? Function(int index) resolveProvider;
  int cursor = 0;
}

class _GalleryImageLoad {
  final Completer<void> _done = Completer<void>();
  ImageStream? _stream;
  ImageStreamListener? _listener;

  Future<void> get done => _done.future;

  void start(ImageProvider provider, ImageConfiguration configuration) {
    _stream = provider.resolve(configuration);
    _listener = ImageStreamListener(
      (info, synchronous) {
        info.dispose();
        detach();
      },
      onError: (Object error, StackTrace? stackTrace) => detach(),
    );
    _stream!.addListener(_listener!);
  }

  void detach({bool suppressLateErrors = false}) {
    if (suppressLateErrors) {
      // An error-only callback does not keep animated frames running or retain
      // this load/page. Flutter removes it on the next frame or error.
      _stream?.completer?.addEphemeralErrorListener(_ignoreLateError);
    }
    final listener = _listener;
    _listener = null;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    if (!_done.isCompleted) _done.complete();
  }

  static void _ignoreLateError(Object error, StackTrace? stackTrace) {}
}
