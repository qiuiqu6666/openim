import 'dart:convert';
import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_message_adapter.dart';
import 'package:openim/services/favorite_message_builder.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

import '../../../support/favorite_test_fakes.dart';

void main() {
  late Directory directory;
  late FakeFavoriteFactory factory;
  late MemoryFavoriteTaskStore store;
  const target = FavoriteTarget(conversationID: 'c', userID: 'recipient');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('favorite-p0-contract-');
    factory = FakeFavoriteFactory();
    store = MemoryFavoriteTaskStore();
  });
  tearDown(() async => directory.delete(recursive: true));

  FavoriteMessageBuilder builder({FakeFavoriteDownloader? downloader}) =>
      FavoriteMessageBuilder(
          messageFactory: factory,
          downloader: downloader ?? FakeFavoriteDownloader({}),
          directoryProvider: () async => directory);
  FavoriteSendCoordinator coordinator(
          FakeFavoriteRepository repository, FavoriteSendCallback sender) =>
      FavoriteSendCoordinator(
          repository: repository,
          builder: builder(),
          taskStore: store,
          sender: sender,
          lookup: (message, _) async =>
              FavoriteSendResult.unknown(clientMsgID: message.clientMsgID));
  FavoriteSendResult accepted(Message message) => FavoriteSendResult.success(
      message: Message.fromJson(message.toJson())
        ..status = MessageStatus.succeeded);
  Message source() => Message(
      clientMsgID: 'source-message',
      seq: 101,
      status: MessageStatus.succeeded,
      contentType: MessageType.text,
      textElem: TextElem(content: 'body'));

  test('source locators require a positive sequence and exact identifiers', () {
    for (final seq in [null, 0, -1]) {
      final message = source()..seq = seq;
      expect(FavoriteMessageAdapter.canFavorite(message), isFalse);
      expect(
          () => FavoriteMessageAdapter.sourceForMessage(message,
              conversationID: 'si_a_b'),
          throwsFormatException);
    }
    for (final id in ['', ' ', ' si_a_b', 'si_a_b\n', 'si_a_b\x00']) {
      expect(
          () => FavoriteMessageAdapter.sourceForMessage(source(),
              conversationID: id),
          throwsFormatException);
      expect(FavoriteMessageAdapter.canFavorite(source()..clientMsgID = id),
          isFalse);
    }
    expect(
        FavoriteMessageAdapter.sourceForMessage(source(),
                conversationID: 'si_a_b')
            .toJson(),
        {
          'conversationID': 'si_a_b',
          'clientMsgID': 'source-message',
          'sequence': 101
        });
  });

  test('P0 never accepts location, contact or merged message protocols',
      () async {
    for (final type in [
      MessageType.location,
      MessageType.card,
      MessageType.merger
    ]) {
      expect(FavoriteMessageAdapter.canFavorite(source()..contentType = type),
          isFalse);
    }
    for (final type in ['location', 'contact', 'card', 'message', 'merger']) {
      await expectLater(
          builder().build(
              favoritePrepared([
                const FavoriteBlock(id: 'text', type: 'text', text: 'okay'),
                FavoriteBlock(id: 'unsupported', type: type, data: const {
                  'blocks': [
                    {'id': 'nested', 'type': 'text', 'text': 'must not flatten'}
                  ]
                })
              ]),
              assets: [],
              sendAttemptID: 'attempt'),
          throwsA(isA<FavoriteBuildException>()
              .having((error) => error.code, 'code', 'UNSUPPORTED_CONTENT')));
    }
    await expectLater(
        builder().build(
            favoritePrepared(
                const [FavoriteBlock(id: 'body', type: 'text', text: 'no')],
                kind: FavoriteKind.location),
            assets: [],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()));
    expect(factory.calls, isEmpty);
  });

  test('completed video block coverAssetID maps to a checked local snapshot',
      () async {
    final video =
        favoriteAsset('video', [1, 2], mime: 'video/mp4', durationMs: 1001);
    final cover = favoriteAsset('cover', [3, 4], role: 'cover');
    final messages = await builder(
        downloader: FakeFavoriteDownloader({
      'video': [1, 2],
      'cover': [3, 4]
    })).build(
        favoritePrepared(
            const [
              FavoriteBlock(id: 'v', type: 'video', assetID: 'video', data: {
                'coverAssetID': 'cover',
                'snapshotAssetID': 'stale-client-field'
              })
            ],
            kind: FavoriteKind.video,
            downloads: [favoriteGrant(video), favoriteGrant(cover)]),
        assets: [video, cover],
        sendAttemptID: 'attempt');
    expect(factory.calls.single['duration'], 2);
    expect(await File(factory.calls.single['snapshot'] as String).readAsBytes(),
        [3, 4]);
    expect(messages.single.localPaths.length, 2);
    expect(jsonEncode(messages.single.message.toJson()),
        isNot(contains('privateSignature')));
  });

  test('numeric 20063 renews only the request ID before re-preparing',
      () async {
    final repository =
        _ExpiredPrepareRepository(favoriteTextItem(), expireCount: 1);
    var sends = 0;
    final sender = coordinator(repository, (message, _) async {
      sends++;
      return accepted(message);
    });
    final result = await sender.send(repository.detail, target);
    expect(result.isSuccess, isTrue);
    expect(repository.prepareCalls, 2);
    expect(repository.attemptIDs.toSet(), {result.sendAttemptID});
    expect(repository.requestIDs.toSet().length, 2);
    expect(repository.expectedRevisions.toSet(), {'revision-1'});
    expect(sends, 1);
    expect(factory.count, 1);
    expect(jsonEncode(store.values), isNot(contains('privateSignature')));
  });

  test('an expired download grant is rejected before any HTTP or SDK work',
      () async {
    final image = favoriteAsset('image', [1, 2]);
    final grant = favoriteGrant(image);
    final expired = FavoriteDownload(
        assetID: grant.assetID,
        url: grant.url,
        sizeBytes: grant.sizeBytes,
        sha256: grant.sha256,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)));
    final downloader = FakeFavoriteDownloader({
      'image': [1, 2]
    });
    await expectLater(
        builder(downloader: downloader).build(
            favoritePrepared(
                const [FavoriteBlock(id: 'i', type: 'image', assetID: 'image')],
                kind: FavoriteKind.image,
                downloads: [expired]),
            assets: [image],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()
            .having((error) => error.code, 'code', 'PREPARE_EXPIRED')));
    expect(downloader.downloaded, isEmpty);
    expect(factory.calls, isEmpty);
  });

  test('repeated expiration is bounded and resumes the same logical attempt',
      () async {
    final repository =
        _ExpiredPrepareRepository(favoriteTextItem(), expireCount: 2);
    var sends = 0;
    final sender = coordinator(repository, (message, _) async {
      sends++;
      return accepted(message);
    });
    final failed = await sender.send(repository.detail, target);
    expect(failed.errorCode, '20063');
    expect(failed.retryable, isTrue);
    expect(repository.prepareCalls, 2);
    expect(sends, 0);
    expect(factory.count, 0);
    final result = await sender.send(repository.detail, target);
    expect(result.isSuccess, isTrue);
    expect(result.sendAttemptID, failed.sendAttemptID);
    expect(repository.attemptIDs.toSet(), {failed.sendAttemptID});
    expect(repository.requestIDs.toSet().length, 3);
    expect(sends, 1);
    expect(factory.count, 1);
  });

  test(
      'unavailable capabilities block a new send and a restored prepared retry',
      () async {
    final repository = FakeFavoriteRepository(favoriteTextItem())
      ..favoritesAvailable = false;
    var sends = 0;
    final sender = coordinator(repository, (message, _) async {
      sends++;
      return FavoriteSendResult.failed(
          clientMsgID: message.clientMsgID, retryable: true);
    });
    expect((await sender.send(repository.detail, target)).errorCode,
        'FAVORITES_UNAVAILABLE');
    expect(repository.prepareCalls, 0);
    expect(factory.count, 0);
    expect(sends, 0);
    repository.favoritesAvailable = true;
    final prepared = await sender.send(repository.detail, target);
    expect(sends, 1);
    repository.favoritesAvailable = false;
    final restored = coordinator(repository, (message, _) async {
      sends++;
      return accepted(message);
    });
    expect((await restored.retry(prepared.sendAttemptID!)).errorCode,
        'FAVORITES_UNAVAILABLE');
    expect(sends, 1);
    expect(factory.count, 1);
    repository.favoritesAvailable = true;
    expect((await restored.retry(prepared.sendAttemptID!)).isSuccess, isTrue);
    expect(sends, 2);
    expect(factory.count, 1);
  });

  test(
      'capabilities are checked between blocks without duplicating accepted content',
      () async {
    final repository = FakeFavoriteRepository(favoriteTextItem(blocks: const [
      FavoriteBlock(id: 'one', type: 'text', text: 'one'),
      FavoriteBlock(id: 'two', type: 'text', text: 'two')
    ]));
    final ids = <String>[];
    final sender = coordinator(repository, (message, _) async {
      ids.add(message.clientMsgID!);
      repository.favoritesAvailable = false;
      return accepted(message);
    });
    final partial = await sender.send(repository.detail, target);
    expect(partial.errorCode, 'FAVORITES_UNAVAILABLE');
    expect(partial.sentCount, 1);
    expect(ids, ['new-1']);
    repository.favoritesAvailable = true;
    expect((await sender.retry(partial.sendAttemptID!)).isSuccess, isTrue);
    expect(ids, ['new-1', 'new-2']);
    expect(factory.count, 2);
  });

  test('legacy location materials cannot bypass P0 by restoring a task',
      () async {
    final repository = FakeFavoriteRepository(favoriteTextItem());
    final sender = coordinator(
        repository,
        (message, _) async => FavoriteSendResult.failed(
            clientMsgID: message.clientMsgID, retryable: true));
    final failed = await sender.send(repository.detail, target);
    final saved = store.values[repository.accountNamespace]!.single;
    saved['kind'] = 'location';
    (saved['steps'] as List).single['message']['contentType'] =
        MessageType.location;
    var sends = 0;
    final restored = coordinator(repository, (message, _) async {
      sends++;
      return accepted(message);
    });
    expect((await restored.retry(failed.sendAttemptID!)).errorCode,
        'UNSUPPORTED_CONTENT');
    expect(sends, 0);
    expect(factory.count, 1);
  });
}

class _ExpiredPrepareRepository extends FakeFavoriteRepository {
  _ExpiredPrepareRepository(super.detail, {required this.expireCount});
  final int expireCount;
  final List<String> expectedRevisions = [];
  @override
  Future<FavoritePreparedSend> prepareForSend(String id,
      {required String expectedContentRevision,
      required String sendAttemptID,
      required String clientRequestID}) async {
    expectedRevisions.add(expectedContentRevision);
    final prepared = await super.prepareForSend(id,
        expectedContentRevision: expectedContentRevision,
        sendAttemptID: sendAttemptID,
        clientRequestID: clientRequestID);
    if (prepareCalls <= expireCount) {
      throw const FavoriteApiException(20063, 'PrepareExpired');
    }
    return prepared;
  }
}
