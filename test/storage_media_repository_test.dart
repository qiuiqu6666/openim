import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/storage_media_repository.dart';

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
}

class _NoCacheManager extends Fake implements CacheManager {
  @override
  Future<FileInfo?> getFileFromCache(String key,
          {bool ignoreMemCache = false}) async =>
      null;

  @override
  Future<void> removeFile(String key) async {}
}
