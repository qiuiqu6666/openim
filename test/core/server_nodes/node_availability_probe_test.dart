import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String? brokenPath;
  String? brokenHost;
  Object? healthBody;
  int statusCode = 200;
  Object? failure;
  Completer<void>? gate;
  bool closed = false;
  @override
  void close({bool force = false}) => closed = true;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    final body = options.uri.path == brokenPath &&
            (brokenHost == null || options.uri.host == brokenHost)
        ? {'errCode': 500, 'errMsg': 'Unavailable'}
        : options.uri.path.endsWith('/healthz')
            ? healthBody ??
                {
                  'service': options.uri.host.contains('99chatapi') ||
                          options.uri.port == 10008
                      ? 'chat-api'
                      : 'openim-api',
                  'status': 'ok',
                }
            : {
                'errCode': 1602,
                'errMsg': 'args err, need token, sendID, platformID'
              };
    return ResponseBody.fromString(jsonEncode(body), statusCode, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('header API probe does not substitute a gateway probe for SDK state',
      () async {
    final adapter = _Adapter();
    final result = await NodeAvailabilityProbe(
            clientFactory: () => Dio()..httpClientAdapter = adapter)
        .check(NodeEndpoint.direct, includeGateway: false);
    expect(result.available, isTrue);
    expect(adapter.requests.map((request) => request.uri.port).toSet(), {443});
  });
  test('probes every service with no login credentials or redirects', () async {
    final adapter = _Adapter();
    final result = await NodeAvailabilityProbe(
            clientFactory: () => Dio()..httpClientAdapter = adapter)
        .check(NodeEndpoint.direct);
    expect(result.available, isTrue);
    expect(adapter.requests, hasLength(3));
    expect(adapter.requests.map((request) => request.uri.port).toSet(), {443});
    for (final request in adapter.requests) {
      final headers = request.headers.keys.map((key) => key.toLowerCase());
      expect(headers, isNot(contains('token')));
      expect(headers, isNot(contains('authorization')));
      expect(headers, isNot(contains('cookie')));
      expect(request.headers['X-Client-Source'], 'line-probe');
      expect(request.headers['operationID'],
          matches(RegExp(r'^line-probe-[A-Za-z0-9_-]{1,69}$')));
      expect(request.queryParameters, isEmpty);
      expect(request.data, isNull);
      expect(request.method, 'GET');
      expect(request.followRedirects, isFalse);
    }
    expect(adapter.closed, isTrue);
  });
  for (final service in ['chat', 'imApi', 'imWs']) {
    test('one failed service rejects the complete route: $service', () async {
      final adapter = _Adapter()
        ..brokenPath = service == 'imWs' ? '' : '/healthz'
        ..brokenHost = service == 'chat'
            ? '99chatapi.99chat.vip'
            : service == 'imApi'
                ? '99imapi.99chat.vip'
                : null;
      final result = await NodeAvailabilityProbe(
              clientFactory: () => Dio()..httpClientAdapter = adapter)
          .check(NodeEndpoint.direct);
      expect(result.available, isFalse);
      expect(result.serviceFailures[service], 'StateError');
      expect(adapter.closed, isTrue);
    });
  }
  test('total timeout closes network work and returns an unavailable node',
      () async {
    final adapter = _Adapter()..gate = Completer<void>();
    final result = await NodeAvailabilityProbe(
            timeout: const Duration(milliseconds: 20),
            clientFactory: () => Dio()..httpClientAdapter = adapter)
        .check(NodeEndpoint.direct);
    expect(result.available, isFalse);
    expect(result.serviceFailures, {
      'chat': 'timeout',
      'imApi': 'timeout',
      'imWs': 'timeout',
    });
    expect(adapter.closed, isTrue);
    adapter.gate!.complete();
  });
  test('invalid endpoint is rejected before making requests', () async {
    final adapter = _Adapter();
    final result = await NodeAvailabilityProbe(
            clientFactory: () => Dio()..httpClientAdapter = adapter)
        .check(const NodeEndpoint(
            chatApi: 'https://user:secret@example.test',
            imApi: 'https://example.test',
            imWs: 'wss://example.test'));
    expect(result.available, isFalse);
    expect(adapter.requests, isEmpty);
  });

  test('same candidate shares work and cancellation closes its requests',
      () async {
    final adapter = _Adapter()..gate = Completer<void>();
    final probe = NodeAvailabilityProbe(
        clientFactory: () => Dio()..httpClientAdapter = adapter);
    final first = probe.check(NodeEndpoint.direct, includeGateway: false);
    expect(
        identical(
            first, probe.check(NodeEndpoint.direct, includeGateway: false)),
        isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    probe.cancel();
    expect((await first).available, isFalse);
    expect(adapter.closed, isTrue);
    adapter.gate!.complete();
  });

  test('each candidate probes its own API addresses, preserving base paths',
      () async {
    final adapters = <_Adapter>[];
    final probe = NodeAvailabilityProbe(clientFactory: () {
      final adapter = _Adapter();
      adapters.add(adapter);
      return Dio()..httpClientAdapter = adapter;
    });
    const candidate = NodeEndpoint(
      chatApi: 'https://99chatapi.example/chat-base/',
      imApi: 'https://openim.example/im-base/',
      imWs: 'wss://gateway.example',
    );
    expect((await probe.check(candidate, includeGateway: false)).available,
        isTrue);
    expect(adapters.single.requests.map((r) => r.uri.toString()).toSet(), {
      'https://99chatapi.example/chat-base/healthz',
      'https://openim.example/im-base/healthz',
    });
    expect(adapters.single.requests.map((r) => r.method).toSet(), {'GET'});
    expect(
        (await probe.check(NodeEndpoint.backup, includeGateway: false))
            .available,
        isTrue);
    expect(
        adapters.last.requests.map((r) => r.uri.port).toSet(), {10008, 10002});
  });

  for (final body in <Object>[
    {'errCode': 1001, 'errDlt': 'header must have token'},
    '<html>ok</html>',
    [],
    {'service': 'other-api', 'status': 'ok'},
    {'service': 'chat-api'},
    {'service': 'chat-api', 'status': 'OK'},
    {'service': 'chat-api', 'status': 'ok', 'errCode': 1001},
  ]) {
    test('business errors and malformed health are unavailable: $body',
        () async {
      final adapter = _Adapter()..healthBody = body;
      final result = await NodeAvailabilityProbe(
              clientFactory: () => Dio()..httpClientAdapter = adapter)
          .check(NodeEndpoint.direct, includeGateway: false);
      expect(result.available, isFalse);
      expect(adapter.requests.every((r) => r.uri.path == '/healthz'), isTrue);
    });
  }
  for (final status in [201, 204, 302, 404, 503]) {
    test('health requires exactly HTTP 200: $status', () async {
      final adapter = _Adapter()..statusCode = status;
      final result = await NodeAvailabilityProbe(
              clientFactory: () => Dio()..httpClientAdapter = adapter)
          .check(NodeEndpoint.direct, includeGateway: false);
      expect(result.available, isFalse);
      expect(adapter.requests.every((r) => !r.followRedirects), isTrue);
    });
  }

  test('TLS and transport errors do not fall back to business endpoints',
      () async {
    final adapter = _Adapter()
      ..failure = DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badCertificate);
    final result = await NodeAvailabilityProbe(
            clientFactory: () => Dio()..httpClientAdapter = adapter)
        .check(NodeEndpoint.direct, includeGateway: false);
    expect(result.available, isFalse);
    expect(adapter.requests.every((r) => r.uri.path == '/healthz'), isTrue);
  });
}
