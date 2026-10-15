import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/node_switch/node_endpoint.dart';
import 'package:openim/pages/mine/settings/node_switch/node_probe_controller.dart';

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final started = Completer<void>();
  Object body = {'service': 'chat-api', 'status': 'ok'};
  int code = 200;
  Completer<void>? gate;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (!started.isCompleted) started.complete();
    if (gate != null) await gate!.future;
    return ResponseBody.fromString(jsonEncode(body), code, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const endpoint = NodeEndpoint(
      chatApi: 'https://chat.example/',
      imApi: 'https://im.example',
      imWs: 'wss://im.example');
  late _Transport transport;
  late NodeProbeController controller;
  var current = endpoint;
  setUp(() {
    current = endpoint;
    transport = _Transport();
    controller = NodeProbeController(
        readEndpoint: () => current,
        clientFactory: () => Dio()..httpClientAdapter = transport);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
  });
  tearDown(() => controller.dispose());

  test('manual test probes only the direct route and refreshes its status',
      () async {
    final direct = _Transport()..gate = Completer<void>();
    final all = NodeProbeController(
        readEndpoint: () => NodeEndpoint.direct,
        clientFactory: () => Dio()..httpClientAdapter = direct);
    all.didChangeAppLifecycleState(AppLifecycleState.resumed);
    addTearDown(all.dispose);
    final work = all.test();
    expect(identical(work, all.test()), isTrue);
    await direct.started.future;
    await Future<void>.delayed(Duration.zero);
    expect(direct.requests.map((request) => request.uri.toString()),
        NodeEndpoint.builtIn.map((node) => '${node.chatApi}/healthz'));
    expect(all.pending,
        NodeEndpoint.builtIn.map((node) => node.signature).toSet());
    direct.gate!.complete();
    await work;
    expect(all.results[NodeEndpoint.direct.signature]?.status,
        NodeProbeStatus.normal);
    expect(all.pending, isEmpty);
    expect(all.testing, isFalse);
    expect(all.results, hasLength(3));
    expect(all.endpoint.signature, NodeEndpoint.direct.signature);
    expect(all.testedAt, isNotNull);
    direct.code = 503;
    await all.test();
    expect(direct.requests, hasLength(4));
    expect(all.results[NodeEndpoint.direct.signature]?.status,
        NodeProbeStatus.abnormal);
  });

  test('manual probe validates public response without account credentials',
      () async {
    expect(transport.requests, isEmpty);
    await controller.test();
    final request = transport.requests.single;
    expect(request.uri.toString(), 'https://chat.example/healthz');
    expect(request.method, 'GET');
    expect(request.headers['operationID'], isNotEmpty);
    expect(request.headers.keys.map((e) => e.toLowerCase()),
        isNot(contains('authorization')));
    expect(request.headers.keys.map((e) => e.toLowerCase()),
        isNot(contains('token')));
    expect(controller.status, NodeProbeStatus.normal);
    expect(controller.latencyMs, isNonNegative);
    expect(controller.testedAt, isNotNull);
    await controller.test();
    expect(transport.requests, hasLength(2));
  });
  test('HTTP errors and unsuccessful or malformed bodies stay abnormal',
      () async {
    transport.code = 401;
    await controller.test();
    expect(controller.status, NodeProbeStatus.abnormal);
    expect(controller.httpStatus, 401);
    transport.code = 200;
    for (final body in [
      {'errCode': 1, 'data': {}},
      {'errCode': 0, 'data': null}
    ]) {
      transport.body = body;
      await controller.test();
      expect(controller.status, NodeProbeStatus.abnormal);
      expect(controller.latencyMs, isNull);
    }
  });
  test('concurrent clicks share request and changed endpoints discard results',
      () async {
    transport.gate = Completer<void>();
    final first = controller.test();
    expect(identical(first, controller.test()), isTrue);
    await transport.started.future;
    current = const NodeEndpoint(
        chatApi: 'https://new.example',
        imApi: 'https://im.example',
        imWs: 'wss://im.example');
    transport.gate!.complete();
    await first;
    expect(transport.requests, hasLength(1));
    expect(controller.endpoint.chatApi, current.chatApi);
    expect(controller.status, NodeProbeStatus.unknown);
    expect(controller.testedAt, isNull);
  });
  test('background cancels probe and resume makes no automatic request',
      () async {
    transport.gate = Completer<void>();
    final work = controller.test();
    await transport.started.future;
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    transport.gate!.complete();
    await work;
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(controller.testing, isFalse);
    expect(controller.status, NodeProbeStatus.unknown);
    expect(transport.requests, hasLength(1));
  });

  test('network changes cancel old probes and never publish their result',
      () async {
    final network = StreamController<List<ConnectivityResult>>();
    final adapter = _Transport()..gate = Completer<void>();
    final owned = NodeProbeController(
      readEndpoint: () => endpoint,
      networkChanges: network.stream,
      clientFactory: () => Dio()..httpClientAdapter = adapter,
    );
    owned.didChangeAppLifecycleState(AppLifecycleState.resumed);
    addTearDown(owned.dispose);
    addTearDown(network.close);
    final work = owned.test();
    await adapter.started.future;
    network.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    await work;
    expect(owned.testing, isFalse);
    expect(owned.results, isEmpty);
    expect(owned.status, NodeProbeStatus.unknown);
    adapter.gate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(owned.testedAt, isNull);
    expect(adapter.requests, hasLength(1));
  });
}
