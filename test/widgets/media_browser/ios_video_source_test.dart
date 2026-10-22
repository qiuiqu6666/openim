import 'package:openim_common/src/media/media_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/native_media_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

final _video = Uint8List.fromList([
  0,
  0,
  0,
  24,
  ...ascii.encode('ftypisom'),
  ...List.filled(12, 0),
]);

class _VideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final events = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  final networkCreated = Completer<void>();
  final downloadReady = Completer<void>();
  bool holdDownload = false;
  bool failFile = false;

  @override
  Future<void> init() async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final source = options.dataSource;
    sources.add(source);
    if (source.sourceType == DataSourceType.network) {
      networkCreated.complete();
      if (holdDownload) await downloadReady.future;
      // Simulate a shared download completing while native streaming fails.
      // Deliberately use the cache's generic .bin filename, as object storage
      // returning application/octet-stream does in production.
      await DefaultCacheManager()
          .putFile(source.uri!, _video, fileExtension: 'bin');
    }
    return sources.length;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    final stream = StreamController<VideoEvent>();
    events[id] = stream;
    if (sources[id - 1].sourceType == DataSourceType.network || failFile) {
      stream.addError(
          PlatformException(code: 'VideoError', message: 'Cannot open source'));
    } else {
      stream.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 2),
          size: const Size(160, 240)));
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

Future<void> _flush(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  await tester.pump();
}

Future<void> _flushCacheWrites(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 21));
  // JSON cache writes cross several real file-I/O and FakeAsync continuations.
  // Drain them before the test zone ends, including closing Windows handles.
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await MediaCoordinator.instance.initialize();
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late VideoPlayerPlatform previous;
  late _VideoPlatform platform;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('ios-video-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    // Create cache storage outside the per-widget FakeAsync zone, so shared
    // cache initialization cannot retain a previous test's event queue.
    await DefaultCacheManager().putFile('test-cache-init', Uint8List(0));
  });
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() {
    VideoPlayerPlatform.instance = previous;
  });
  tearDownAll(() async {
    await DefaultCacheManager().emptyCache();
    await DefaultCacheManager().dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  for (final failFile in [false, true]) {
    testWidgets(
        'iOS streaming failure tries a correctly named downloaded file (fails=$failFile)',
        (tester) async {
      platform.failFile = failFile;
      final url = 'https://cdn.test/video-$failFile?signature=keep%2Bvalue';
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: NativeMediaVideo(
        url: url,
        autoPlay: true,
        muted: false,
      ))));
      await _flush(tester, () => platform.events.length == 2);
      await tester.pump();
      expect(platform.sources.map((source) => source.sourceType),
          [DataSourceType.network, DataSourceType.file]);
      expect(platform.sources.first.uri, url);
      final local = File.fromUri(Uri.parse(platform.sources.last.uri!));
      expect(local.path, endsWith('.mp4'));
      expect(await tester.runAsync(local.readAsBytes), _video);
      expect(
          find.text('视频加载失败，点击重试'), failFile ? findsOneWidget : findsNothing);
      if (!failFile) expect(find.byType(Slider), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _flushCacheWrites(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  testWidgets('file-only temporary previews do not create persistent copies',
      (tester) async {
    final file = await tester.runAsync(() =>
        File('${directory.path}/temporary-original').writeAsBytes(_video));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NativeMediaVideo(
      file: file,
      autoPlay: true,
      muted: false,
    ))));
    await _flush(tester, () => platform.events.isNotEmpty);
    expect(platform.sources, hasLength(1));
    expect(
        File.fromUri(Uri.parse(platform.sources.single.uri!)).uri, file!.uri);
    await tester.pumpWidget(const SizedBox());
    await _flushCacheWrites(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
      'leaving during failed network loading cannot start local fallback',
      (tester) async {
    platform.holdDownload = true;
    await tester.pumpWidget(const MaterialApp(
        home: NativeMediaVideo(
      url: 'https://cdn.test/closed-video',
      autoPlay: true,
      muted: false,
    )));
    await _flush(tester, () => platform.networkCreated.isCompleted);
    await tester.pumpWidget(const SizedBox());
    platform.downloadReady.complete();
    await _flush(tester, () => platform.disposed.isNotEmpty);
    expect(platform.sources, hasLength(1));
    expect(tester.takeException(), isNull);
    await _flushCacheWrites(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
