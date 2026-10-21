import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:openim/pages/chat/media/preparation/chat_media_asset_loader.dart';

void main() {
  late Directory dir;
  late File video;
  const asset =
      AssetEntity(id: 'video-test', typeInt: 2, width: 10, height: 10);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('video-download-');
    video = await File('${dir.path}/video.mp4').writeAsBytes([1, 2, 3]);
  });
  tearDown(() => dir.delete(recursive: true));
  test('progress extends inactivity but not total deadline', () async {
    var calls = 0;
    final result = await loadChatMediaAsset(asset,
        timeout: const Duration(milliseconds: 10),
        isCancelled: () => false,
        videoIdleTimeout: const Duration(milliseconds: 60),
        videoTotalTimeout: const Duration(seconds: 2),
        videoReader: (_, progress) async {
          calls++;
          for (var i = 1; i <= 5; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            progress(i / 5);
          }
          return video;
        });
    expect(result, video);
    expect(calls, 1);
  });
  test('retry observes late native result without a second export', () async {
    var calls = 0;
    final native = Completer<File?>();
    Future<File?> reader(bool _, void Function(double) progress) {
      calls++;
      return native.future;
    }

    await expectLater(
        loadChatMediaAsset(asset,
            timeout: const Duration(milliseconds: 10),
            isCancelled: () => false,
            videoIdleTimeout: const Duration(milliseconds: 20),
            videoReader: reader),
        throwsA(isA<TimeoutException>()));
    final retry = loadChatMediaAsset(asset,
        timeout: const Duration(milliseconds: 10),
        isCancelled: () => false,
        videoReader: reader);
    native.complete(video);
    expect(await retry, video);
    expect(calls, 1);
  });
  test('definitive export failure safely falls back to original', () async {
    final origins = <bool>[];
    expect(
        await loadChatMediaAsset(asset,
            timeout: const Duration(milliseconds: 10),
            isCancelled: () => false,
            videoReader: (origin, _) async {
              origins.add(origin);
              return origin ? video : null;
            }),
        video);
    expect(origins, [false, true]);
  });
}
