import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_api.dart';

const requestID = '33b61b45-5816-48fd-972e-853f58a9bbcc';
Map<String, dynamic> _item() => {
      'id': 'f1',
      'kind': 'note',
      'title': 'note',
      'status': 'ready',
      'version': 1,
      'contentRevision': 'r1',
      'content': {
        'blocks': [
          {'id': 'b1', 'type': 'text', 'text': 'hello'}
        ]
      }
    };

void main() {
  test(
      'confirmed void deletes accept null or missing data without inventing read DTOs',
      () async {
    var explicitNull = true;
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {'errCode': 0, if (explicitNull) 'data': null}))));
    final api = FavoriteApi(
        client: client,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'token');
    await api.delete('f1', expectedVersion: 1, clientRequestID: requestID);
    explicitNull = false;
    await api.delete('f1', expectedVersion: 1, clientRequestID: requestID);
    await expectLater(api.getDetail('f1'), throwsFormatException);
  });
  test('P0 rejects tag writes and queries without calling unopened routes',
      () async {
    final requests = <RequestOptions>[];
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options);
        handler
            .resolve(Response(requestOptions: options, statusCode: 200, data: {
          'errCode': 0,
          'data': options.method == 'GET'
              ? {'items': [], 'nextCursor': null}
              : {'item': _item()}
        }));
      }));
    final api = FavoriteApi(
        client: client,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'token');
    await expectLater(
        api.list(tagID: 't1'), throwsA(isA<FavoriteApiException>()));
    await expectLater(
        api.update('f1',
            expectedVersion: 3, clientRequestID: requestID, tagIDs: ['t1']),
        throwsA(isA<FavoriteApiException>()));
    await expectLater(api.createTag('标签', clientRequestID: requestID),
        throwsA(isA<FavoriteApiException>()));
    expect(requests, isEmpty);
  });
  test(
      'business token and stable request ID, fresh operation IDs, source hints removed',
      () async {
    final requests = <RequestOptions>[];
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options);
        handler
            .resolve(Response(requestOptions: options, statusCode: 200, data: {
          'errCode': 0,
          'data': {'item': _item()}
        }));
      }));
    final api = FavoriteApi(
        client: client,
        baseUrl: 'https://chat.test/',
        tokenProvider: () => 'chat-secret');
    for (var i = 0; i < 2; i++) {
      await api.createFromMessage(
          source: const FavoriteSource(
              conversationID: 'c1',
              clientMsgID: 'm1',
              sequence: 101,
              displayName: 'untrusted'),
          clientRequestID: requestID);
    }
    expect(requests.first.uri.toString(), 'https://chat.test/chat/favorites');
    expect(requests.first.headers['token'], 'chat-secret');
    expect(requests.first.headers['operationID'],
        isNot(requests.last.headers['operationID']));
    expect(requests.first.data['clientRequestID'],
        requests.last.data['clientRequestID']);
    expect(requests.first.data['source'].containsKey('displayName'), isFalse);
    expect(requests.first.data.containsKey('ownerUserID'), isFalse);
  });
  test('untrusted server errors are not exposed in exceptions', () async {
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
                  Response(requestOptions: options, statusCode: 200, data: {
                'errCode': 123,
                'errMsg': 'chat-secret https://private.test/token',
                'errDlt': 'private body',
                'data': {}
              }))));
    final api = FavoriteApi(
        client: client,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'chat-secret');
    await expectLater(
        api.list(),
        throwsA(isA<FavoriteApiException>().having((error) => error.toString(),
            'sanitized', isNot(contains('chat-secret')))));
  });
  test('a repeated page cursor and mismatched prepared revision are rejected',
      () async {
    var prepare = false;
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
                  Response(requestOptions: options, statusCode: 200, data: {
                'errCode': 0,
                'data': prepare
                    ? {
                        'prepareID': 'p1',
                        'contentRevision': 'other',
                        'expiresAt': 1700000000000,
                        'sendContent': {'kind': 'note', 'blocks': []},
                        'downloads': []
                      }
                    : {'items': [], 'nextCursor': 'same', 'syncAt': 100}
              }))));
    final api = FavoriteApi(
        client: client,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'token');
    await expectLater(
        api.list(cursor: 'same', baseline: 100), throwsFormatException);
    prepare = true;
    await expectLater(
        api.prepareForSend('f1',
            expectedContentRevision: 'r1',
            sendAttemptID: requestID,
            clientRequestID: requestID),
        throwsFormatException);
  });
  test(
      'signed upload uses a separate client and streams original bytes without Chat token',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('favorite-upload-test-');
    final file = File('${directory.path}/original.bin');
    await file.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() async {
      await file.delete();
      await directory.delete();
    });
    RequestOptions? uploaded;
    List<int>? bytes;
    final uploadClient = Dio()
      ..interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) async {
        uploaded = options;
        bytes = await (options.data as Stream<List<int>>)
            .expand((part) => part)
            .toList();
        handler.resolve(Response(requestOptions: options, statusCode: 200));
      }));
    final api = FavoriteApi(
        client: Dio(),
        uploadClient: uploadClient,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'chat-secret');
    await api.uploadFile(
        FavoriteUploadSession(
            uploadID: 'u1',
            uploadURL: Uri.parse('https://storage.test/signed'),
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
            maxSizeBytes: 100),
        file);
    expect(bytes, [1, 2, 3, 4]);
    expect(uploaded!.method, 'PUT');
    expect(uploaded!.headers.containsKey('token'), isFalse);
    expect(uploaded!.headers.containsKey('operationID'), isFalse);
  });
}
