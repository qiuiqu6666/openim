import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../utils/media/openim_media_url.dart';
import '../../utils/media/shared_image_disk_cache.dart';

/// One viewer owns this request, including its socket and decoded image.
/// Encoded disk files are shared, but cancellation never affects another view.
class ViewerImageProvider extends ImageProvider<ViewerImageProvider> {
  ViewerImageProvider(String url,
      {this.maxPixels = 16 * 1024 * 1024,
      this.cacheOnly = false,
      HttpClient Function()? createClient,
      BaseCacheManager? cache,
      SharedImageDiskCache? sharedCache})
      : url = OpenIMMediaUrl.repairThumbnail(url),
        _sharedCache = sharedCache ?? SharedImageDiskCache(),
        _createClient = createClient ?? HttpClient.new,
        _cache = cache;
  final HttpClient Function() _createClient;
  final BaseCacheManager? _cache;
  final SharedImageDiskCache _sharedCache;

  final String url;
  final int maxPixels;
  final bool cacheOnly;
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

  /// Checks encoded originals without starting a download or decoding pixels.
  Future<bool> isCached() async {
    try {
      if (await _sharedCache.contains(url)) return true;
    } catch (_) {}
    try {
      final entry =
          await (_cache ?? DefaultCacheManager()).getFileFromCache(url);
      return entry != null &&
          await entry.file.exists() &&
          await entry.file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ViewerImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      ViewerImageProvider key, ImageDecoderCallback decode) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(decode, chunks).whenComplete(chunks.close),
      chunkEvents: chunks.stream,
      scale: 1,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode,
      StreamController<ImageChunkEvent> chunks) async {
    final cache = _cache ?? DefaultCacheManager();
    Uint8List? bytes;
    try {
      bytes = await _sharedCache.read(url);
    } catch (_) {
      // A missing/unavailable shared cache must not prevent viewing.
    }
    _check();
    final sharedHit = bytes != null;
    if (bytes == null) {
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
    }
    if (bytes == null) {
      _check();
      if (cacheOnly) throw StateError('Image not yet cached');
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
        bytes = await consolidateHttpClientResponseBytes(response,
            onBytesReceived: (received, total) {
          if (!_cancelled) {
            chunks.add(ImageChunkEvent(
                cumulativeBytesLoaded: received, expectedTotalBytes: total));
          }
        }).timeout(const Duration(seconds: 45));
        _check();
      } finally {
        client.close(force: true);
        _client = null;
        _request = null;
      }
    }
    _check();
    // Also migrate an existing viewer-only cache hit for future bubble reuse.
    if (!sharedHit) {
      try {
        await _sharedCache.write(url, bytes, isCurrent: () => !_cancelled);
      } catch (_) {
        _check();
        try {
          await cache.putFile(url, bytes);
        } catch (_) {}
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
