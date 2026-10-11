import 'dart:async';
import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/voice/voice_playback_source.dart';

void main() {
  late Directory directory;
  late File audio;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('voice-source-');
    audio = await File('${directory.path}/voice.m4a').writeAsBytes([1, 2, 3]);
  });
  tearDown(() async {
    await audio.delete();
    await directory.delete();
  });

  Message message({String? path, String? url}) => Message.fromJson({
        'clientMsgID': 'voice',
        'soundElem': {'soundPath': path, 'sourceUrl': url, 'duration': 2}
      });

  test('plays existing recording without a network request', () async {
    final source = await VoicePlaybackSource.load(message(path: audio.path),
        download: (_) => throw StateError('No download expected'));
    expect(source.isFile, isTrue);
    expect(source.value, audio.path);
  });

  test('missing local file downloads corrected OpenIM URL before playback',
      () async {
    final urls = <String>[];
    final source = await VoicePlaybackSource.load(
        message(
            path: '${directory.path}/missing.m4a',
            url: 'http://127.0.0.1:10002/object/user/voice.m4a'),
        imApiUrl: 'https://im.example.com', download: (url) async {
      urls.add(url);
      return audio;
    });
    expect(urls, ['https://im.example.com/object/user/voice.m4a']);
    expect(source.isFile, isTrue);
    expect(source.value, audio.path);
  });

  test('file URI from an iOS attachment is treated as a local source',
      () async {
    final source = await VoicePlaybackSource.load(
        message(path: audio.uri.toString()),
        download: (_) => throw StateError('No download expected'));
    expect(File(source.value).uri, audio.uri);
    expect(source.isFile, isTrue);
  });

  test('empty recording falls back to its uploaded source', () async {
    await audio.writeAsBytes([]);
    final source = await VoicePlaybackSource.load(
        message(path: audio.path, url: 'https://cdn.test/voice.m4a'),
        download: (_) async {
      await audio.writeAsBytes([1]);
      return audio;
    });
    expect(await File(source.value).length(), 1);
  });

  test('slow download falls back to streaming the same signed URL', () async {
    final pending = Completer<File>();
    const url = 'https://cdn.test/voice.m4a?token=secret&signature=a%2Fb';
    final source = await VoicePlaybackSource.load(message(url: url),
        download: (_) => pending.future,
        downloadTimeout: const Duration(milliseconds: 10));
    expect(source.isFile, isFalse);
    expect(source.value, url);
    pending.complete(audio);
  });

  test('failed cache download still permits direct streaming', () async {
    const url = 'http://127.0.0.1:10002/object/user/audio.m4a';
    final source = await VoicePlaybackSource.load(message(url: url),
        imApiUrl: 'https://im.example.com',
        download: (_) async => throw const HttpException('Unavailable'));
    expect(source.isFile, isFalse);
    expect(source.value, 'https://im.example.com/object/user/audio.m4a');
  });

  test('missing source fails without a network request', () async {
    await expectLater(
        VoicePlaybackSource.load(message(),
            download: (_) => throw StateError('Unexpected network')),
        throwsStateError);
  });
}
