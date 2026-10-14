import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'image_load_scheduler.dart';

/// Marks only the synchronous listener installed by ImageCache.putIfAbsent.
/// Actual widgets and precacheImage attach their listeners after this returns.
class ImageLoadCacheContext {
  static final _marker = Object();
  static final _eviction = Object();
  static bool get addingCacheListener => Zone.current[_marker] == true;
  static void Function()? get evictPending => Zone.current[_eviction];

  static T lookup<T>(T Function() lookup, void Function() evictPending) =>
      runZoned(lookup, zoneValues: {_marker: true, _eviction: evictPending});
}

/// Keeps Flutter's shared decoded cache, but doesn't treat its pending listener
/// as a reason to finish downloading an image no widget needs anymore.
class ManagedImageStreamCompleter extends ImageStreamCompleter {
  ManagedImageStreamCompleter({
    required this.load,
    required this.scale,
    required String label,
  }) : _evictPending = ImageLoadCacheContext.evictPending {
    debugLabel = label;
  }

  final Future<ui.Codec> Function(
    ImageLoadSignal signal,
    void Function(ImageChunkEvent) progress,
  )
  load;
  final double scale;
  final void Function()? _evictPending;
  final _consumers = <ImageStreamListener>[];
  final _cacheListeners = <ImageStreamListener>[];
  ImageLoadSignal? _signal;
  MultiFrameImageStreamCompleter? _decoded;
  ImageStreamListener? _decodedListener;
  ImageStreamCompleterHandle? _decodedHandle;
  bool _loading = false;
  bool _listening = false;
  bool _disposed = false;
  bool _receivedFrame = false;
  bool _failed = false;
  int _generation = 0;

  @override
  void addListener(ImageStreamListener listener) {
    if (ImageLoadCacheContext.addingCacheListener) {
      _cacheListeners.add(listener);
    } else {
      _consumers.add(listener);
    }
    super.addListener(listener);
    if (_consumers.isNotEmpty) {
      if (_decoded != null) {
        _listenDecoded();
      } else if (!_loading && !_failed) {
        _start();
      }
    }
  }

  void _start() {
    _loading = true;
    final generation = ++_generation;
    final signal = _signal = ImageLoadSignal();
    unawaited(() async {
      try {
        final codec = await load(signal, (chunk) {
          if (!signal.isCancelled && _consumers.isNotEmpty) {
            reportImageChunkEvent(chunk);
          }
        });
        if (signal.isCancelled || generation != _generation) {
          codec.dispose();
          return;
        }
        _loading = false;
        _decoded = MultiFrameImageStreamCompleter(
          codec: SynchronousFuture(codec),
          scale: scale,
          debugLabel: debugLabel,
        );
        _decodedHandle = _decoded!.keepAlive();
        _decodedListener = ImageStreamListener(
          (image, _) {
            _receivedFrame = true;
            setImage(image);
          },
          onError:
              (Object error, StackTrace? stack) => reportError(
                context: ErrorDescription('decoding network image'),
                exception: error,
                stack: stack,
                silent: true,
              ),
        );
        if (_consumers.isNotEmpty) _listenDecoded();
      } catch (error, stack) {
        if (signal.isCancelled || generation != _generation) return;
        _loading = false;
        _failed = true;
        reportError(
          context: ErrorDescription('loading network image'),
          exception: error,
          stack: stack,
          silent: true,
        );
      }
    }());
  }

  void _listenDecoded() {
    if (_listening) return;
    _listening = true;
    _decoded!.addListener(_decodedListener!);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    _consumers.remove(listener);
    _cacheListeners.remove(listener);
    super.removeListener(listener);
    if (_consumers.isNotEmpty) return;
    // Reparenting or a same-frame consumer transfer must not restart requests.
    scheduleMicrotask(() {
      if (_disposed || _consumers.isNotEmpty) return;
      if (_loading || !_receivedFrame) {
        ++_generation;
        _loading = false;
        // A paused stream can survive cache eviction through a keepAlive
        // handle. Its old key must not evict a newer task with the same key.
        if (_cacheListeners.isNotEmpty) _evictPending?.call();
        _signal?.cancel();
        _releaseDecoded();
      }
      if (_listening) {
        _decoded!.removeListener(_decodedListener!);
        _listening = false;
      }
    });
  }

  @override
  void onDisposed() {
    _disposed = true;
    ++_generation;
    _signal?.cancel();
    _releaseDecoded();
    super.onDisposed();
  }

  void _releaseDecoded() {
    if (_listening) _decoded!.removeListener(_decodedListener!);
    _listening = false;
    _decodedHandle?.dispose();
    _decodedHandle = null;
    _decoded = null;
    _decodedListener = null;
  }
}
