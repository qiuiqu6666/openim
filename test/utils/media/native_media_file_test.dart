import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/media/native_media_file.dart';
import 'package:openim_common/src/widgets/chat/voice/voice_playback_source.dart';

List<int> container(String brand) =>
    [0, 0, 0, 24, ...ascii.encode('ftyp$brand'), ...List.filled(12, 0)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('ios-media-file-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  tearDownAll(() async {
    await DefaultCacheManager().emptyCache();
    await DefaultCacheManager().dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  for (final fixture in [
    ('m4a', container('M4A ')),
    ('mp4', container('isom')),
    ('mov', container('qt  ')),
    ('mp3', [0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0]),
    ('aac', [0xff, 0xf1, 0x50, 0x80]),
    ('wav', [...ascii.encode('RIFF'), 24, 0, 0, 0, ...ascii.encode('WAVE')]),
  ]) {
    test('iOS repairs a cached .bin containing ${fixture.$1}, preserving bytes',
        () async {
      final source = await File('${directory.path}/${fixture.$1}.bin')
          .writeAsBytes(fixture.$2);
      final copies = await Future.wait([
        NativeMediaFile.prepare(source),
        NativeMediaFile.prepare(source),
      ]);
      expect(copies.first.path, endsWith('.${fixture.$1}'));
      expect(copies.last.path, copies.first.path);
      expect(await copies.first.readAsBytes(), fixture.$2);
      expect(await source.readAsBytes(), fixture.$2);
      expect((await NativeMediaFile.prepare(source)).path, copies.first.path);
    });
  }

  test('does not copy a correctly named recording or guess unknown data',
      () async {
    for (final fixture in [
      ('recording.m4a', container('M4A ')),
      ('error.bin', ascii.encode('<html>not media</html>')),
      ('empty.bin', <int>[]),
    ]) {
      final source = await File('${directory.path}/${fixture.$1}')
          .writeAsBytes(fixture.$2);
      expect((await NativeMediaFile.prepare(source)).path, source.path);
    }
  });

  test('does not reuse a copy when the source changes', () async {
    final source = await File('${directory.path}/changing.bin')
        .writeAsBytes(container('M4A '));
    final first = await NativeMediaFile.prepare(source);
    await source.writeAsBytes([...container('M4A '), 1]);
    final second = await NativeMediaFile.prepare(source);
    expect(second.path, isNot(first.path));
    expect(await second.readAsBytes(), [...container('M4A '), 1]);
  });

  test('Android keeps the existing playback path', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final source = await File('${directory.path}/android.bin')
        .writeAsBytes(container('M4A '));
    expect((await NativeMediaFile.prepare(source)).path, source.path);
  });

  test('voice source passes a playable M4A copy and unchanged signed fallback',
      () async {
    final source = await File('${directory.path}/download.bin')
        .writeAsBytes(container('M4A '));
    const url = 'https://cdn.test/audio?token=secret&signature=a%2Fb';
    final message = Message.fromJson({
      'soundElem': {'sourceUrl': url}
    });
    final loaded = await VoicePlaybackSource.load(message,
        imApiUrl: 'https://im.test', download: (_) async => source);
    expect(loaded.value, endsWith('.m4a'));
    expect(loaded.fallbackUrl, url);
    expect(await File(loaded.value).readAsBytes(), await source.readAsBytes());
  });
}
