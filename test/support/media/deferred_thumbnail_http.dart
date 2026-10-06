import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds an actual image response until the test advances its loading lifecycle.
class DeferredThumbnailHttpClient extends Fake implements HttpClient {
  static HttpClientProvider? _previous;
  static bool _installed = false;
  final bytes = Completer<List<int>>();
  int requests = 0;

  void install() {
    _previous = debugNetworkImageHttpClientProvider;
    _installed = true;
    debugNetworkImageHttpClientProvider = () => this;
    addTearDown(() {
      restore();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  static void restore() {
    if (!_installed) return;
    debugNetworkImageHttpClientProvider = _previous;
    _previous = null;
    _installed = false;
  }

  @override
  set autoUncompress(bool value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    return _Request(bytes.future);
  }

  @override
  void close({bool force = false}) {}
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.bytes);
  final Future<List<int>> bytes;
  @override
  final headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response(await bytes);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes);
  final List<int> bytes;
  @override
  final headers = _Headers();
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
