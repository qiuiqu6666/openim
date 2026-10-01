import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/video_media_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('full-screen video can reuse an existing cached file', () async {
    final cacheDir = Directory.systemTemp.createTempSync('chat-video-test-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => cacheDir.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
    });
    const url = 'https://example.test/cached-chat-video.mp4';
    final bytes = Uint8List.fromList([0, 0, 0, 8, 0x66, 0x74, 0x79, 0x70]);
    await DefaultCacheManager().putFile(url, bytes);
    final cached = await VideoMediaCache.cachedFile(url);
    expect(cached, isNotNull);
    expect(await cached!.readAsBytes(), bytes);
  });
}
