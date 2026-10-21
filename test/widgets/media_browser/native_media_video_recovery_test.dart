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
  final seeks = <Duration>[];
  final speeds = <double>[];
  Completer<void>? speedGate;
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
  Future<void> seekTo(int id, Duration position) async => seeks.add(position);
  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {
    speeds.add(speed);
    if (speed == 2) await speedGate?.future;
  }

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

  for (final right in [false, true]) {
    testWidgets('edge hold restores chosen speed (right: $right)',
        (tester) async {
      await mount(tester);
      await tester.tap(find.text('1.0倍'));
      await tester.pump();
      final bounds = tester.getRect(find.byType(NativeMediaVideo));
      final gesture = await tester.startGesture(Offset(
          right ? bounds.right - 30 : bounds.left + 30, bounds.center.dy));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('2倍速播放'), findsOneWidget);
      expect(platform.speeds.last, 2);
      if (right) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();
      expect(platform.speeds.last, 1.5);
      expect(find.text('2倍速播放'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets('release waits for pending native speed change before restoring',
      (tester) async {
    await mount(tester);
    platform.speedGate = Completer<void>();
    final bounds = tester.getRect(find.byType(NativeMediaVideo));
    final gesture =
        await tester.startGesture(Offset(bounds.left + 30, bounds.center.dy));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();
    expect(find.text('2倍速播放'), findsNothing);
    expect(platform.speeds.last, 2);
    platform.speedGate!.complete();
    await tester.pump();
    expect(platform.speeds.last, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('short edge tap and center hold do not change speed',
      (tester) async {
    await mount(tester);
    platform.speeds.clear();
    final bounds = tester.getRect(find.byType(NativeMediaVideo));
    await tester.tapAt(Offset(bounds.left + 30, bounds.center.dy));
    final gesture = await tester.startGesture(bounds.center);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    expect(platform.speeds, isEmpty);
    expect(find.text('2倍速播放'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('closing during an edge hold safely disposes playback',
      (tester) async {
    await mount(tester);
    final bounds = tester.getRect(find.byType(NativeMediaVideo));
    final gesture =
        await tester.startGesture(Offset(bounds.left + 30, bounds.center.dy));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(platform.disposed, contains(1));
  });

  testWidgets('backgrounding restores speed while finger is still held',
      (tester) async {
    await mount(tester);
    final bounds = tester.getRect(find.byType(NativeMediaVideo));
    final gesture =
        await tester.startGesture(Offset(bounds.left + 30, bounds.center.dy));
    await tester.pump(const Duration(milliseconds: 600));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(platform.speeds.last, 1);
    expect(find.text('2倍速播放'), findsNothing);
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('speed button accepts edge taps and displays decimal multiples',
      (tester) async {
    await mount(tester);
    final button = find.widgetWithText(TextButton, '1.0倍');
    final bounds = tester.getRect(button);
    expect(bounds.width, greaterThanOrEqualTo(72));
    expect(bounds.height, greaterThanOrEqualTo(48));
    for (final speed in [1.5, 2.0, 0.5, 1.0]) {
      await tester.tapAt(bounds.bottomRight - const Offset(4, 4));
      await tester.pump();
      expect(platform.speeds.last, speed);
      expect(find.text('${speed.toStringAsFixed(1)}倍'), findsOneWidget);
    }
    expect(platform.seeks, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('seek accepts taps and drags away from the visible track',
      (tester) async {
    await mount(tester);
    final slider = find.byType(Slider);
    final bounds = tester.getRect(slider);
    expect(bounds.height, greaterThanOrEqualTo(48));

    // A finger need not land exactly on the thin painted track.
    await tester.tapAt(Offset(bounds.center.dx, bounds.center.dy + 24));
    await tester.pump();
    expect(platform.seeks.last.inMilliseconds, closeTo(5000, 300));

    await tester.dragFrom(
      Offset(bounds.center.dx, bounds.center.dy - 24),
      Offset(bounds.width / 4, 0),
    );
    await tester.pump();
    expect(platform.seeks.last.inMilliseconds, greaterThan(7000));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

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
