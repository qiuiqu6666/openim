import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// One viewer owns this request, including its socket and decoded image.
/// Encoded disk files are shared, but cancellation never affects another view.
class ViewerImageProvider extends ImageProvider<ViewerImageProvider> {
  ViewerImageProvider(this.url,
      {this.maxPixels = 16 * 1024 * 1024,
      HttpClient Function()? createClient,
      BaseCacheManager? cache})
      : _createClient = createClient ?? HttpClient.new,
        _cache = cache;
  final HttpClient Function() _createClient;
  final BaseCacheManager? _cache;

  final String url;
  final int maxPixels;
  HttpClient? _client;
  HttpClientRequest? _request;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _request?.abort();
    _client?.close(force: true);
    PaintingBinding.instance.imageCache.evict(this);
  }

  void _check() {
    if (_cancelled) throw StateError('Image viewer request cancelled');
  }

  @override
  Future<ViewerImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          ViewerImageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final cache = _cache ?? DefaultCacheManager();
    Uint8List? bytes;
    try {
      final cached = await cache.getFileFromCache(url);
      _check();
      if (cached != null && await cached.file.exists()) {
        bytes = await cached.file.readAsBytes();
      }
    } catch (_) {
      _check();
      // A missing disk cache must not prevent normal preview playback.
    }
    if (bytes == null) {
      _check();
      final client = _client = _createClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final request = await client.getUrl(Uri.parse(url));
        _request = request;
        _check();
        final response =
            await request.close().timeout(const Duration(seconds: 30));
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Image HTTP ${response.statusCode}');
        }
        bytes = await consolidateHttpClientResponseBytes(response)
            .timeout(const Duration(seconds: 45));
        _check();
        // Disk persistence is best effort; only the current request writes it.
        try {
          await cache.putFile(url, bytes);
        } catch (_) {}
      } finally {
        client.close(force: true);
        _client = null;
        _request = null;
      }
    }
    _check();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    if (_cancelled) {
      buffer.dispose();
      _check();
    }
    return decode(buffer, getTargetSize: (width, height) {
      final ratio = math.min(1.0, math.sqrt(maxPixels / (width * height)));
      return ui.TargetImageSize(
          width: math.max(1, (width * ratio).round()),
          height: math.max(1, (height * ratio).round()));
    });
  }
}
