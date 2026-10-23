import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/src/widgets/chat/chat_attachment_view.dart';
import 'package:openim_common/src/widgets/chat/voice/voice_seek_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/media/media_coordinator.dart';
import 'package:openim_common/src/widgets/chat/voice_playback_controller.dart';
import 'package:openim_common/src/widgets/chat/voice/voice_playback_source.dart';
import '../../../voice_playback_test.dart' show FakePlayer, voice, flush;

class SeekPlayer extends FakePlayer {
  final seeks = <Duration>[];
  Duration offset = Duration.zero;
  Duration? initial;
  Completer<void>? seekGate;
  bool failSeek = false;
  @override
  Duration get position => offset;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks.add(position!);
    await seekGate?.future;
    if (failSeek) throw StateError('seek failed');
    offset = position;
  }

  @override
  Future<Duration?> setUrl(String url,
      {Map<String, String>? headers,
      Duration? initialPosition,
      bool preload = true,
      dynamic tag}) async {
    initial = initialPosition;
    offset = initialPosition ?? Duration.zero;
    return super.setUrl(url, initialPosition: initialPosition);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VoicePlaybackController controller;
  late List<SeekPlayer> players;
  final a = voice('a', 1), b = voice('b', 2);
  setUp(() {
    players = [];
    controller = VoicePlaybackController(
        messages: () => [a, b],
        coordinator: MediaCoordinator(
            readMode: () async => null,
            writeMode: (_) async {},
            configure: (_, __) async {}),
        playerFactory: () {
          final p = SeekPlayer();
          players.add(p);
          return p;
        },
        sourceLoader: (message) async =>
            VoicePlaybackSource.remote(message.soundElem!.sourceUrl!));
  });
  tearDown(() => controller.dispose());

  testWidgets(
      'bubble seek reaches player and preserves displayed paused position',
      (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            home: Scaffold(
                body: Center(
                    child: ChatVoiceMessageView(
                        message: a,
                        isOutgoing: true,
                        playback: controller))))));
    unawaited(controller.toggle(a));
    await tester.runAsync(flush);
    await tester.pumpAndSettle();
    expect(controller.playing, isTrue);
    expect(tester.widget<VoiceSeekBar>(find.byType(VoiceSeekBar)).onSeek, isNotNull);
    final rect = tester.getRect(find.byType(VoiceSeekBar));
    await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
    await tester.runAsync(flush);
    await tester.pumpAndSettle();
    expect(controller.playing, isTrue, reason: 'wave tap must not toggle');
    expect(players.single.seeks, isNotEmpty, reason: 'rect=$rect');
    expect(players.single.seeks.single.inMilliseconds, closeTo(1500, 5));
    expect(controller.playing, isTrue);
    expect(tester.widget<VoiceSeekBar>(find.byType(VoiceSeekBar)).progress,
        closeTo(.75, .01));
    await controller.stop();
    await tester.pumpAndSettle();
    expect(tester.widget<VoiceSeekBar>(find.byType(VoiceSeekBar)).progress,
        closeTo(.75, .01));
    await tester.pumpWidget(const SizedBox());
  });

  test('active seek keeps player and playback, clamps both ends', () async {
    unawaited(controller.toggle(a));
    await flush();
    await controller.seek(a, .75);
    expect(players.single.position, const Duration(milliseconds: 1500));
    expect(controller.playing, isTrue);
    expect(players.single.urls.length, 1);
    await controller.seek(a, -2);
    await controller.seek(a, 2);
    expect(players.single.seeks, [
      const Duration(milliseconds: 1500),
      Duration.zero,
      const Duration(seconds: 2)
    ]);
  });

  test(
      'idle and paused seeks load chosen position instead of old resume position',
      () async {
    await controller.seek(a, .5);
    await flush();
    expect(players.single.initial, const Duration(seconds: 1));
    await controller.stop();
    expect(controller.positionFor(a), const Duration(seconds: 1));
    await controller.seek(a, .75);
    await flush();
    expect(players.last.initial, const Duration(milliseconds: 1500));
    expect(controller.playing, isTrue);
    await controller.seek(b, .25);
    await flush();
    expect(players.last.initial, const Duration(milliseconds: 500));
    expect(controller.current, b);
    expect(controller.positionFor(a), Duration.zero);
  });

  test('queued seeks cannot touch retired player after message switch',
      () async {
    unawaited(controller.toggle(a));
    await flush();
    final old = players.single;
    old.seekGate = Completer<void>();
    final first = controller.seek(a, .2);
    await flush();
    final second = controller.seek(a, .8);
    unawaited(controller.toggle(b));
    await flush();
    old.seekGate!.complete();
    await Future.wait([first, second]);
    expect(old.seeks.length, 1);
    expect(players.last.seeks, isEmpty);
    expect(controller.current, b);
  });

  test('failed seek can be retried and invalid fraction is ignored', () async {
    await controller.seek(a, double.nan);
    expect(players, isEmpty);
    unawaited(controller.toggle(a));
    await flush();
    players.single.failSeek = true;
    await controller.seek(a, .5);
    players.single.failSeek = false;
    await controller.seek(a, .75);
    expect(controller.playing, isTrue);
    expect(players.single.position, const Duration(milliseconds: 1500));
  });
}
