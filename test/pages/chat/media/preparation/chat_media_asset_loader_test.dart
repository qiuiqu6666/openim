import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/preparation/chat_media_asset_loader.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class _Asset extends AssetEntity {
  const _Asset(this.exported, this.original, {this.onOriginalRead})
      : super(id: 'asset', typeInt: 1, width: 10, height: 10);
  final Future<File?> exported, original;
  final void Function()? onOriginalRead;

  @override
  Future<File?> get file => exported;
  @override
  Future<File?> get originFile {
    onOriginalRead?.call();
    return original;
  }
}

void main() {
  late Directory directory;
  late File photo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('asset-loader-');
    photo = await File('${directory.path}/photo.jpg').writeAsBytes([1, 2, 3]);
  });
  tearDown(() => directory.delete(recursive: true));

  for (final failure in ['null', 'missing', 'empty', 'error', 'timeout']) {
    test('gallery export $failure falls back to the original resource',
        () async {
      final stalled = Completer<File?>();
      final exported = switch (failure) {
        'null' => Future<File?>.value(),
        'missing' => Future.value(File('${directory.path}/missing.jpg')),
        'empty' => File('${directory.path}/empty.jpg').writeAsBytes([]),
        'error' => Future<File?>.error(StateError('Export unavailable')),
        _ => stalled.future,
      };
      var originalReads = 0;
      final asset = _Asset(exported, Future.value(photo),
          onOriginalRead: () => originalReads++);
      expect(
          await loadChatMediaAsset(asset,
              timeout: const Duration(milliseconds: 20),
              isCancelled: () => false),
          photo);
      expect(originalReads, 1);
      if (failure == 'timeout') stalled.complete(photo);
    });
  }

  test('available export does not request the original file', () async {
    var originalReads = 0;
    final asset = _Asset(Future.value(photo), Future.value(null),
        onOriginalRead: () => originalReads++);
    expect(
        await loadChatMediaAsset(asset,
            timeout: const Duration(seconds: 1), isCancelled: () => false),
        photo);
    expect(originalReads, 0);
  });

  test('account change during export prevents original fallback', () async {
    var cancelled = false;
    final export = Completer<File?>();
    var originalReads = 0;
    final asset = _Asset(export.future, Future.value(photo),
        onOriginalRead: () => originalReads++);
    final pending = loadChatMediaAsset(asset,
        timeout: const Duration(seconds: 1), isCancelled: () => cancelled);
    cancelled = true;
    export.complete(null);
    expect(await pending, isNull);
    expect(originalReads, 0);
  });
  test('late export is discarded while original fallback remains stalled',
      () async {
    final export = Completer<File?>();
    final original = Completer<File?>();
    final stages = <String>[];
    final asset = _Asset(export.future, original.future,
        onOriginalRead: () => export.complete(photo));
    try {
      await expectLater(
          loadChatMediaAsset(asset,
              timeout: const Duration(milliseconds: 20),
              isCancelled: () => false,
              onReadFailure: (stage, _) => stages.add(stage)),
          throwsStateError);
      expect(await export.future, photo);
      expect(stages, ['asset_export', 'asset_original']);
    } finally {
      original.complete(photo);
    }
  });

}
