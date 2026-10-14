import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui show Codec;
import 'package:extended_image_library/src/extended_image_provider.dart';
import 'package:extended_image_library/src/platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http_client_helper/http_client_helper.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'extended_network_image_provider.dart' as image_provider;
import 'loading/image_load_scheduler.dart';
import 'loading/cancellable_image_body.dart';
import 'loading/managed_image_stream.dart';
import 'loading/prepared_image_codec.dart';

class ExtendedNetworkImageProvider
    extends ImageProvider<image_provider.ExtendedNetworkImageProvider>
    with ExtendedImageProvider<image_provider.ExtendedNetworkImageProvider>
    implements image_provider.ExtendedNetworkImageProvider {
  /// Creates an object that fetches the image at the given URL.
  ///
  /// The arguments must not be null.
  ExtendedNetworkImageProvider(
    this.url, {
    this.scale = 1.0,
    this.headers,
    this.cache = false,
    this.retries = 3,
    this.timeLimit,
    this.timeRetry = const Duration(milliseconds: 100),
    this.cacheKey,
    this.printError = true,
    this.cacheRawData = false,
    this.cancelWhenUnused = false,
    this.cancelToken,
    this.imageCacheName,
    this.cacheMaxAge,
    this.webHtmlElementStrategy = WebHtmlElementStrategy.never,
  });

  /// The name of [ImageCache], you can define custom [ImageCache] to store this provider.
  @override
  final String? imageCacheName;

  /// Whether cache raw data if you need to get raw data directly.
  /// For example, we need raw image data to edit,
  /// but [ui.Image.toByteData()] is very slow. So we cache the image
  /// data here.
  @override
  final bool cacheRawData;

  @override
  final bool cancelWhenUnused;

  /// The time limit to request image
  @override
  final Duration? timeLimit;

  /// The time to retry to request
  @override
  final int retries;

  /// The time duration to retry to request
  @override
  final Duration timeRetry;

  /// Whether cache image to local
  @override
  final bool cache;

  /// The URL from which the image will be fetched.
  @override
  final String url;

  /// The scale to place in the [ImageInfo] object of the image.
  @override
  final double scale;

  /// The HTTP headers that will be used with [HttpClient.get] to fetch image from network.
  @override
  final Map<String, String>? headers;

  /// The token to cancel network request
  @override
  final CancellationToken? cancelToken;

  /// Custom cache key
  @override
  final String? cacheKey;

  /// print error
  @override
  final bool printError;

  /// The max duration to cahce image.
  /// After this time the cache is expired and the image is reloaded.
  @override
  final Duration? cacheMaxAge;

  @override
  final WebHtmlElementStrategy webHtmlElementStrategy;

  @override
  ImageStreamCompleter loadImage(
    image_provider.ExtendedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    if (cancelWhenUnused) {
      return ManagedImageStreamCompleter(
        scale: key.scale,
        label: key.url,
        load: (signal, progress) {
          final chunks = StreamController<ImageChunkEvent>();
          chunks.stream.listen(progress);
          return ImageLoadScheduler.shared
              .run(
                signal,
                () => prepareImageCodec(
                  () => _loadAsync(
                    key as ExtendedNetworkImageProvider,
                    chunks,
                    decode,
                    signal,
                  ),
                  signal,
                ),
              )
              .whenComplete(() async {
                signal.finish();
                await chunks.close();
              });
        },
      );
    }
    // Ownership of this controller is handed off to [_loadAsync]; it is that
    // method's responsibility to close the controller's stream when the image
    // has been loaded or an error is thrown.
    final StreamController<ImageChunkEvent> chunkEvents =
        StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(
        key as ExtendedNetworkImageProvider,
        chunkEvents,
        decode,
      ).whenComplete(() => chunkEvents.close()),
      scale: key.scale,
      chunkEvents: chunkEvents.stream,
      debugLabel: key.url,
      informationCollector: () {
        return <DiagnosticsNode>[
          DiagnosticsProperty<ImageProvider>('Image provider', this),
          DiagnosticsProperty<image_provider.ExtendedNetworkImageProvider>(
            'Image key',
            key,
          ),
        ];
      },
    );
  }

  @override
  Future<ExtendedNetworkImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<ExtendedNetworkImageProvider>(this);
  }

  Future<ui.Codec> _loadAsync(
    ExtendedNetworkImageProvider key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode, [
    ImageLoadSignal? signal,
  ]) async {
    signal?.check();
    assert(key == this);
    final String md5Key = cacheKey ?? keyToMd5(key.url);
    ui.Codec? result;
    if (cache) {
      try {
        final Uint8List? data = await _loadCache(key, chunkEvents, md5Key);
        signal?.check();
        if (data != null) {
          result = await instantiateImageCodec(data, decode);
        }
      } catch (e) {
        if (signal?.isCancelled ?? false) rethrow;
        if (printError) {
          print(e);
        }
      }
    }

    if (result == null) {
      try {
        final Uint8List? data = await _loadNetwork(key, chunkEvents, signal);
        signal?.check();
        if (data != null) {
          result = await instantiateImageCodec(data, decode);
          if (cache && !(signal?.isCancelled ?? false)) {
            // Persist only complete bytes that the decoder accepted.
            await _storeCache(data, md5Key);
          }
        }
      } catch (e) {
        if (signal?.isCancelled ?? false) rethrow;
        if (printError) {
          print(e);
        }
      }
    }

    if (signal?.isCancelled ?? false) {
      result?.dispose();
      throw const ImageLoadCancelled();
    }
    //Failed to load
    if (result == null) {
      //result = await ui.instantiateImageCodec(kTransparentImage);
      return Future<ui.Codec>.error(StateError('Failed to load $url.'));
    }

    return result;
  }

  Future<void> _storeCache(Uint8List data, String md5Key) async {
    try {
      final directory = Directory(
        join((await getTemporaryDirectory()).path, cacheImageFolderName),
      );
      await directory.create(recursive: true);
      final temporary = File(
        join(
          directory.path,
          '$md5Key.${DateTime.now().microsecondsSinceEpoch}.part',
        ),
      );
      try {
        await temporary.writeAsBytes(data);
        await temporary.rename(join(directory.path, md5Key));
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } catch (_) {
      // Cache failures must not hide an otherwise usable image.
    }
  }

  /// Get the image from cache folder.
  Future<Uint8List?> _loadCache(
    ExtendedNetworkImageProvider key,
    StreamController<ImageChunkEvent>? chunkEvents,
    String md5Key,
  ) async {
    final Directory directory = Directory(
      join((await getTemporaryDirectory()).path, cacheImageFolderName),
    );
    final File cached = File(join(directory.path, md5Key));
    // Cache misses need no directory creation; _storeCache owns that step.
    // Keep metadata access off the UI isolate's synchronous I/O path too.
    if (!await cached.exists()) return null;
    final Duration? maxAge = key.cacheMaxAge;
    if (maxAge != null) {
      final FileStat stat = await cached.stat();
      if (DateTime.now().subtract(maxAge).isAfter(stat.changed)) {
        await cached.delete();
        return null;
      }
    }
    return cached.readAsBytes();
  }

  /// Get the image from network.
  Future<Uint8List?> _loadNetwork(
    ExtendedNetworkImageProvider key,
    StreamController<ImageChunkEvent>? chunkEvents, [
    ImageLoadSignal? signal,
  ]) async {
    try {
      final Uri resolved = Uri.base.resolve(key.url);
      final HttpClientResponse? response = await _tryGetResponse(
        resolved,
        signal,
      );
      if (response == null || response.statusCode != HttpStatus.ok) {
        if (response != null) {
          // The network may be only temporarily unavailable, or the file will be
          // added on the server later. Avoid having future calls to resolve
          // fail to check the network again.
          final body =
              timeLimit == null ? response : response.timeout(timeLimit!);
          await cancellableImageBody(body, signal).drain<void>();
        }
        return null;
      }

      // Apply an inactivity deadline to the stream that is actually consumed.
      // await-for cancels its subscription on timeout; partial files are never
      // written to the cache. Unknown/compressed lengths remain indeterminate.
      final builder = BytesBuilder(copy: false);
      final progressClock = Stopwatch()..start();
      var lastProgressMs = -100;
      final body = timeLimit == null ? response : response.timeout(timeLimit!);
      final decodedBody =
          response.compressionState ==
                  HttpClientResponseCompressionState.compressed
              ? gzip.decoder.bind(body)
              : body;
      await for (final chunk in cancellableImageBody(decodedBody, signal)) {
        signal?.check();
        builder.add(chunk);
        final finalChunk =
            response.contentLength > 0 &&
            builder.length == response.contentLength;
        if (chunkEvents != null &&
            !chunkEvents.isClosed &&
            (finalChunk ||
                progressClock.elapsedMilliseconds - lastProgressMs >= 100)) {
          lastProgressMs = progressClock.elapsedMilliseconds;
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: builder.length,
              expectedTotalBytes:
                  response.contentLength > 0 &&
                          response.compressionState ==
                              HttpClientResponseCompressionState.notCompressed
                      ? response.contentLength
                      : null,
            ),
          );
        }
      }
      final Uint8List bytes = builder.takeBytes();
      if (bytes.lengthInBytes == 0) {
        return Future<Uint8List>.error(
          StateError('NetworkImage is an empty file: $resolved'),
        );
      }

      return bytes;
    } on OperationCanceledError catch (_) {
      if (printError) {
        print('User cancel request $url.');
      }
      return Future<Uint8List>.error(StateError('User cancel request $url.'));
    } catch (e) {
      if (signal?.isCancelled ?? false) rethrow;
      if (printError) {
        print(e);
      }
    } finally {
      await chunkEvents?.close();
    }
    return null;
  }

  Future<HttpClientResponse> _getResponse(
    Uri resolved, [
    ImageLoadSignal? signal,
  ]) async {
    var expired = false;
    final opening = httpClient.getUrl(resolved).then((request) {
      if (expired || (signal?.isCancelled ?? false)) {
        // The awaiting task has already left; consume abort's response error.
        request.close().ignore();
        request.abort();
      }
      return request;
    });
    final HttpClientRequest request;
    try {
      request =
          await (signal?.bind(
                timeLimit == null ? opening : opening.timeout(timeLimit!),
              ) ??
              (timeLimit == null ? opening : opening.timeout(timeLimit!)));
    } on TimeoutException {
      expired = true;
      rethrow;
    }
    signal?.check();
    // Abort waiting headers; cancellableImageBody owns body cancellation.
    final unregister = signal?.onCancel(
      () => request.abort(const ImageLoadCancelled()),
    );
    headers?.forEach((String name, String value) {
      request.headers.add(name, value);
    });
    try {
      final response = request.close();
      return await (timeLimit == null
          ? response
          : response.timeout(timeLimit!));
    } on TimeoutException {
      request.abort();
      rethrow;
    } finally {
      unregister?.call();
    }
  }

  // Http get with cancel, delay try again
  Future<HttpClientResponse?> _tryGetResponse(
    Uri resolved, [
    ImageLoadSignal? signal,
  ]) async {
    signal?.check();
    cancelToken?.throwIfCancellationRequested();
    return await RetryHelper.tryRun<HttpClientResponse>(
      () {
        signal?.check();
        return CancellationTokenSource.register(
          cancelToken,
          _getResponse(resolved, signal),
        );
      },
      cancelToken: cancelToken,
      timeRetry: timeRetry,
      retries: retries,
      throwThenExpction: () => signal?.isCancelled ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is ExtendedNetworkImageProvider &&
        url == other.url &&
        scale == other.scale &&
        cacheRawData == other.cacheRawData &&
        cancelWhenUnused == other.cancelWhenUnused &&
        timeLimit == other.timeLimit &&
        cancelToken == other.cancelToken &&
        timeRetry == other.timeRetry &&
        cache == other.cache &&
        cacheKey == other.cacheKey &&
        //headers == other.headers &&
        retries == other.retries &&
        imageCacheName == other.imageCacheName &&
        cacheMaxAge == other.cacheMaxAge;
  }

  @override
  int get hashCode => Object.hash(
    url,
    scale,
    cacheRawData,
    cancelWhenUnused,
    timeLimit,
    cancelToken,
    timeRetry,
    cache,
    cacheKey,
    //headers,
    retries,
    imageCacheName,
    cacheMaxAge,
  );

  @override
  String toString() => '$runtimeType("$url", scale: $scale)';

  @override
  /// Get network image data from cached
  Future<Uint8List?> getNetworkImageData({
    StreamController<ImageChunkEvent>? chunkEvents,
  }) async {
    final String uId = cacheKey ?? keyToMd5(url);

    try {
      if (cache) {
        try {
          final cached = await _loadCache(this, chunkEvents, uId);
          if (cached != null && cached.isNotEmpty) return cached;
        } catch (_) {
          // A missing/unreadable cache must still fall back to the network.
        }
      }
      final data = await _loadNetwork(this, chunkEvents);
      if (cache && data != null) await _storeCache(data, uId);
      return data;
    } finally {
      await chunkEvents?.close();
    }
  }

  // Do not access this field directly; use [_httpClient] instead.
  // Compressed responses are decoded by the bounded stream above. Their wire
  // content length is not used as the decoded image's progress denominator.
  static final HttpClient _sharedHttpClient =
      HttpClient()..autoUncompress = false;

  static HttpClient get httpClient {
    HttpClient client = _sharedHttpClient;
    assert(() {
      if (debugNetworkImageHttpClientProvider != null) {
        client = debugNetworkImageHttpClientProvider!();
      }
      return true;
    }());
    return client;
  }
}
