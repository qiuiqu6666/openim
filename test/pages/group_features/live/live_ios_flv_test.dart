import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as media;
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/playback/live_flv_engine.dart';
import 'package:openim/pages/group_features/live/playback/live_flv_video_controller.dart';
import 'package:openim/pages/group_features/live/playback/live_playback_controller.dart';
import 'package:openim/pages/group_features/live/playback/live_video_factory.dart';
import 'package:openim/pages/group_features/live/playback/live_player_view.dart';
import 'package:openim/pages/group_features/live/playback/live_video_surface.dart';
import 'live_test_support.dart';

class FakeFlvEngine extends LiveFlvEngine {
  final Completer<void>? gate;
  final bool initializeVideo;
  FakeFlvEngine({this.gate, this.initializeVideo = true});
  final commands = <String>[];
  Uri? source;
  int closes = 0;
  @override
  media.VideoController? get videoController => null;
  @override
  Future<void> open(Uri uri) async {
    source = uri;
    commands.add('open');
    await gate?.future;
    if (closes == 0 && initializeVideo) {
      value = value.copyWith(isInitialized: true, size: const Size(720, 1280));
    }
  }

  @override
  Future<void> play() async {
    commands.add('play');
    value =
        value.copyWith(isPlaying: true, position: const Duration(seconds: 1));
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> setVolume(double volume) async {
    commands.add('volume:$volume');
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> close() async {
    closes++;
    super.dispose();
  }
}

const info = LivePlayInfo(
    id: 'ios-live',
    roomName: '',
    protocol: 'hls',
    playURL: 'https://video.test/live.m3u8?signature=hls',
    flvURL: 'https://video.test/live.flv?signature=flv');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets(
      'FLV startup timeout falls back and releases pending initialization',
      (tester) async {
    final engine = FakeFlvEngine(initializeVideo: false);
    final sources = <Uri>[];
    final controller = LivePlaybackController(info,
        sessionCurrent: () => true,
        factory: (uri) {
          sources.add(uri);
          return uri.path.endsWith('.flv')
              ? LiveFlvVideoController(uri, engineFactory: () => engine)
              : TestLiveVideo(uri);
        });
    final opening = controller.open();
    await tester.pump();
    expect(controller.loading, isTrue);
    await tester.pump(const Duration(seconds: 13));
    await opening;
    expect(sources.map((uri) => uri.toString()), [info.flvURL, info.playURL]);
    expect(engine.closes, 1);
    expect(controller.ready, isTrue);
    controller.dispose();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('FLV surface shares its engine across fullscreen and returns',
      (tester) async {
    // Exercise shared Flutter controls without an actual iOS AirPlay platform view.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final engine = FakeFlvEngine();
    var creations = 0;
    final controller = LivePlaybackController(info,
        sessionCurrent: () => true,
        factory: (uri) {
          creations++;
          return LiveFlvVideoController(uri, engineFactory: () => engine);
        });
    await controller.open();
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            home: Scaffold(
                body: LivePlayerView(
                    controller: controller, roomName: '直播测试')))));
    await tester.pumpAndSettle();
    expect(find.byType(LiveVideoSurface), findsOneWidget);
    await tester.tap(find.text('全屏观看'));
    await tester.pumpAndSettle();
    expect(creations, 1);
    expect(engine.closes, 0);
    expect(find.text('退出全屏'), findsOneWidget);
    await tester.tap(find.text('退出全屏'));
    await tester.pumpAndSettle();
    expect(creations, 1);
    expect(engine.commands.where((command) => command == 'pause'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump();
    expect(engine.closes, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  test('factory routes only iOS FLV through dedicated engine', () async {
    for (final platform in TargetPlatform.values) {
      final video = createLiveVideo(Uri.parse(info.flvURL),
          platform: platform, web: false);
      expect(video is LiveFlvVideoController, platform == TargetPlatform.iOS);
      await video.dispose();
    }
    final hls = createLiveVideo(Uri.parse(info.playURL));
    expect(hls, isNot(isA<LiveFlvVideoController>()));
    expect(hls.httpHeaders, {'X-99Chat-Local-Live-Playback': '1'});
    await hls.dispose();
    final web = createLiveVideo(Uri.parse(info.flvURL), web: true);
    expect(web, isNot(isA<LiveFlvVideoController>()));
    await web.dispose();
  });

  test('iOS FLV starts muted and preserves pause/volume ownership', () async {
    final engine = FakeFlvEngine();
    final controller = LivePlaybackController(info,
        sessionCurrent: () => true,
        muted: true,
        factory: (uri) =>
            LiveFlvVideoController(uri, engineFactory: () => engine));
    await controller.open();
    expect(engine.source.toString(), info.flvURL);
    expect(engine.commands, ['open', 'volume:0.0', 'play']);
    expect(controller.ready, isTrue);
    expect(controller.player!.value.aspectRatio, 720 / 1280);
    await controller.toggleMute();
    expect(engine.value.volume, 1);
    await controller.suspend();
    expect(engine.commands.last, 'pause');
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(engine.closes, 1);
  });

  test('FLV decoder failure closes engine before native HLS fallback',
      () async {
    final engine = FakeFlvEngine();
    final sources = <Uri>[];
    final controller = LivePlaybackController(info,
        sessionCurrent: () => true,
        muted: true,
        factory: (uri) {
          sources.add(uri);
          if (uri.path.endsWith('.flv')) {
            return LiveFlvVideoController(uri, engineFactory: () => engine);
          }
          expect(engine.closes, 1);
          return TestLiveVideo(uri);
        });
    await controller.open();
    engine.value = engine.value.copyWith(errorDescription: 'decoder failure');
    await Future<void>.delayed(Duration.zero);
    expect(sources.map((uri) => uri.toString()), [info.flvURL, info.playURL]);
    expect(controller.ready, isTrue);
    expect(controller.player!.value.volume, 0);
    controller.dispose();
  });

  test('close during initialization cannot autoplay or retain the FLV engine',
      () async {
    final gate = Completer<void>();
    final engine = FakeFlvEngine(gate: gate);
    final controller = LivePlaybackController(info,
        sessionCurrent: () => true,
        factory: (uri) =>
            LiveFlvVideoController(uri, engineFactory: () => engine));
    final opening = controller.open();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    gate.complete();
    await opening;
    expect(engine.commands, ['open']);
    expect(engine.closes, 1);
  });

  test(
      'missing FLV engine falls back instead of escaping as an unhandled error',
      () async {
    final sources = <Uri>[];
    final controller = LivePlaybackController(info,
        sessionCurrent: () => true,
        factory: (uri) {
          sources.add(uri);
          if (uri.path.endsWith('.flv')) {
            throw StateError('native engine unavailable');
          }
          return TestLiveVideo(uri);
        });
    await controller.open();
    await Future<void>.delayed(Duration.zero);
    expect(sources.map((uri) => uri.toString()), [info.flvURL, info.playURL]);
    expect(controller.ready, isTrue);
    controller.dispose();
  });
}
