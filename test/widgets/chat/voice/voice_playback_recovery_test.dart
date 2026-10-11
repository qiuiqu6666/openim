import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/src/widgets/chat/voice/voice_playback_source.dart';
import 'package:openim_common/src/widgets/chat/voice_playback_controller.dart';

class _Player implements AudioPlayer {
  Future<void> Function()? onStop;
  Future<Duration?> Function()? onLoad;
  final files = <String>[];
  final urls = <String>[];
  final _playing = Completer<void>();
  bool disposed = false;
  int playCount = 0;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Future<void> stop() async => onStop?.call();
  @override
  Future<void> pause() async {
    if (!_playing.isCompleted) _playing.complete();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await pause();
  }

  @override
  Future<Duration?> setFilePath(String path,
      {Duration? initialPosition, bool preload = true, dynamic tag}) async {
    files.add(path);
    return onLoad?.call() ?? const Duration(seconds: 2);
  }

  @override
  Future<Duration?> setUrl(String url,
      {Map<String, String>? headers,
      Duration? initialPosition,
      bool preload = true,
      dynamic tag}) async {
    urls.add(url);
    return onLoad?.call() ?? const Duration(seconds: 2);
  }

  @override
  Future<void> play() {
    playCount++;
    return _playing.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _message(String id) => Message.fromJson({
      'clientMsgID': id,
      'soundElem': {'sourceUrl': 'https://cdn.test/$id.m4a', 'duration': 2}
    });

Future<void> _flush() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('local decode failure tries the original remote source once', () async {
    final player = _Player();
    var loads = 0;
    player.onLoad = () async {
      if (loads++ == 0) {
        throw PlayerException(1, 'Unrecognized local format', 0);
      }
      return const Duration(seconds: 2);
    };
    const url = 'https://cdn.test/audio?signature=keep%2Bthis';
    final heard = <String?>[];
    final controller = VoicePlaybackController(
      messages: () => [],
      playerFactory: () => player,
      sourceLoader: (_) async =>
          const VoicePlaybackSource.file('/cache/audio.bin', fallbackUrl: url),
      onPlayed: (message) async => heard.add(message.clientMsgID),
    );
    addTearDown(controller.dispose);
    unawaited(controller.toggle(_message('voice')));
    await _flush();
    expect(player.files, ['/cache/audio.bin']);
    expect(player.urls, [url]);
    expect(player.playCount, 1);
    expect(controller.playing, isTrue);
    expect(controller.failed, isFalse);
    expect(heard, ['voice']);
  });

  test('both local and remote decoding failures leave retry available',
      () async {
    final player = _Player()
      ..onLoad = () async => throw PlayerException(1, 'Bad data', 0);
    final controller = VoicePlaybackController(
      messages: () => [],
      playerFactory: () => player,
      sourceLoader: (_) async => const VoicePlaybackSource.file(
          '/cache/bad.bin',
          fallbackUrl: 'https://cdn.test/bad'),
    );
    addTearDown(controller.dispose);
    await controller.toggle(_message('voice'));
    expect(player.files, hasLength(1));
    expect(player.urls, hasLength(1));
    expect(player.playCount, 0);
    expect(player.disposed, isTrue);
    expect(controller.failed, isTrue);
    expect(controller.loading, isFalse);
  });

  test('cancelled local load cannot start a remote fallback on late failure',
      () async {
    final pending = Completer<Duration?>();
    final player = _Player()..onLoad = () => pending.future;
    final controller = VoicePlaybackController(
      messages: () => [],
      playerFactory: () => player,
      sourceLoader: (_) async => const VoicePlaybackSource.file(
          '/cache/audio.bin',
          fallbackUrl: 'https://cdn.test/audio'),
    );
    addTearDown(controller.dispose);
    final playing = controller.toggle(_message('voice'));
    await _flush();
    controller.stop();
    pending.completeError(PlayerException(1, 'Late failure', 0));
    await playing;
    expect(player.urls, isEmpty);
    expect(player.playCount, 0);
    expect(controller.failed, isFalse);
  });

  for (final phase in ['stop', 'source', 'decode']) {
    test('$phase timeout leaves retry available and ignores late completion',
        () async {
      final blocked = Completer<void>();
      final stale = _Player();
      final fresh = _Player();
      var created = 0;
      var loads = 0;
      final heard = <String?>[];
      if (phase == 'stop') stale.onStop = () => blocked.future;
      if (phase == 'decode') {
        stale.onLoad = () async {
          await blocked.future;
          return const Duration(seconds: 2);
        };
      }
      final controller = VoicePlaybackController(
        messages: () => [],
        playerFactory: () => created++ == 0 ? stale : fresh,
        prepareTimeout: const Duration(milliseconds: 30),
        sourceLoader: (message) async {
          if (loads++ == 0 && phase == 'source') await blocked.future;
          return VoicePlaybackSource.file('/cached/${message.clientMsgID}.m4a');
        },
        onPlayed: (message) async => heard.add(message.clientMsgID),
      );
      addTearDown(controller.dispose);
      await controller.toggle(_message('first'));
      expect(controller.loading, isFalse);
      expect(controller.failed, isTrue);
      expect(stale.disposed, isTrue);
      expect(heard, isEmpty);

      unawaited(controller.toggle(_message('retry')));
      await _flush();
      expect(controller.playing, isTrue);
      expect(controller.failed, isFalse);
      expect(fresh.files, ['/cached/retry.m4a']);
      blocked.complete();
      await _flush();
      expect(controller.current?.clientMsgID, 'retry');
      expect(controller.playing, isTrue);
      expect(stale.playCount, 0);
      expect(fresh.playCount, 1);
      expect(heard, ['retry']);
    });
  }

  for (final action in ['tap', 'background', 'dispose', 'another_message']) {
    test('$action during preparation cannot start stale playback', () async {
      final source = Completer<VoicePlaybackSource>();
      final stale = _Player(), fresh = _Player();
      var created = 0;
      final first = _message('first');
      final controller = VoicePlaybackController(
        messages: () => [],
        playerFactory: () => created++ == 0 ? stale : fresh,
        sourceLoader: (message) => message.clientMsgID == 'first'
            ? source.future
            : Future.value(
                const VoicePlaybackSource.remote('https://cdn.test/b.m4a')),
      );
      unawaited(controller.toggle(first));
      await _flush();
      expect(controller.loading, isTrue);
      switch (action) {
        case 'tap':
          await controller.toggle(first);
        case 'background':
          controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        case 'dispose':
          controller.dispose();
        case 'another_message':
          unawaited(controller.toggle(_message('second')));
          await _flush();
      }
      source.complete(const VoicePlaybackSource.file('/cached/stale.m4a'));
      await _flush();
      expect(stale.disposed, isTrue);
      expect(stale.files, isEmpty);
      expect(stale.playCount, 0);
      if (action == 'another_message') {
        expect(fresh.playCount, 1);
        expect(controller.current?.clientMsgID, 'second');
      } else {
        expect(controller.loading, isFalse);
        expect(controller.playing, isFalse);
      }
      if (action != 'dispose') controller.dispose();
    });
  }
}
