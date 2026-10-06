import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_api.dart';

const requestID = '33b61b45-5816-48fd-972e-853f58a9bbcc';
const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> item({String id = 'f1', int version = 1}) => {
      'id': id,
      'kind': 'note',
      'title': null,
      'summary': 'saved',
      'status': 'archive_failed',
      'version': version,
      'contentRevision': 'r1',
      'coverAssetID': 'cover1',
      'createdAt': 100,
      'updatedAt': 200,
      'schemaVersion': 1,
      'totalBytes': 7,
      'provenance': 'userCreated',
      'content': {
        'blocks': [
          {'type': 'text', 'text': 'body'}
        ]
      }
    };

void main() {
  late List<RequestOptions> requests;
  late FavoriteApi api;
  late Map<String, dynamic> envelope;
  setUp(() {
    requests = [];
    envelope = {'errCode': 0, 'data': {}};
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options);
        handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: envelope));
      }));
    api = FavoriteApi(
        client: dio,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'chat-token');
  });

  test('quota requires actual booleans and both capabilities', () async {
    envelope['data'] = {
      'supportsFavorites': true,
      'supportsPrepareSend': false
    };
    expect((await api.getQuota()).available, isFalse);
    expect(requests.single.path, 'https://chat.test/chat/favorites/quota');
    expect(requests.single.headers['token'], 'chat-token');
    envelope['data'] = {
      'supportsFavorites': true,
      'supportsPrepareSend': 'true'
    };
    await expectLater(api.getQuota(), throwsFormatException);
    envelope['data'] = {'supportsFavorites': true};
    await expectLater(api.getQuota(), throwsFormatException);
  });

  test(
      'detail uses data.item, preserves failed status and supports id-free blocks',
      () async {
    envelope['data'] = {'item': item()};
    final detail = await api.getDetail('f1');
    expect(detail.status, FavoriteStatus.failed);
    expect(detail.status.wireName, 'archive_failed');
    expect(detail.coverAssetID, 'cover1');
    expect(detail.totalBytes, 7);
    expect(detail.blocks.single.id, 'block_0');
    expect(detail.blocks.single.toJson().containsKey('id'), isFalse);
    envelope['data'] = item();
    await expectLater(api.getDetail('f1'), throwsFormatException);
    for (final kind in [
      FavoriteKind.location,
      FavoriteKind.contact,
      FavoriteKind.messageBundle
    ]) {
      expect(
          FavoriteItem(
                  id: 'old',
                  kind: kind,
                  title: '',
                  version: 1,
                  status: FavoriteStatus.ready)
              .canSend,
          isFalse);
    }
  });

  test(
      '20051 source duplicate is successful with the existing authenticated item',
      () async {
    envelope = {
      'errCode': 20051,
      'errMsg': 'FavoriteAlreadyExists',
      'data': {'item': item()}
    };
    final existing = await api.createFromMessage(
        source: const FavoriteSource(
            conversationID: 'c',
            clientMsgID: 'm',
            sequence: 101,
            serverMsgID: 'untrusted',
            displayName: 'hint'),
        clientRequestID: requestID);
    expect(existing.id, 'f1');
    expect(requests.single.data['source'],
        {'conversationID': 'c', 'clientMsgID': 'm', 'sequence': 101});
    expect(requests.single.data.containsKey('tagIDs'), isFalse);
    envelope['data'] = {};
    await expectLater(
        api.createFromMessage(
            source: const FavoriteSource(
                conversationID: 'c', clientMsgID: 'm', sequence: 101),
            clientRequestID: requestID),
        throwsFormatException);
  });

  test('source must carry seq and clientMsgID before any request', () async {
    await expectLater(
        api.createFromMessage(
            source: const FavoriteSource(
                conversationID: 'c', serverMsgID: 'server-only'),
            clientRequestID: requestID),
        throwsArgumentError);
    await expectLater(
        api.createFromMessage(
            source: const FavoriteSource(
                conversationID: 'c', clientMsgID: 'm', sequence: 0),
            clientRequestID: requestID),
        throwsArgumentError);
    expect(requests, isEmpty);
  });

  test(
      'numeric conflict carries current item and never exposes private server details',
      () async {
    envelope = {
      'errCode': 20061,
      'errMsg': 'VersionConflict',
      'errDlt': 'chat-token https://private.test/signed',
      'data': {'item': item(version: 9)}
    };
    await expectLater(
        api.update('f1',
            expectedVersion: 3, clientRequestID: requestID, title: 'my draft'),
        throwsA(isA<FavoriteApiException>()
            .having((e) => e.code, 'numeric code', 20061)
            .having((e) => e.currentItem?.version, 'current record', 9)
            .having((e) => e.message, 'safe message',
                isNot(contains('chat-token')))));
    envelope = {'errCode': 20063, 'errMsg': 'PrepareExpired', 'data': {}};
    await expectLater(
        api.prepareForSend('f1',
            expectedContentRevision: 'r1',
            sendAttemptID: requestID,
            clientRequestID: requestID),
        throwsA(isA<FavoriteApiException>()
            .having((e) => e.code, 'expiry code', 20063)));
  });

  test('list echoes exact initial baseline and enforces 64 characters',
      () async {
    envelope['data'] = {
      'items': [item()],
      'nextCursor': 'next',
      'syncAt': 567
    };
    expect((await api.list()).syncAt, 567);
    expect(requests.single.queryParameters.containsKey('baseline'), isFalse);
    envelope['data'] = {'items': [], 'nextCursor': null, 'syncAt': 567};
    await api.list(cursor: 'next', baseline: 567);
    expect(requests.last.queryParameters['baseline'], 567);
    envelope['data'] = {'items': [], 'nextCursor': null, 'syncAt': 568};
    await expectLater(
        api.list(cursor: 'next', baseline: 567), throwsFormatException);
    await expectLater(
        api.list(query: List.filled(65, '字').join()), throwsArgumentError);
  });

  test(
      'delta pages use updatedAfter and accept a full same-millisecond group above limit',
      () async {
    envelope['data'] = {
      'events': [
        {'operation': 'upsert', 'item': item()},
        {'operation': 'delete', 'id': 'f2', 'version': 2, 'updatedAt': 200},
        {'id': 'f3', 'version': 3, 'updatedAt': 200},
      ],
      'syncAt': 200
    };
    final page = await api.changes(updatedAfter: 100, limit: 2);
    expect(page.events, hasLength(3));
    expect(page.hasMore, isTrue);
    expect(requests.single.queryParameters, {'updatedAfter': 100, 'limit': 2});
    envelope['data'] = {'events': [], 'syncAt': 450};
    final end = await api.changes(updatedAfter: page.syncAt, limit: 2);
    expect(end.hasMore, isFalse);
    expect(end.syncAt, 450);
  });

  test(
      'asset access binds the requested asset and retains expiry; completed video retains cover',
      () async {
    envelope['data'] = {
      'url': 'https://storage.test/signed',
      'sha256': hash,
      'sizeBytes': 7,
      'expiresAt': 123456
    };
    final access = await api.assetAccess('f1', 'a1');
    expect(access.assetID, 'a1');
    expect(access.expiresAt!.millisecondsSinceEpoch, 123456);
    envelope['data']['assetID'] = 'another';
    await expectLater(api.assetAccess('f1', 'a1'), throwsFormatException);
    envelope['data'] = {
      'assetID': 'a1',
      'mimeType': 'video/mp4',
      'sizeBytes': 7,
      'sha256': hash,
      'durationMs': 1500,
      'coverAssetID': 'cover1'
    };
    final asset = await api.completeUpload('u1', clientRequestID: requestID);
    expect(asset.coverAssetID, 'cover1');
    expect(asset.durationMs, 1500);
  });

  test('self-created P0 note has no tagIDs and unsupported kinds do not send',
      () async {
    envelope['data'] = {'item': item()};
    await api.create(
        kind: FavoriteKind.note,
        content: const FavoriteContent(
            kind: FavoriteKind.note,
            blocks: [FavoriteBlock(id: 'b1', type: 'text', text: 'note')]),
        clientRequestID: requestID);
    expect(requests.single.data.containsKey('tagIDs'), isFalse);
    expect(requests.single.data['content']['blocks'], [
      {'id': 'b1', 'type': 'text', 'text': 'note'}
    ]);
    await expectLater(
        api.create(
            kind: FavoriteKind.contact,
            content:
                const FavoriteContent(kind: FavoriteKind.contact, blocks: []),
            clientRequestID: requestID),
        throwsArgumentError);
    expect(requests, hasLength(1));
  });

  test(
      'batch delete is one request with immutable per-item versions and conflicts',
      () async {
    envelope['data'] = {
      'items': [
        {'id': 'f1', 'result': 'deleted', 'version': 4},
        {'id': 'f2', 'result': 'versionConflict', 'version': 8}
      ]
    };
    final result = await api.batchDelete([
      FavoriteItem.fromJson(item(version: 3)),
      FavoriteItem.fromJson(item(id: 'f2', version: 4))
    ], clientRequestID: requestID);
    expect(requests.single.uri.path, '/chat/favorites/batch-delete');
    expect(requests.single.data['items'], [
      {'id': 'f1', 'expectedVersion': 3},
      {'id': 'f2', 'expectedVersion': 4}
    ]);
    expect(result.items.first.deleted, isTrue);
    expect(result.items.first.version, 4);
    expect(result.conflicts.single.currentVersion, 8);
    expect(result.conflicts.single.currentItem, isNull);
  });
}
