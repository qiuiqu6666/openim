import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_api.dart';

const _requestID = '33b61b45-5816-48fd-972e-853f58a9bbcc';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> _note() => {
      'id': 'f1',
      'kind': 'note',
      'title': '',
      'summary': 'note',
      'version': 1,
      'status': 'ready',
      'contentRevision': 'r1',
      'coverAssetID': '',
      'content': {
        'blocks': [
          {'type': 'text', 'text': 'hello'}
        ]
      }
    };

void main() {
  test('unarchived production items have no immutable content revision yet',
      () {
    for (final status in ['pending_archive', 'archive_failed']) {
      final payload = {
        ..._note(),
        'kind': 'image',
        'provenance': 'serverVerified',
        'status': status,
        'schemaVersion': 1,
        'contentRevision': '',
        'summary': '',
        'content': null,
        'assets': [],
        'totalBytes': 0,
        'source': {
          'conversationID': 'si_a_b',
          'clientMsgID': 'm1',
          'displayName': 'sender',
          'sentAt': 1790878581409
        },
        'createdAt': 1791090210451,
        'updatedAt': 1791090211602
      };
      final item = FavoriteItem.fromJson(payload);
      expect(item.contentRevision, isNull);
      expect(item.content, isNull);
      expect(item.assets, isEmpty);
      expect(item.canSend, isFalse);
      expect(item.source!.clientMsgID, 'm1');
      expect(
          FavoritePage.fromJson({
            'items': [payload],
            'nextCursor': null,
            'syncAt': 1791090259575
          }).items.single.id,
          item.id);
      expect(
          FavoriteChangesPage.fromJson({
            'events': [
              {'operation': 'upsert', 'item': payload}
            ],
            'syncAt': 1791090259680
          }, limit: 100)
              .events
              .single
              .item!
              .contentRevision,
          isNull);
      expect(FavoriteItem.fromJson(item.toCacheJson()).contentRevision, isNull);
    }
    expect(() => FavoriteItem.fromJson({..._note(), 'contentRevision': 0}),
        throwsFormatException);
    expect(
        () => FavoritePreparedSend.fromJson({
              'prepareID': 'p1',
              'contentRevision': '',
              'expiresAt': 1900000000000,
              'sendContent': {
                'kind': 'note',
                'blocks': [
                  {'id': 'b1', 'type': 'text', 'text': 'note'}
                ]
              },
              'downloads': []
            }),
        throwsFormatException);
  });

  test('production upload completion accepts zero metadata and empty cover',
      () async {
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler
            .resolve(Response(requestOptions: options, statusCode: 200, data: {
          'errCode': 0,
          'data': {
            'assetID': 'a1',
            'coverAssetID': '',
            'durationMs': 0,
            'width': 0,
            'height': 0,
            'fileName': 'notes.txt',
            'mimeType': 'text/plain',
            'sizeBytes': 7,
            'sha256': _hash
          }
        }));
      }));
    final api = FavoriteApi(
        client: client,
        tokenProvider: () => 'chat-secret',
        baseUrl: 'https://chat.test');
    final asset = await api.completeUpload('u1', clientRequestID: _requestID);
    expect(asset.id, 'a1');
    expect(asset.coverAssetID, isNull);
    expect(asset.durationMs, 0);
    expect(asset.width, 0);
    expect(asset.height, 0);
    expect(asset.fileName, 'notes.txt');
  });

  test(
      'batch delete keeps version hints but never assumes empty replay success',
      () async {
    final body = <String, dynamic>{
      'items': [
        {'id': 'f1', 'result': 'versionConflict', 'version': 8}
      ]
    };
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'errCode': 0, 'data': body}));
      }));
    final api = FavoriteApi(
        client: client,
        tokenProvider: () => 'chat-secret',
        baseUrl: 'https://chat.test');
    final items = [FavoriteItem.fromJson(_note())];
    final result = await api.batchDelete(items, clientRequestID: _requestID);
    expect(result.conflicts.single.version, 8);
    expect(result.conflicts.single.currentItem, isNull);
    body['items'] = [];
    await expectLater(api.batchDelete(items, clientRequestID: _requestID),
        throwsFormatException);
    expect(
        FavoriteDeleteResult.fromJson(
            {'id': 'f1', 'result': 'alreadyDeleted', 'version': 0}).version,
        isNull);
    expect(
        () => FavoriteDeleteResult.fromJson(
            {'id': 'f1', 'result': 'versionConflict', 'version': '8'}),
        throwsFormatException);
  });

  test(
      'remote API rejects signed loopback media URLs without rewriting or exposing them',
      () async {
    var grantURL = 'http://localhost:10005/private-path?signature=do-not-log';
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        final grant = {
          'assetID': 'a1',
          'url': grantURL,
          'sha256': _hash,
          'sizeBytes': 7
        };
        final data = options.uri.path.endsWith('/uploads')
            ? {
                'uploadID': 'u1',
                'uploadURL': grantURL,
                'expiresAt': 1900000000000,
                'maxSizeBytes': 100
              }
            : options.uri.path.endsWith('/prepare-send')
                ? {
                    'prepareID': 'p1',
                    'contentRevision': 'r1',
                    'expiresAt': 1900000000000,
                    'sendContent': {
                      'kind': 'image',
                      'blocks': [
                        {'id': 'b1', 'type': 'image', 'assetID': 'a1'}
                      ]
                    },
                    'downloads': [grant]
                  }
                : {...grant, 'expiresAt': 1900000000000};
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'errCode': 0, 'data': data}));
      }));
    final api = FavoriteApi(
        client: client,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'chat-secret');
    final configurationError = throwsA(isA<FavoriteApiException>()
        .having((error) => error.code, 'safe configuration code',
            'MEDIA_ENDPOINT_UNREACHABLE')
        .having((error) => error.message, 'no signed path',
            isNot(contains('private-path')))
        .having((error) => error.message, 'no signature',
            isNot(contains('do-not-log')))
        .having((error) => error.message, 'no account token',
            isNot(contains('chat-secret'))));
    for (final host in ['localhost', '127.2.3.4', '[::1]']) {
      grantURL = 'http://$host:10005/private-path?signature=do-not-log';
      await expectLater(
          api.initializeUpload(
              fileName: 'image.png',
              mimeType: 'image/png',
              sizeBytes: 7,
              clientRequestID: _requestID),
          configurationError);
      await expectLater(api.assetAccess('f1', 'a1'), configurationError);
      await expectLater(
          api.prepareForSend('f1',
              expectedContentRevision: 'r1',
              sendAttemptID: _requestID,
              clientRequestID: _requestID),
          configurationError);
    }
    grantURL = 'https://public-storage.test/private-path?signature=do-not-log';
    expect(
        (await api.initializeUpload(
                fileName: 'image.png',
                mimeType: 'image/png',
                sizeBytes: 7,
                clientRequestID: _requestID))
            .uploadURL
            .toString(),
        grantURL);
    expect((await api.assetAccess('f1', 'a1')).url.toString(), grantURL);
    expect(
        (await api.prepareForSend('f1',
                expectedContentRevision: 'r1',
                sendAttemptID: _requestID,
                clientRequestID: _requestID))
            .downloads
            .single
            .url
            .toString(),
        grantURL);
    final local = FavoriteApi(
        client: client,
        baseUrl: 'http://localhost:10008',
        tokenProvider: () => 'local-token');
    grantURL = 'http://localhost:10005/private-path?signature=do-not-log';
    expect(
        (await local.initializeUpload(
                fileName: 'image.png',
                mimeType: 'image/png',
                sizeBytes: 7,
                clientRequestID: _requestID))
            .uploadURL
            .toString(),
        grantURL);
  });

  test(
      'all authored writes retain block IDs required by the deployed Go validator',
      () async {
    final requests = <RequestOptions>[];
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        requests.add(options);
        final body = options.data as Map;
        final blocks = body['content']['blocks'] as List;
        // favorite_write.go validates both Block.ID and Block.Type before saving.
        final invalid = blocks.any((block) =>
            block['id'] is! String ||
            (block['id'] as String).isEmpty ||
            block['type'] is! String ||
            (block['type'] as String).isEmpty);
        final response = _note()
          ..['kind'] = body['kind'] ?? 'note'
          ..['content'] = body['content'];
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: invalid
                ? {
                    'errCode': 1001,
                    'errMsg': 'ArgsError',
                    'errDlt': 'block is invalid',
                    'data': {}
                  }
                : {
                    'errCode': 0,
                    'data': {'item': response}
                  }));
      }));
    final api = FavoriteApi(
        client: client,
        tokenProvider: () => 'chat-secret',
        baseUrl: 'https://chat.test');
    for (final kind in [
      FavoriteKind.note,
      FavoriteKind.link,
      FavoriteKind.image,
      FavoriteKind.video,
      FavoriteKind.audio,
      FavoriteKind.file
    ]) {
      final block = FavoriteBlock(
          id: 'b1',
          type: kind == FavoriteKind.note ? 'text' : kind.wireName,
          text: kind == FavoriteKind.note ? 'note' : null,
          assetID: {
            FavoriteKind.image,
            FavoriteKind.video,
            FavoriteKind.audio,
            FavoriteKind.file
          }.contains(kind)
              ? 'a1'
              : null,
          data: kind == FavoriteKind.link
              ? {'url': 'https://example.test/'}
              : const {});
      final content = FavoriteContent(kind: kind, blocks: [block]);
      final request = FavoriteApi.newRequestID();
      await api.create(
          kind: kind,
          content: content,
          clientRequestID: request,
          assetIDs: block.assetID == null ? [] : ['a1']);
      await api.create(
          kind: kind,
          content: content,
          clientRequestID: request,
          assetIDs: block.assetID == null ? [] : ['a1']);
      expect(requests.last.data['content']['blocks'][0]['id'], 'b1');
      expect(requests[requests.length - 2].data, requests.last.data);
      expect(requests.last.data['content'], {
        'blocks': [block.toJson()]
      });
    }
    await api.update('f1',
        expectedVersion: 1,
        clientRequestID: FavoriteApi.newRequestID(),
        content: const FavoriteContent(
            kind: FavoriteKind.note,
            blocks: [FavoriteBlock(id: 'b1', type: 'text', text: 'edit')]));
    expect(requests.last.data['content']['blocks'][0]['id'], 'b1');
  });

  test(
      'legacy parsed no-ID blocks preserve the original retry body and surface 1001',
      () async {
    Map? submitted;
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        submitted = options.data as Map;
        handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'errCode': 1001,
              'errMsg': 'ArgsError',
              'errDlt': 'block is invalid',
              'data': {}
            }));
      }));
    final api = FavoriteApi(
        client: client,
        tokenProvider: () => 'chat-secret',
        baseUrl: 'https://chat.test');
    final old = FavoriteContent.fromJson({
      'blocks': [
        {'type': 'text', 'text': 'old draft'}
      ]
    }, kind: FavoriteKind.note);
    expect(old.blocks.single.hasWireID, isFalse);
    await expectLater(
        api.create(
            kind: FavoriteKind.note, content: old, clientRequestID: _requestID),
        throwsA(isA<FavoriteApiException>().having(
            (error) => error.code, 'same terminal business code', 1001)));
    expect(submitted!['content']['blocks'][0].containsKey('id'), isFalse);
    expect(submitted!['clientRequestID'], _requestID);
  });

  test(
      'production prepare grants inherit and are bounded by the top-level lease',
      () {
    Map<String, dynamic> prepared(List<Map<String, dynamic>> downloads) => {
          'prepareID': 'p1',
          'contentRevision': 'r1',
          'expiresAt': 1900000000000,
          'sendContent': {
            'kind': 'image',
            'blocks': [
              {'id': 'b1', 'type': 'image', 'assetID': 'a1'}
            ]
          },
          'downloads': downloads
        };
    Map<String, dynamic> grant({int? expiresAt}) => {
          'assetID': 'a1',
          'url': 'https://storage.test/signed',
          'sizeBytes': 7,
          'sha256': _hash,
          'mimeType': 'image/png',
          if (expiresAt != null) 'expiresAt': expiresAt
        };
    final inherited = FavoritePreparedSend.fromJson(prepared([grant()]));
    expect(inherited.downloads.single.expiresAt, inherited.expiresAt);
    final longer = FavoritePreparedSend.fromJson(
        prepared([grant(expiresAt: 1900000060000)]));
    expect(longer.downloads.single.expiresAt!.millisecondsSinceEpoch,
        1900000000000);
    final shorter = FavoritePreparedSend.fromJson(
        prepared([grant(expiresAt: 1899999940000)]));
    expect(shorter.downloads.single.expiresAt!.millisecondsSinceEpoch,
        1899999940000);
    expect(FavoriteDownload.fromJson(grant()).expiresAt, isNull);
  });
  test('empty optional asset IDs do not reject valid note and non-video assets',
      () {
    final item = FavoriteItem.fromJson(_note());
    expect(item.coverAssetID, isNull);
    expect(item.text, 'hello');
    final asset = FavoriteAsset.fromJson({
      'assetID': 'a1',
      'mimeType': 'image/png',
      'sizeBytes': 7,
      'sha256': _hash,
      'coverAssetID': '',
      'codec': ''
    });
    expect(asset.coverAssetID, isNull);
    expect(asset.codec, isNull);
    expect(() => FavoriteItem.fromJson({..._note(), 'coverAssetID': 1}),
        throwsFormatException);
    expect(
        () => FavoriteAsset.fromJson({
              'assetID': 'a1',
              'mimeType': 'image/png',
              'sizeBytes': 7,
              'sha256': _hash,
              'coverAssetID': 1
            }),
        throwsFormatException);
  });

  test(
      'nil downloads permit text preparation while missing media grants still fail',
      () {
    final body = {
      'prepareID': 'p1',
      'contentRevision': 'r1',
      'expiresAt': 1900000000000,
      'sendContent': {
        'kind': 'note',
        'blocks': [
          {'type': 'text', 'text': 'hello'}
        ]
      },
      'downloads': null
    };
    expect(FavoritePreparedSend.fromJson(body).downloads, isEmpty);
    expect(
        () => FavoritePreparedSend.fromJson({
              ...body,
              'sendContent': {
                'kind': 'image',
                'blocks': [
                  {'type': 'image', 'assetID': 'a1'}
                ]
              }
            }),
        throwsFormatException);
  });

  test(
      'declared original MIME survives upload initialization and is used for binary PUT',
      () async {
    final folder = await Directory.systemTemp.createTemp('favorite-mime-');
    final file = File('${folder.path}/image.png');
    await file.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      await file.delete();
      await folder.delete();
    });
    RequestOptions? uploaded;
    final business = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler
            .resolve(Response(requestOptions: options, statusCode: 200, data: {
          'errCode': 0,
          'data': {
            'uploadID': 'u1',
            'uploadURL': 'https://storage.test/signed',
            'expiresAt': 1900000000000,
            'maxSizeBytes': 100
          }
        }));
      }));
    final storage = Dio()
      ..interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) async {
        uploaded = options;
        final bytes = await (options.data as Stream<List<int>>)
            .expand((part) => part)
            .toList();
        expect(bytes, [1, 2, 3]);
        handler.resolve(Response(requestOptions: options, statusCode: 204));
      }));
    final api = FavoriteApi(
        client: business,
        uploadClient: storage,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'chat-secret');
    final session = await api.initializeUpload(
        fileName: 'image.png',
        mimeType: 'image/png',
        sizeBytes: 3,
        clientRequestID: _requestID);
    expect(session.contentType, 'image/png');
    await api.uploadFile(session, file);
    expect(uploaded!.contentType, 'image/png');
    expect(uploaded!.method, 'PUT');
    expect(uploaded!.headers.keys.any((key) => key.toLowerCase() == 'token'),
        isFalse);
  });

  test(
      'signed Content-Type casing is respected and bearer chat headers never go to storage',
      () async {
    final folder = await Directory.systemTemp.createTemp('favorite-header-');
    final file = File('${folder.path}/image.png');
    await file.writeAsBytes([1, 2, 3]);
    addTearDown(() async {
      await file.delete();
      await folder.delete();
    });
    var calls = 0;
    final storage = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        calls++;
        expect(options.contentType, 'image/png');
        handler.resolve(Response(requestOptions: options, statusCode: 204));
      }));
    final api =
        FavoriteApi(uploadClient: storage, tokenProvider: () => 'chat-secret');
    FavoriteUploadSession session(Map<String, String> headers) =>
        FavoriteUploadSession(
            uploadID: 'u1',
            uploadURL: Uri.parse('https://storage.test/signed'),
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
            maxSizeBytes: 100,
            contentType: 'application/octet-stream',
            headers: headers);
    await api.uploadFile(session({'Content-Type': 'image/png'}), file);
    await expectLater(
        api.uploadFile(session({'Authorization': 'Bearer chat-secret'}), file),
        throwsFormatException);
    await expectLater(
        api.uploadFile(session({'token': 'some-other-secret'}), file),
        throwsFormatException);
    expect(calls, 1);
  });
}
