import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/cloud/search_http_client.dart';

void main() {
  test('global transport reuses socket with request-scoped credentials',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ports = <int>[];
    final tokens = <String?>[];
    final subscription = server.listen((request) async {
      ports.add(request.connectionInfo!.remotePort);
      tokens.add(request.headers.value('token'));
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'errCode': 0,
        'data': {'ok': true}
      }));
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    for (final token in ['first-account', 'second-account']) {
      final client = SearchHttpClient(
        paced: false,
        reuseConnections: true,
        session: () => (
          user: token,
          token: token,
          server: 'http://127.0.0.1:${server.port}'
        ),
      );
      expect((await client.request('/search', {}))['ok'], isTrue);
    }
    expect(ports.toSet(), hasLength(1));
    expect(tokens, ['first-account', 'second-account']);
  });

  test('real HTTP transport cancels an outstanding request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    final subscription = server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/old') {
        received.complete();
        return; // Deliberately never respond: cancellation must release the client.
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'errCode': 0,
        'data': {'fresh': true}
      }));
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final client = SearchHttpClient(
      paced: false,
      reuseConnections: true,
      session: () => (
        user: 'self',
        token: 'im',
        server: 'http://127.0.0.1:${server.port}'
      ),
    );
    final cancel = CancelToken();
    final old = client.request('/old', {}, cancelToken: cancel);
    final cancelled = expectLater(old, throwsA(isA<DioException>()));
    await received.future.timeout(const Duration(seconds: 2));
    cancel.cancel();
    await cancelled.timeout(const Duration(seconds: 1));
    final fresh =
        await client.request('/new', {}).timeout(const Duration(seconds: 2));
    expect(fresh['fresh'], isTrue);
  });

  test('cancelled in-flight search releases queue before old response',
      () async {
    final old = Completer<dynamic>();
    final started = Completer<void>();
    final cancel = CancelToken();
    final watch = Stopwatch()..start();
    final starts = <int>[];
    final client = SearchHttpClient(
      paced: true,
      session: () =>
          (user: 'self', token: 'im', server: 'https://example.test'),
      post: (_, body, __) async {
        starts.add(watch.elapsedMilliseconds);
        if (body['query'] == 'old') {
          started.complete();
          return old.future;
        }
        return {'errCode': 0, 'data': <String, dynamic>{}};
      },
    );
    final first =
        client.request('/search', {'query': 'old'}, cancelToken: cancel);
    final cancelled = expectLater(first, throwsA(isA<DioException>()));
    await started.future;
    cancel.cancel();
    await client.request(
        '/search', {'query': 'new'}).timeout(const Duration(seconds: 3));
    await cancelled;
    expect(old.isCompleted, isFalse);
    expect(starts.last - starts.first, greaterThanOrEqualTo(1000));
    expect(starts.last - starts.first, lessThan(2500));
    debugPrint(
        'New search started after ${starts.last - starts.first}ms; old request still unresolved');
    old.complete({'errCode': 0, 'data': <String, dynamic>{}});
  });

  test('search clients share one paced queue and skip stale queued work',
      () async {
    final times = <DateTime>[];
    final first = Completer<dynamic>();
    final firstStarted = Completer<void>();
    var active = true;
    SearchHttpClient client() => SearchHttpClient(
        paced: true,
        session: () =>
            (user: 'self', token: 'im', server: 'https://example.test'),
        post: (_, __, ___) async {
          times.add(DateTime.now());
          if (times.length == 1) {
            firstStarted.complete();
            return first.future;
          }
          return {'errCode': 0, 'data': <String, dynamic>{}};
        });
    final a = client().request('/msg/search_messages', {});
    final b = client().request('/msg/search_message_context', {});
    final c = client()
        .request('/msg/search_messages_global', {}, isCurrent: () => active);
    final cancelled = expectLater(c, throwsA(isA<SearchApiException>()));
    await firstStarted.future;
    expect(times.length, 1);
    active = false;
    first.complete({'errCode': 0, 'data': <String, dynamic>{}});
    await Future.wait([a, b]);
    await cancelled;
    expect(times.length, 2);
    expect(times[1].difference(times[0]).inMilliseconds,
        greaterThanOrEqualTo(1000));
  });
}
