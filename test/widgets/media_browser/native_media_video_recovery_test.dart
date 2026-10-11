import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/native_media_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Platform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final events = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  bool failLocal = false;
  bool hang = false;

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource);
    return sources.length;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    final stream = StreamController<VideoEvent>();
    events[id] = stream;
    if (!hang) {
      if (failLocal && sources[id - 1].sourceType == DataSourceType.file) {
        stream.addError(
            PlatformException(code: 'VideoError', message: 'bad file'));
      } else {
        stream.add(VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 10),
            size: const Size(160, 240)));
      }
    }
    return stream.stream;
  }

  @override
  Future<void> dispose(int id) async {
    disposed.add(id);
    await events[id]?.close();
  }

  @override
  Future<void> setLooping(int id, bool looping) async {}
  @override
  Future<void> setVolume(int id, double volume) async {}
  @override
  Future<void> play(int id) async {}
  @override
  Future<void> pause(int id) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

Future<void> mount(WidgetTester tester, {String? url}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: NativeMediaVideo(
    file: File('openim_common/assets/images/ic_archive_99chat.png'),
    url: url,
    httpHeaders: const {'Authorization': 'Bearer test'},
    autoPlay: true,
    muted: false,
  ))));
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
}

void main() {
  late VideoPlayerPlatform previous;
  late _Platform platform;
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = _Platform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = previous);

  testWidgets('bad local file falls back to remote with original headers',
      (tester) async {
    platform.failLocal = true;
    await mount(tester, url: 'https://example.test/video.mp4');
    expect(platform.sources.map((s) => s.sourceType),
        [DataSourceType.file, DataSourceType.network]);
    expect(platform.sources.last.httpHeaders, {'Authorization': 'Bearer test'});
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(platform.disposed, contains(1));
    expect(find.byType(Slider), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('loading timeout shows retry and disposes pending player',
      (tester) async {
    platform.hang = true;
    await mount(tester);
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
    expect(find.text('视频加载失败，点击重试'), findsOneWidget);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(platform.disposed, contains(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('leaving while initializing disposes without waiting for event',
      (tester) async {
    platform.hang = true;
    await mount(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(platform.disposed, contains(1));
    await tester.pump(const Duration(seconds: 21));
    expect(tester.takeException(), isNull);
  });

  testWidgets('runtime decoder failure exits black frame and can retry remote',
      (tester) async {
    await mount(tester, url: 'https://example.test/video.mp4');
    platform.events[1]!.addError(
        PlatformException(code: 'VideoError', message: 'decoder failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('视频加载失败，点击重试'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    await tester.pump();
    expect(platform.sources.last.sourceType, DataSourceType.network);
    expect(find.byType(Slider), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
