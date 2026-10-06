import 'dart:io';

// FileInfo fixtures use the file implementation already owned by cache_manager.
// ignore: depend_on_referenced_packages
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/storage_media_repository.dart';
import 'package:openim_common/openim_common.dart' show Config, OpenIMMediaUrl;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('storage cleanup touches only app-owned copies and keeps messages',
      () async {
    final sandbox =
        await Directory.systemTemp.createTemp('storage-cleaner-test-');
    try {
      final owned = await Directory('${sandbox.path}/cache').create();
      final outside =
          await File('${sandbox.path}/original.jpg').writeAsBytes([1, 2]);
      final cached =
          await File('${owned.path}/copy.jpg').writeAsBytes([1, 2, 3]);
      final repository = StorageMediaRepository(
          cacheManager: _NoCacheManager(), ownedRoots: [owned]);
      final conversation = SearchResultItems()
        ..conversationID = 'c1'
        ..showName = 'Test';
      final message = Message(
        clientMsgID: 'm1',
        contentType: MessageType.picture,
        pictureElem: PictureElem(sourcePath: outside.path),
      );

      expect(await repository.resolve(message, conversation), isNull);
      message.pictureElem!.sourcePath = cached.path;
      expect(await repository.resolve(message, conversation), isNull,
          reason: 'local-only attachments must not be offered for deletion');
      message.pictureElem!.sourcePicture =
          PictureInfo(url: 'https://example.com/copy.jpg');
      final item = await repository.resolve(message, conversation);
      expect(item, isNotNull);
      expect(item!.bytes, 3);

      await repository.removeLocalFiles([item]);
      expect(await cached.exists(), isFalse);
      expect(await outside.exists(), isTrue);
      expect(message.clientMsgID, 'm1');
    } finally {
      await sandbox.delete(recursive: true);
    }
  });

  test('loopback messages find and clean the public cache key once', () async {
    final sandbox =
        await Directory.systemTemp.createTemp('storage-public-key-test-');
    try {
      final owned = await Directory('${sandbox.path}/cache').create();
      final cached =
          await File('${owned.path}/report.png').writeAsBytes([1, 2, 3, 4]);
      const originalURL =
          'http://127.0.0.1:10002/object/sangong/report.png?height=960&width=960&type=image';
      final publicURL =
          OpenIMMediaUrl.resolve(originalURL, imApiUrl: Config.imApiUrl);
      expect(publicURL, isNot(originalURL));
      final cache = _PublicKeyCacheManager(
        publicURL,
        FileInfo(const LocalFileSystem().file(cached.path), FileSource.Cache,
            DateTime(2099), publicURL),
      );
      final repository =
          StorageMediaRepository(cacheManager: cache, ownedRoots: [owned]);
      final conversation = SearchResultItems()
        ..conversationID = 'c1'
        ..showName = 'Test';
      final message = Message(
        clientMsgID: 'public-cache-message',
        contentType: MessageType.picture,
        pictureElem: PictureElem(
          sourcePicture: PictureInfo(url: originalURL),
          bigPicture: PictureInfo(url: originalURL),
          snapshotPicture: PictureInfo(url: originalURL),
        ),
      );

      final item = await repository.resolve(message, conversation);

      expect(item, isNotNull);
      expect(item!.cachedURLs, [publicURL]);
      expect(item.localPaths, [cached.path]);
      expect(item.previewPath, cached.path);
      expect(item.bytes, 4,
          reason: 'source, big and snapshot refer to the same cached file');
      expect(cache.requestedKeys.toSet(), {originalURL, publicURL});

      await repository.removeLocalFiles([item, item]);

      expect(cache.removedKeys, [publicURL]);
      expect(await cached.exists(), isFalse);
      expect(identical(item.message, message), isTrue);
      expect(message.pictureElem!.sourcePicture!.url, originalURL);
      expect(message.pictureElem!.bigPicture!.url, originalURL);
      expect(message.pictureElem!.snapshotPicture!.url, originalURL);
      expect(message.clientMsgID, 'public-cache-message');
    } finally {
      await sandbox.delete(recursive: true);
    }
  });
}

class _NoCacheManager extends Fake implements CacheManager {
  @override
  Future<FileInfo?> getFileFromCache(String key,
          {bool ignoreMemCache = false}) async =>
      null;

  @override
  Future<void> removeFile(String key) async {}
}

class _PublicKeyCacheManager extends Fake implements CacheManager {
  _PublicKeyCacheManager(this.publicKey, this.info);
  final String publicKey;
  final FileInfo info;
  final requestedKeys = <String>[];
  final removedKeys = <String>[];

  @override
  Future<FileInfo?> getFileFromCache(String key,
      {bool ignoreMemCache = false}) async {
    requestedKeys.add(key);
    return key == publicKey ? info : null;
  }

  @override
  Future<void> removeFile(String key) async {
    removedKeys.add(key);
  }
}
