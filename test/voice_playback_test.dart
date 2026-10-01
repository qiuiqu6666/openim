import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';

class FakePlayer implements AudioPlayer {
  Completer<void>? pending;
  final urls = <String>[];
  bool disposed = false;
  @override
  ProcessingState processingState = ProcessingState.ready;
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => const Duration(seconds: 2);
  @override
  Future<void> stop() async {
    await pause();
  }

  @override
  Future<void> pause() async {
    if (pending != null && !pending!.isCompleted) pending!.complete();
  }

  @override
  Future<Duration?> setUrl(String url,
      {Map<String, String>? headers,
      Duration? initialPosition,
      bool preload = true,
      dynamic tag}) async {
    urls.add(url);
    processingState = ProcessingState.ready;
    return duration;
  }

  @override
  Future<void> play() {
    pending = Completer<void>();
    return pending!.future;
  }

  void complete() {
    processingState = ProcessingState.completed;
    pending!.complete();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await pause();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message voice(String id, int time) => Message.fromJson({
      'clientMsgID': id,
      'sendTime': time,
      'contentType': MessageType.voice,
      'soundElem': {'sourceUrl': 'https://example.com/$id.mp3', 'duration': 2}
    });
Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('completion plays next chronological audio across other messages',
      () async {
    final first = voice('a', 1), next = voice('b', 3);
    final player = FakePlayer();
    final heard = <String?>[];
    final controller = VoicePlaybackController(
        messages: () => [
              next,
              Message.fromJson({'clientMsgID': 'text', 'sendTime': 2}),
              first
            ],
        playerFactory: () => player,
        onPlayed: (m) async {
          heard.add(m.clientMsgID);
        });
    unawaited(controller.toggle(first));
    await flush();
    player.complete();
    await flush();
    expect(controller.current?.clientMsgID, 'b');
    expect(player.urls.length, 2);
    expect(heard, ['a', 'b']);
    player.complete();
    await flush();
    expect(controller.playing, isFalse);
    controller.dispose();
    expect(player.disposed, isTrue);
  });
  test('manual pause cancels automatic advancement', () async {
    final first = voice('a', 1), next = voice('b', 2);
    final player = FakePlayer();
    final controller = VoicePlaybackController(
        messages: () => [first, next], playerFactory: () => player);
    unawaited(controller.toggle(first));
    await flush();
    await controller.toggle(first);
    await flush();
    expect(player.urls.length, 1);
    expect(controller.playing, isFalse);
    controller.dispose();
  });
  test('inactive overlay retains playback; app background stops it', () async {
    final first = voice('a', 1);
    final player = FakePlayer();
    final controller = VoicePlaybackController(
        messages: () => [first], playerFactory: () => player);
    unawaited(controller.toggle(first));
    await flush();
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(controller.playing, isTrue);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await flush();
    expect(controller.playing, isFalse);
    controller.dispose();
  });
}
