import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_message_builder.dart';
import 'package:openim/services/favorite_models.dart';

import 'support/favorite_test_fakes.dart';

void main() {
  late Directory directory;
  late FakeFavoriteFactory factory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('favorite-builder-test-');
    factory = FakeFavoriteFactory();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  FavoriteMessageBuilder builder(FakeFavoriteDownloader downloader) =>
      FavoriteMessageBuilder(
          messageFactory: factory,
          downloader: downloader,
          directoryProvider: () async => directory);

  test('audio/video use checked originals, ceil seconds and a real snapshot',
      () async {
    final audio =
        favoriteAsset('audio', [1, 2, 3], mime: 'audio/mp4', durationMs: 1501);
    final video =
        favoriteAsset('video', [4, 5], mime: 'video/mp4', durationMs: 12001);
    final cover = favoriteAsset('cover', [6, 7], role: 'cover');
    final downloader = FakeFavoriteDownloader({
      'audio': [1, 2, 3],
      'video': [4, 5],
      'cover': [6, 7]
    });
    final prepared = favoritePrepared(const [
      FavoriteBlock(id: 'a', type: 'audio', assetID: 'audio'),
      FavoriteBlock(
          id: 'v',
          type: 'video',
          assetID: 'video',
          data: {'snapshotAssetID': 'cover'})
    ], downloads: [
      favoriteGrant(audio),
      favoriteGrant(video),
      favoriteGrant(cover)
    ]);
    final messages = await builder(downloader).build(prepared,
        assets: [audio, video, cover],
        sendAttemptID: 'attempt',
        namespace: 'account');
    expect(messages.length, 2);
    expect(factory.calls[0]['duration'], 2);
    expect(factory.calls[1]['duration'], 13);
    expect(factory.calls[1]['mime'], 'video/mp4');
    expect(await File(factory.calls[1]['snapshot'] as String).readAsBytes(),
        [6, 7]);
    expect(factory.calls.map((value) => value['path']),
        everyElement(isNot(contains('https://'))));
    expect(
        messages.map((value) => value.message.clientMsgID), ['new-1', 'new-2']);
  });
  test('checksum mismatch deletes incomplete materials and creates no message',
      () async {
    final image = favoriteAsset('image', [1, 2, 3]);
    final downloader = FakeFavoriteDownloader({
      'image': [9, 9, 9]
    });
    await expectLater(
        builder(downloader).build(
            favoritePrepared(
                const [FavoriteBlock(id: 'i', type: 'image', assetID: 'image')],
                downloads: [favoriteGrant(image)]),
            assets: [image],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()
            .having((value) => value.code, 'code', 'MEDIA_INVALID')));
    expect(factory.calls, isEmpty);
    expect(
        await directory
            .list(recursive: true)
            .where((value) => value is File)
            .toList(),
        isEmpty);
  });
  test('video cannot silently send without its original and snapshot',
      () async {
    final video =
        favoriteAsset('video', [1, 2], mime: 'video/mp4', durationMs: 1000);
    await expectLater(
        builder(FakeFavoriteDownloader({
          'video': [1, 2]
        })).build(
            favoritePrepared(
                const [FavoriteBlock(id: 'v', type: 'video', assetID: 'video')],
                downloads: [favoriteGrant(video)]),
            assets: [video],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()
            .having((value) => value.code, 'code', 'ASSET_MISSING')));
    expect(factory.calls, isEmpty);
  });
  test(
      'unsupported mixed blocks fail the whole build instead of dropping content',
      () async {
    await expectLater(
        builder(FakeFavoriteDownloader({})).build(
            favoritePrepared(const [
              FavoriteBlock(id: 't', type: 'text', text: 'okay'),
              FavoriteBlock(
                  id: 'c', type: 'custom', data: {'action': 'transfer'})
            ]),
            assets: [],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()));
    expect(factory.calls, isEmpty);
  });
  test('file names cannot control the local destination', () async {
    final file = favoriteAsset('file', [1, 2],
        mime: 'application/pdf', fileName: '../../合同.pdf');
    final messages = await builder(FakeFavoriteDownloader({
      'file': [1, 2]
    })).build(
        favoritePrepared(
            const [FavoriteBlock(id: 'f', type: 'file', assetID: 'file')],
            downloads: [favoriteGrant(file)]),
        assets: [file],
        sendAttemptID: 'attempt');
    expect(factory.calls.single['fileName'], '合同.pdf');
    expect((factory.calls.single['path'] as String).startsWith(directory.path),
        isTrue);
    expect(messages.single.localPaths.length, 1);
  });
  test('expired preparation and unknown schemes never build or download',
      () async {
    final downloader = FakeFavoriteDownloader({});
    await expectLater(
        builder(downloader).build(
            favoritePrepared(
                const [FavoriteBlock(id: 't', type: 'text', text: 'hello')],
                expiry: DateTime.now().subtract(const Duration(seconds: 1))),
            assets: [],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()
            .having((value) => value.code, 'code', 'PREPARE_EXPIRED')));
    await expectLater(
        builder(downloader).build(
            favoritePrepared(const [
              FavoriteBlock(
                  id: 'l', type: 'link', data: {'url': 'javascript:alert(1)'})
            ]),
            assets: [],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()));
    expect(factory.calls, isEmpty);
    expect(downloader.downloaded, isEmpty);
  });

  test('streaming download aborts excess bytes before SDK creation', () async {
    final asset = favoriteAsset('image', [1, 2]);
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.headers.containsKey('token'), isFalse);
      expect(options.headers.containsKey('Authorization'), isFalse);
      handler.resolve(Response<ResponseBody>(
          requestOptions: options,
          statusCode: 200,
          data:
              ResponseBody(Stream.value(Uint8List.fromList([1, 2, 3])), 200)));
    }));
    final real = FavoriteMessageBuilder(
        messageFactory: factory,
        downloader: DioFavoriteMediaDownloader(dio: dio),
        directoryProvider: () async => directory);
    await expectLater(
        real.build(
            favoritePrepared(
                const [FavoriteBlock(id: 'i', type: 'image', assetID: 'image')],
                downloads: [favoriteGrant(asset)]),
            assets: [asset],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()
            .having((error) => error.code, 'code', 'MEDIA_TOO_LARGE')));
    expect(factory.calls, isEmpty);
    expect(
        await directory
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList(),
        isEmpty);
  });

  test('multiple videos require explicit per-block snapshot mapping', () async {
    final one = favoriteAsset('one', [1], mime: 'video/mp4', durationMs: 1000);
    final two = favoriteAsset('two', [2], mime: 'video/mp4', durationMs: 1000);
    final cover = favoriteAsset('cover', [3], role: 'thumbnail');
    await expectLater(
        builder(FakeFavoriteDownloader({
          'one': [1],
          'two': [2],
          'cover': [3]
        })).build(
            favoritePrepared(const [
              FavoriteBlock(id: '1', type: 'video', assetID: 'one'),
              FavoriteBlock(id: '2', type: 'video', assetID: 'two')
            ], downloads: [
              favoriteGrant(one),
              favoriteGrant(two),
              favoriteGrant(cover)
            ]),
            assets: [one, two, cover],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()));
    expect(factory.calls, isEmpty);
  });

  test('malformed nested content cannot be silently dropped', () async {
    await expectLater(
        builder(FakeFavoriteDownloader({})).build(
            favoritePrepared(const [
              FavoriteBlock(id: 'bundle', type: 'message', data: {
                'blocks': [
                  {'id': 't', 'type': 'text', 'text': 'valid'},
                  'malformed'
                ]
              })
            ]),
            assets: [],
            sendAttemptID: 'attempt'),
        throwsA(isA<FavoriteBuildException>()));
    expect(factory.calls, isEmpty);
  });
}
