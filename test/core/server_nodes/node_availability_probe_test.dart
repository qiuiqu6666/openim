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
  Completer<void>? gate;
  bool closed = false;
  @override
  void close({bool force = false}) => closed = true;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (gate != null) await gate!.future;
    final body = options.uri.path == brokenPath
        ? {'errCode': 500, 'errMsg': 'Unavailable'}
        : options.uri.path.endsWith('/chat/platform')
            ? {'errCode': 0, 'data': <String, dynamic>{}}
            : options.uri.path.endsWith('/user/get_users_info')
                ? {
                    'errCode': 1001,
                    'errMsg': 'ArgsError',
                    'errDlt': 'header must have token'
                  }
                : {
                    'errCode': 1602,
                    'errMsg': 'args err, need token, sendID, platformID'
                  };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('probes every service with no login credentials or redirects', () async {
    final adapter = _Adapter();
    final result = await NodeAvailabilityProbe(
            clientFactory: () => Dio()..httpClientAdapter = adapter)
        .check(NodeEndpoint.direct);
    expect(result.available, isTrue);
    expect(adapter.requests, hasLength(3));
    expect(adapter.requests.map((request) => request.uri.port).toSet(),
        {10008, 10002, 10001});
    for (final request in adapter.requests) {
      final headers = request.headers.keys.map((key) => key.toLowerCase());
      expect(headers, isNot(contains('token')));
      expect(headers, isNot(contains('authorization')));
      expect(request.followRedirects, isFalse);
    }
    expect(adapter.closed, isTrue);
  });
  for (final brokenPath in ['/chat/platform', '/user/get_users_info', '']) {
    test('one failed service rejects the complete route: $brokenPath',
        () async {
      final adapter = _Adapter()..brokenPath = brokenPath;
      final result = await NodeAvailabilityProbe(
              clientFactory: () => Dio()..httpClientAdapter = adapter)
          .check(NodeEndpoint.direct);
      expect(result.available, isFalse);
      expect(adapter.closed, isTrue);
    });
  }
  test('total timeout closes network work and returns an unavailable node',
      () async {
    final adapter = _Adapter()..gate = Completer<void>();
    final result = await NodeAvailabilityProbe(
            timeout: const Duration(milliseconds: 20),
            clientFactory: () => Dio()..httpClientAdapter = adapter)
        .check(NodeEndpoint.primary);
    expect(result.available, isFalse);
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
}
