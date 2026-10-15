import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/youmeng/shield_readiness.dart';

class _ShieldAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final gate = Completer<void>();
  int? brokenPort;
  bool closed = false;

  @override
  void close({bool force = false}) => closed = true;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await gate.future;
    final port = options.uri.port;
    final body = port == brokenPort
        ? {'errCode': 500}
        : port == 10008
            ? {'service': 'chat-api', 'status': 'ok'}
            : port == 10002
                ? {'service': 'openim-api', 'status': 'ok'}
                : {'errCode': 1602, 'errMsg': 'args err, need token'};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold tunnel remains pending past the old 3-second deadline', () async {
    final adapter = _ShieldAdapter();
    var completed = false;
    final ready = ShieldReadiness.verify(
      probe: NodeAvailabilityProbe(
        timeout: ShieldReadiness.timeout,
        clientFactory: () => Dio()..httpClientAdapter = adapter,
      ),
    ).then((_) => completed = true);
    await Future<void>.delayed(const Duration(milliseconds: 3150));
    expect(completed, isFalse);
    expect(adapter.closed, isFalse);
    expect(
        adapter.requests.map((r) => r.uri.port).toSet(), {10008, 10002, 10001});
    adapter.gate.complete();
    await ready;
    expect(completed, isTrue);
    expect(adapter.closed, isTrue);
  });

  for (final port in [10008, 10002, 10001]) {
    test('listener/HELLO readiness cannot bypass failed business port $port',
        () async {
      final adapter = _ShieldAdapter()..brokenPort = port;
      adapter.gate.complete();
      await expectLater(
          ShieldReadiness.verify(
            probe: NodeAvailabilityProbe(
              clientFactory: () => Dio()..httpClientAdapter = adapter,
            ),
          ),
          throwsStateError);
      expect(adapter.closed, isTrue);
    });
  }

  test('hung tunnel validation still expires and closes all probes', () async {
    final adapter = _ShieldAdapter();
    await expectLater(
        ShieldReadiness.verify(
          probe: NodeAvailabilityProbe(
            timeout: const Duration(milliseconds: 30),
            clientFactory: () => Dio()..httpClientAdapter = adapter,
          ),
        ),
        throwsStateError);
    expect(adapter.closed, isTrue);
    adapter.gate.complete();
  });
}
