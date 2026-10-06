import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/customer_service/data/data.dart';

void main() {
  const config = CustomerServiceConfig(
      baseUrl: 'https://support.example/kefu', inboxIdentifier: 'inbox /');
  late Dio dio;
  late CustomerServiceApi api;
  late _Adapter adapter;

  setUp(() {
    dio = Dio();
    adapter = _Adapter();
    dio.httpClientAdapter = adapter;
    api = CustomerServiceApi(client: dio, config: config);
  });
  tearDown(() {
    api.dispose();
    dio.close(force: true);
  });

  test('uses the approved deployment and permits explicit configuration', () {
    const defaults = CustomerServiceConfig();
    expect(defaults.normalizedBaseUrl, 'http://129.226.192.93:8815');
    expect(defaults.inboxIdentifier, 'JucC6gvPuKjfzZxLtT5ftaiQ');
    expect(defaults.cableUri.toString(), 'ws://129.226.192.93:8815/cable');
    expect(config.cableUri.toString(), 'wss://support.example/kefu/cable');
  });

  test('contact and conversation requests preserve /kefu and public contract',
      () async {
    adapter.responses.addAll([
      {'source_id': 'visitor /1', 'pubsub_token': 'room-token'},
      {'id': 42},
    ]);
    final contact = await api.createContact(
        identifier: 'device-uuid',
        name: 'Current user',
        avatarUrl: 'https://cdn.example/avatar.png');
    final conversation = await api.createConversation(contact.sourceId);
    expect(conversation, '42');
    expect(adapter.requests[0].uri.toString(),
        'https://support.example/kefu/public/api/v1/inboxes/inbox%20%2F/contacts');
    expect(adapter.requests[0].data, {
      'name': 'Current user',
      'identifier': 'device-uuid',
      'avatar_url': 'https://cdn.example/avatar.png',
    });
    expect(adapter.requests[1].uri.toString(),
        'https://support.example/kefu/public/api/v1/inboxes/inbox%20%2F/contacts/visitor%20%2F1/conversations');
    expect(adapter.requests[1].data, isEmpty);
    expect(
        adapter.requests
            .expand((request) => request.headers.keys)
            .map((key) => key.toLowerCase()),
        isNot(contains(anyOf('token', 'authorization'))));
  });

  test('rejects private or signed avatars without leaking URL credentials',
      () async {
    for (final avatar in [
      'file:///avatar.png',
      'https://user:password@cdn.example/avatar.png',
      'https://cdn.example/avatar.png?token=account-secret',
      'http://127.0.0.1/avatar.png',
      'http://192.168.1.2/avatar.png',
    ]) {
      adapter.responses.add({'source_id': 's', 'pubsub_token': 'p'});
      await api.createContact(identifier: 'i', name: 'n', avatarUrl: avatar);
      expect(adapter.requests.last.data, isNot(contains('avatar_url')));
    }
  });

  test('parses wrapped history, sender types, attachment URLs and timestamps',
      () async {
    adapter.responses.add({
      'payload': [
        {
          'id': 9,
          'content': 'Reply',
          'message_type': 'incoming',
          'sender': {'type': 'agent'},
          'echo_id': 'echo',
          'conversation_id': 42,
          'created_at': 1700000000,
          'attachments': [
            {
              'file_type': 2,
              'data_url': '/kefu/uploads/movie.mp4',
              'thumb_url': '/uploads/cover.jpg',
              'file_name': 'movie.mp4',
              'width': '1920',
              'height': 1080,
            },
          ],
        },
      ],
    });
    final rows = await api.listMessages(contactId: 's', conversationId: '42');
    final message = rows.single;
    expect(message.messageType, 1);
    expect(message.conversationId, '42');
    expect(message.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
    expect(message.attachments.single.fileType, 'video');
    expect(message.attachments.single.dataUrl,
        'https://support.example/kefu/uploads/movie.mp4');
    expect(message.attachments.single.thumbUrl,
        'https://support.example/kefu/uploads/cover.jpg');
    expect(message.attachments.single.width, 1920);
  });

  test('sends exact echo IDs and multipart attachment fields', () async {
    adapter.responses.addAll([
      {
        'id': 1,
        'content': 'Question',
        'message_type': 0,
        'echo_id': 'text-echo'
      },
      {'id': 2, 'content': '', 'message_type': 0, 'echo_id': 'file-echo'},
    ]);
    final text = await api.sendText(
        contactId: 's',
        conversationId: 'c',
        content: 'Question',
        echoId: 'text-echo');
    expect(text.echoId, 'text-echo');
    expect(adapter.requests.first.data,
        {'content': 'Question', 'echo_id': 'text-echo'});
    await api.sendAttachment(
        contactId: 's',
        conversationId: 'c',
        echoId: 'file-echo',
        filename: 'photo.png',
        path: '',
        bytes: [1, 2, 3],
        width: 20,
        height: 30,
        thumbnailBytes: [4, 5]);
    final form = adapter.requests.last.data as FormData;
    expect(Map.fromEntries(form.fields), {
      'content': '',
      'echo_id': 'file-echo',
      'width': '20',
      'height': '30',
    });
    expect(form.files.map((file) => file.key), ['attachments[]', 'thumbnail']);
    expect(form.files.first.value.contentType.toString(), 'image/png');
  });

  test('rejects oversized attachments before transport reads bytes', () async {
    await expectLater(
        api.sendAttachment(
            contactId: 's',
            conversationId: 'c',
            echoId: 'echo',
            filename: 'large.mp4',
            path: '',
            bytes: _LargeBytes()),
        throwsArgumentError);
    expect(adapter.requests, isEmpty);
  });

  test('a send response without a message ID is rejected', () async {
    adapter.responses.add({'content': 'Question', 'echo_id': 'echo'});
    await expectLater(
        api.sendText(
            contactId: 's',
            conversationId: 'c',
            content: 'Question',
            echoId: 'echo'),
        throwsStateError);
    expect(adapter.requests, hasLength(1));
  });

  test('invalid history and missing contact IDs are actionable failures',
      () async {
    adapter.responses.addAll([
      {'data': 'broken'},
      {'source_id': 's'}
    ]);
    await expectLater(api.listMessages(contactId: 's', conversationId: 'c'),
        throwsFormatException);
    await expectLater(
        api.createContact(identifier: 'i', name: 'n'), throwsStateError);
  });

  test('disposed API rejects later requests without closing injected clients',
      () async {
    api.dispose();
    expect(adapter.closed, isFalse);
    await expectLater(api.listMessages(contactId: 's', conversationId: 'c'),
        throwsStateError);
    expect(adapter.requests, isEmpty);
  });

  test('disposing cancels an in-flight request without resetting any session',
      () async {
    adapter.pending = Completer<ResponseBody>();
    adapter.started = Completer<void>();
    final request = api.listMessages(contactId: 's', conversationId: 'c');
    final assertion = expectLater(
        request,
        throwsA(isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)));
    await adapter.started!.future;
    expect(adapter.requests, hasLength(1));
    api.dispose();
    await assertion;
    expect(adapter.closed, isFalse);
    adapter.pending!.complete(ResponseBody.fromString('[]', 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    }));
  });
}

class _Adapter implements HttpClientAdapter {
  final responses = <dynamic>[];
  final requests = <RequestOptions>[];
  bool closed = false;
  Completer<ResponseBody>? pending;
  Completer<void>? started;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (started?.isCompleted == false) started!.complete();
    if (pending != null) return pending!.future;
    return ResponseBody.fromString(jsonEncode(responses.removeAt(0)), 200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) => closed = true;
}

class _LargeBytes extends ListBase<int> {
  @override
  int get length => CustomerServiceApi.maxAttachmentBytes + 1;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  int operator [](int index) =>
      throw StateError('Must not read oversized data');
  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}
