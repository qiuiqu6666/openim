import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_api.dart';

class _Transport implements HttpClientAdapter {
  _Transport(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions, Future<void>?) handler;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return await handler(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
  AiAssistantApi api({String? Function()? tokenProvider}) {
    final client =
        Dio(BaseOptions(headers: {'Authorization': 'Bearer reference-jwt'}));
    client.httpClientAdapter = this;
    return AiAssistantApi(
        dio: client,
        baseUrl: 'https://current.test',
        tokenProvider: tokenProvider ?? () => 'chat-token',
        userProvider: () => 'openim-user');
  }
}

ResponseBody _json(Object body, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
ResponseBody _events(String body) =>
    ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['text/event-stream']
    });
Matcher _code(String code) =>
    throwsA(isA<AiAssistantException>().having((e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'uses OpenIM business identity, exact reference route and bounded cursor',
      () async {
    final transport = _Transport((_, __) => _json({
          'errCode': 0,
          'data': {'items': [], 'hasMore': false, 'nextCursor': null}
        }));
    final page = await transport.api().history(limit: 1000, cursor: ' c1 ');
    expect(page.items, isEmpty);
    final request = transport.requests.single;
    expect(request.uri.origin, 'https://current.test');
    expect(request.uri.path, '/ai-assistant/api/v1/chat/history');
    expect(request.queryParameters, {'limit': 100, 'cursor': 'c1'});
    expect(request.headers['token'], 'chat-token');
    expect(request.headers['Authorization'], isNull);
    expect(request.headers['operationID'], isNotEmpty);
    expect(request.followRedirects, isFalse);
  });
  test(
      'missing service, malformed history and expired identity do not become empty history',
      () async {
    final missing = _Transport((_, __) => _json({}, status: 404));
    await expectLater(missing.api().history(), _code('SERVICE_UNAVAILABLE'));
    final malformed = _Transport((_, __) => _json({'errCode': 0, 'data': {}}));
    await expectLater(malformed.api().history(), _code('INVALID_RESPONSE'));
    final expired =
        _Transport((_, __) => _json({'errCode': 1506, 'errMsg': 'expired'}));
    await expectLater(expired.api().history(), _code('UNAUTHORIZED'));
    final absent = _Transport((_, __) => _json({}));
    await expectLater(
        absent.api(tokenProvider: () => '').history(), _code('UNAUTHORIZED'));
    expect(absent.requests, isEmpty);
  });
  test('late business response is fenced after an account token changes',
      () async {
    final gate = Completer<ResponseBody>();
    var token = 'old-chat-token';
    final transport = _Transport((_, __) => gate.future);
    final pending = transport.api(tokenProvider: () => token).history();
    await Future<void>.delayed(Duration.zero);
    final expectation = expectLater(pending, _code('SESSION_CHANGED'));
    token = 'new-chat-token';
    gate.complete(_json({'items': [], 'hasMore': false}));
    await expectation;
  });
  test('multipart upload validates size/type and decodes a real file identity',
      () async {
    final transport = _Transport((_, __) => _json({
          'code': 0,
          'data': {
            'fileId': 'file#1',
            'fileName': 'chart.png',
            'contentType': 'image/png',
            'sizeBytes': 8
          }
        }));
    final api = transport.api();
    final result = await api.uploadFile(
        fileName: 'chart.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]));
    expect(result.fileId, 'file#1');
    final multipart = transport.requests.single.data as FormData;
    expect(multipart.files.single.key, 'file');
    expect(multipart.files.single.value.contentType.toString(), 'image/png');
    await expectLater(
        api.uploadFile(fileName: 'program.exe', bytes: Uint8List.fromList([1])),
        _code('INVALID_INPUT'));
    await expectLater(
        api.uploadFile(
            fileName: 'large.png', bytes: Uint8List(20 * 1024 * 1024 + 1)),
        _code('FILE_TOO_LARGE'));
    expect(transport.requests, hasLength(1));
  });
  test('stream preserves deltas and requires a server terminal event',
      () async {
    final transport = _Transport((_, __) => _events(
        'event: meta\ndata: {"userMessageId":"u","assistantMessageId":"a"}\n\n'
        'event: delta\ndata: {"text":"  answer "}\n\n'
        'event: done\ndata: {"assistantMessageId":"a","sourceMessageCount":12}\n\n'));
    final events = await transport
        .api()
        .streamChat(
            capability: 'summarize',
            content: '总结',
            analyze: const AiAssistantAnalyze.group('group#1'))
        .toList();
    expect(events.map((e) => e.kind), [
      AiAssistantStreamKind.meta,
      AiAssistantStreamKind.delta,
      AiAssistantStreamKind.done
    ]);
    expect(events[1].text, '  answer ');
    expect(events.last.sourceMessageCount, 12);
    expect(transport.requests.single.data, {
      'content': '总结',
      'capability': 'summarize',
      'analyze': {'type': 'group', 'groupId': 'group#1'}
    });
    final incomplete = _Transport(
        (_, __) => _events('event: delta\ndata: {"text":"partial"}\n\n'));
    await expectLater(incomplete.api().streamChat(content: 'question').toList(),
        _code('INCOMPLETE_STREAM'));
  });
  test('cancelling a subscriber closes a quiet underlying response', () async {
    final opened = Completer<void>();
    final released = Completer<void>();
    final source = StreamController<Uint8List>(
      onListen: () => opened.complete(),
      onCancel: () => released.complete(),
    );
    final cancelled = Completer<void>();
    var responseClosed = false;
    final transport = _Transport((_, cancel) {
      cancel?.then((_) {
        if (!cancelled.isCompleted) cancelled.complete();
      });
      return ResponseBody(source.stream, 200,
          onClose: () => responseClosed = true,
          headers: {
            Headers.contentTypeHeader: ['text/event-stream']
          });
    });
    var events = 0;
    final subscription =
        transport.api().streamChat(content: 'question').listen((_) => events++);
    // Exercise cancellation of an established quiet response, not a request
    // that may still be waiting for Dio's asynchronous interceptor pipeline.
    await opened.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();
    await cancelled.future.timeout(const Duration(seconds: 2));
    await released.future.timeout(const Duration(seconds: 2));
    expect(responseClosed, isTrue);
    expect(source.hasListener, isFalse);
    expect(events, 0);
    await source.close();
  });
  test('file downloads always use the configured origin with encoded identity',
      () async {
    final transport =
        _Transport((_, __) => ResponseBody.fromBytes([137, 80, 78, 71], 200,
            headers: {
              Headers.contentTypeHeader: ['image/png']
            }));
    final id = AiAssistantApi.fileIdFromUrl(
        'https://foreign.test/ai-assistant/api/v1/chat/files/file%231?token=ignored');
    expect(id, 'file#1');
    expect(await transport.api().downloadFile(id!), [137, 80, 78, 71]);
    expect(transport.requests.single.uri.toString(),
        'https://current.test/ai-assistant/api/v1/chat/files/file%231');
  });
}
