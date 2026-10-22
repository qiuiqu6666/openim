import 'package:openim_common/src/media/media_coordinator.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/src/widgets/chat/chat_item_view.dart';
import 'package:openim_common/src/widgets/chat/chat_attachment_view.dart';
import 'package:openim_common/src/widgets/chat/chat_bubble.dart';
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
  double speed = 1;
  final appliedSpeeds = <double>[];
  @override
  Future<void> setSpeed(double value) async {
    speed = value;
    appliedSpeeds.add(value);
  }

  @override
  Stream<Duration> get positionStream => const Stream.empty();
  Duration offset = const Duration(seconds: 1);
  Duration? loadedPosition;
  @override
  Duration get position => offset;
  ProcessingState state = ProcessingState.ready;
  void finish() {
    state = ProcessingState.completed;
    if (!_playing.isCompleted) _playing.complete();
  }

  @override
  ProcessingState get processingState => state;
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
    loadedPosition = initialPosition;
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
  test('speed cycles in place and the next voice inherits it', () async {
    final coordinator = MediaCoordinator(
        readMode: () async => null,
        writeMode: (_) async {},
        configure: (_, __) async {});
    final players = [_Player(), _Player()];
    final messages = [_message('a'), _message('b')];
    var created = 0;
    final controller = VoicePlaybackController(
      messages: () => messages,
      coordinator: coordinator,
      playerFactory: () => players[created++],
      sourceLoader: (_) async => const VoicePlaybackSource.file('/audio'),
    );
    addTearDown(controller.dispose);
    unawaited(controller.toggle(messages.first));
    await _flush();
    final progress = players.first.position;
    await Future.wait([
      controller.cycleSpeed(),
      controller.cycleSpeed(),
      controller.cycleSpeed()
    ]);
    expect(players.first.appliedSpeeds, [2.0, 1.0, 2.0]);
    expect(players.first.position, progress);
    expect(players.first.files, ['/audio']);
    expect(players.first.playCount, 1);
    players.first.finish();
    await _flush();
    expect(players.last.speed, 2.0);
    expect(players.last.playCount, 1);
    await controller.stop();
  });

  testWidgets('speed button cycles without toggling playback', (tester) async {
    final coordinator = MediaCoordinator(
        readMode: () async => null,
        writeMode: (_) async {},
        configure: (_, __) async {});
    final player = _Player();
    final resumed = _Player();
    var created = 0;
    // No source URL: waveform extraction has nothing to download.
    final message = Message.fromJson({
      'clientMsgID': 'speed-widget',
      'soundElem': {'duration': 20}
    });
    final controller = VoicePlaybackController(
        messages: () => [],
        coordinator: coordinator,
        playerFactory: () => created++ == 0 ? player : resumed,
        sourceLoader: (_) async => const VoicePlaybackSource.file('/audio'));
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      unawaited(controller.toggle(message));
      await _flush();
    });
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    OpenIM.iMManager.userID = 'me';
    message.contentType = MessageType.voice;
    message.sendTime = 100000;
    for (final outgoing in [false, true]) {
      message.sendID = outgoing ? 'me' : 'other';
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
              theme: outgoing ? ThemeData.dark() : ThemeData.light(),
              home: Scaffold(
                  body: ChatItemView(
                      message: message,
                      rightNickname: 'Me',
                      rightFaceUrl: '',
                      showAvatar: false,
                      showLeftNickname: false,
                      voicePlayback: controller,
                      onTapUserProfile: (_) {})))));
      final button = find.byKey(const ValueKey('voice-playback-speed'));
      final bubble = find.byType(ChatBubble);
      expect(find.descendant(of: bubble, matching: button), findsNothing);
      final bubbleRect = tester.getRect(bubble);
      final buttonRect = tester.getRect(button);
      if (outgoing) {
        expect(buttonRect.right, lessThan(bubbleRect.left));
      } else {
        expect(buttonRect.left, greaterThan(bubbleRect.right));
      }
      for (final label in ['原速播放', '倍速播放']) {
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        await tester.tap(button);
        await tester.pump();
        expect(find.text(label), findsOneWidget);
        expect(tester.getRect(bubble).size, bubbleRect.size);
        expect(controller.playing, isTrue);
        expect(player.playCount, 1);
        expect(player.disposed, isFalse);
      }
    }
    expect(tester.takeException(), isNull);
    final voiceState = tester.state(find.byType(ChatVoiceMessageView));
    await tester.runAsync(controller.stop);
    await tester.pump();
    expect(tester.state(find.byType(ChatVoiceMessageView)), same(voiceState));
    expect(find.text('继续播放'), findsOneWidget);
    final pendingResume = Completer<Duration?>();
    resumed.onLoad = () => pendingResume.future;
    await tester.tap(find.text('继续播放'));
    await tester.runAsync(_flush);
    await tester.pump();
    expect(controller.loading, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(tester.state(find.byType(ChatVoiceMessageView)), same(voiceState));
    expect(find.byKey(const ValueKey('voice-playback-speed')), findsOneWidget);
    await tester.runAsync(() async {
      pendingResume.complete(const Duration(seconds: 20));
      await _flush();
    });
    await tester.pump();
    expect(tester.state(find.byType(ChatVoiceMessageView)), same(voiceState));
    expect(find.text('倍速播放'), findsOneWidget);
    expect(resumed.loadedPosition, player.position);
    expect(resumed.playCount, 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.runAsync(controller.stop);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
      'live routing does not reload or seek and the next voice uses the same mode',
      () async {
    final routes = <VoiceOutput>[];
    final coordinator = MediaCoordinator(
        readMode: () async => null,
        writeMode: (_) async {},
        configure: (kind, mode) async {
          if (kind == MediaKind.voice) routes.add(mode);
        });
    final first = _Player();
    final second = _Player();
    var created = 0;
    final messages = [_message('a'), _message('b')];
    final controller = VoicePlaybackController(
        messages: () => messages,
        coordinator: coordinator,
        playerFactory: () => created++ == 0 ? first : second,
        sourceLoader: (m) async =>
            VoicePlaybackSource.file('/${m.clientMsgID}'));
    addTearDown(controller.dispose);
    unawaited(controller.toggle(messages.first));
    await _flush();
    await coordinator.setOutput(VoiceOutput.earpiece);
    expect(first.files, ['/a']);
    expect(first.playCount, 1);
    expect(first.disposed, isFalse);
    expect(controller.playing, isTrue);
    first.finish();
    await _flush();
    expect(second.playCount, 1);
    expect(routes.last, VoiceOutput.earpiece);
    expect(first.disposed, isTrue);
    await controller.stop();
  });

  test('manual stop releases the player and replay resumes its saved progress',
      () async {
    final coordinator = MediaCoordinator(
        readMode: () async => null,
        writeMode: (_) async {},
        configure: (_, __) async {});
    final first = _Player()..offset = const Duration(milliseconds: 700);
    final second = _Player();
    var created = 0;
    final controller = VoicePlaybackController(
        messages: () => [],
        coordinator: coordinator,
        playerFactory: () => created++ == 0 ? first : second,
        sourceLoader: (_) async => const VoicePlaybackSource.file('/audio'));
    addTearDown(controller.dispose);
    unawaited(controller.toggle(_message('a')));
    await _flush();
    await controller.toggle(_message('a'));
    expect(first.disposed, isTrue);
    unawaited(controller.toggle(_message('a')));
    await _flush();
    expect(second.loadedPosition, const Duration(milliseconds: 700));
    await controller.stop();
  });

  test('recording preempts voice and blocks taps without automatic resume',
      () async {
    final coordinator = MediaCoordinator(
        readMode: () async => null,
        writeMode: (_) async {},
        configure: (_, __) async {});
    final player = _Player();
    final controller = VoicePlaybackController(
        messages: () => [],
        coordinator: coordinator,
        playerFactory: () => player,
        sourceLoader: (_) async => const VoicePlaybackSource.file('/audio'));
    addTearDown(controller.dispose);
    unawaited(controller.toggle(_message('a')));
    await _flush();
    final recording =
        await coordinator.acquire(MediaKind.recording, () async {});
    expect(player.disposed, isTrue);
    expect(controller.playing, isFalse);
    await controller.toggle(_message('b'));
    expect(controller.current!.clientMsgID, 'a');
    await recording!.release(stopped: true);
    await _flush();
    expect(player.playCount, 1);
    expect(controller.playing, isFalse);
  });

  test('completion cannot auto-advance over a pending video request', () async {
    final coordinator = MediaCoordinator(
        readMode: () async => null,
        writeMode: (_) async {},
        configure: (_, __) async {});
    final player = _Player();
    final messages = [_message('a'), _message('b')];
    final controller = VoicePlaybackController(
        messages: () => messages,
        coordinator: coordinator,
        playerFactory: () => player,
        sourceLoader: (_) async => const VoicePlaybackSource.file('/audio'));
    addTearDown(controller.dispose);
    unawaited(controller.toggle(messages.first));
    await _flush();
    player.finish();
    final video = await coordinator.acquire(MediaKind.video, () async {});
    await _flush();
    expect(video!.valid, isTrue);
    expect(player.playCount, 1);
    expect(controller.playing, isFalse);
    await video.release();
  });

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
