import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/public_health_check.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Adapter implements HttpClientAdapter {
  RequestOptions? request;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString('{"service":"chat-api","status":"ok"}', 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('probe isolates saved credentials and uses actual installed build info',
      () async {
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '9.8.7',
      buildNumber: '654',
      buildSignature: '',
    );
    final adapter = _Adapter();
    var authInterceptorCalled = false;
    final client = Dio(BaseOptions(headers: {
      'token': 'saved-token',
      'Authorization': 'Bearer saved',
      'Cookie': 'login=saved',
    }, queryParameters: {
      'token': 'saved-query'
    }))
      ..httpClientAdapter = adapter
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        authInterceptorCalled = true;
        request.headers['token'] = 'intercepted-token';
        handler.next(request);
      }));
    addTearDown(() => client.close(force: true));
    PublicHealthCheck.isolate(client, const Duration(seconds: 3));
    await PublicHealthCheck.get(client, 'https://example.test/',
        service: 'chat-api', cancelToken: CancelToken());
    final request = adapter.request!;
    expect(authInterceptorCalled, isFalse);
    expect(request.uri.toString(), 'https://example.test/healthz');
    expect(request.queryParameters, isEmpty);
    final names = request.headers.keys.map((k) => k.toLowerCase());
    for (final forbidden in ['token', 'authorization', 'cookie']) {
      expect(names, isNot(contains(forbidden)));
    }
    expect(request.headers['X-Client-Version'], '9.8.7+654');
    expect(request.headers['X-Client-Source'], 'line-probe');
    expect(request.headers['operationID'],
        matches(RegExp(r'^line-probe-[A-Za-z0-9_-]{1,69}$')));
    expect(request.headers['operationID'],
        isNot((await PublicHealthCheck.diagnosticHeaders())['operationID']));
  });

  test('retry jitter stays within existing bounded backoff', () {
    for (final seconds in [2, 3, 4, 6, 8, 12, 15, 30]) {
      final base = Duration(seconds: seconds);
      for (var i = 0; i < 100; i++) {
        final delay = PublicHealthCheck.retryDelay(base);
        expect(delay <= base, isTrue);
        expect(delay >= base - const Duration(milliseconds: 250), isTrue);
      }
    }
  });
}
