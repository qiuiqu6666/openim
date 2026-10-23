import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/startup/startup_route_probe.dart';
import 'package:openim/core/server_nodes/startup/startup_state.dart';

class Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final replies = <String, Completer<ResponseBody>>{};
  bool closed = false;
  final started = Completer<void>();
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    requests.add(options);
    final reply = Completer<ResponseBody>();
    replies[options.uri.host] = reply;
    if (replies.length == 3) started.complete();
    return reply.future;
  }

  void reply(String host, Object body, {int status = 200}) => replies[host]!
          .complete(ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      }));
  @override
  void close({bool force = false}) {
    closed = true;
  }
}

const node = NodeEndpoint(
    chatApi: 'https://chat.test',
    imApi: 'https://im.test',
    imWs: 'wss://ws.test');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: ''));

  test(
      'both APIs release before gateway; success remains per-service and credential-free',
      () async {
    final adapter = Adapter();
    final probe = StartupRouteProbe(
        clientFactory: () => Dio()..httpClientAdapter = adapter);
    final updates = <StartupHealth>[];
    final apiReady = Completer<void>();
    final work = probe.check(node, 7, (value) {
      updates.add(value);
      if (value.apiReady && !apiReady.isCompleted) apiReady.complete();
    });
    await adapter.started.future;
    expect(adapter.requests.length, 3);
    adapter.reply('chat.test', {'status': 'ok', 'service': 'chat-api'});
    adapter.reply('im.test', {'status': 'ok', 'service': 'openim-api'});
    await apiReady.future;
    expect(updates.last.apiReady, isTrue);
    expect(updates.last.fullyHealthy, isFalse);
    expect(updates.last.services['imWs'], 'pending');
    expect(updates.last.generation, 7);
    adapter.reply('ws.test', {'errCode': 1602, 'errMsg': 'need token'});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await work;
    expect(updates.last.fullyHealthy, isTrue);
    expect(adapter.closed, isTrue);
    for (final request in adapter.requests) {
      expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(anyOf(contains('token'), contains('authorization'),
              contains('cookie'))));
      expect(request.queryParameters, isEmpty);
    }
  });

  test('HTTP 200 with wrong service or HTML never claims healthy', () async {
    final adapter = Adapter();
    final probe = StartupRouteProbe(
        clientFactory: () => Dio()..httpClientAdapter = adapter);
    final updates = <StartupHealth>[];
    final work = probe.check(node, 2, updates.add);
    await adapter.started.future;
    adapter.reply('chat.test', {'status': 'ok', 'service': 'wrong'});
    adapter.reply(
        'im.test', {'status': 'ok', 'service': 'openim-api', 'errCode': 500});
    adapter.reply('ws.test', '<html>proxy</html>');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await work;
    expect(updates.every((u) => !u.apiReady && !u.fullyHealthy), isTrue);
    expect(updates.last.services.values.every((v) => v != 'ok'), isTrue);
  });

  test('gateway failure does not abort successful API requests', () async {
    final adapter = Adapter();
    final probe = StartupRouteProbe(
        clientFactory: () => Dio()..httpClientAdapter = adapter);
    final updates = <StartupHealth>[];
    final work = probe.check(node, 3, updates.add);
    await adapter.started.future;
    adapter.reply('ws.test', {}, status: 503);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    adapter.reply('chat.test', {'status': 'ok', 'service': 'chat-api'});
    adapter.reply('im.test', {'status': 'ok', 'service': 'openim-api'});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await work;
    expect(updates.last.apiReady, isTrue);
    expect(updates.last.fullyHealthy, isFalse);
  });

  test('cancel closes clients and suppresses all late observations', () async {
    final adapter = Adapter();
    final probe = StartupRouteProbe(
        clientFactory: () => Dio()..httpClientAdapter = adapter);
    final updates = <StartupHealth>[];
    final work = probe.check(node, 3, updates.add);
    await adapter.started.future;
    probe.cancel();
    expect(adapter.closed, isTrue);
    adapter.reply('chat.test', {'status': 'ok', 'service': 'chat-api'});
    adapter.reply('im.test', {'status': 'ok', 'service': 'openim-api'});
    adapter.reply('ws.test', {'errCode': 1602, 'errMsg': 'need token'});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await work;
    expect(updates, isEmpty);
  });
}
