import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/widgets/live_watch_surface.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim_common/openim_common.dart';
import 'package:video_player/video_player.dart';

import 'live_test_support.dart';

const _castChannel = MethodChannel('openim_group_live_cast');

class _RecordedVideo extends TestLiveVideo {
  _RecordedVideo(super.uri);
  final volumesAtPlay = <double>[];

  @override
  Future<void> play() {
    volumesAtPlay.add(value.volume);
    return super.play();
  }
}

class _WatchFixture {
  _WatchFixture({
    this.initialStatus = LiveStatus.authorized,
    this.detail,
  }) {
    status = initialStatus.name.toUpperCase();
    transport = LiveTransport((request) {
      if (request.path.endsWith('/play-info')) {
        return {
          'liveSessionId': 'live-1',
          'roomName': '每日直播',
          'anchorUserId': 'anchor',
          'protocol': 'hls',
          'playUrl': 'https://video.example.test/live.m3u8',
        };
      }
      return detail?.call(detailReads) ??
          liveDTO(status: status, version: version);
    });
    context = liveContext(
      transport.api(),
      current: () => accountCurrent,
      features: GroupFeatures.fromJson({
        'schemaVersion': 1,
        'revision': 1,
        'live': {
          'sessionID': 'live-1',
          'status': initialStatus == LiveStatus.live ? 'live' : 'ready',
          'roomName': '每日直播',
          'anchorUserID': 'anchor',
        },
      }),
      events: events.stream,
    );
  }

  final LiveStatus initialStatus;
  final FutureOr<Map<String, dynamic>> Function(int requestNumber)? detail;
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final navigator = GlobalKey<NavigatorState>();
  final videos = <_RecordedVideo>[];
  late final LiveTransport transport;
  late final GroupFeatureContext context;
  late String status;
  int version = 1;
  bool accountCurrent = true;
  int closes = 0;

  int get detailReads => transport.requests
      .where((request) => request.path.endsWith('/live/live-1'))
      .length;
  int get credentialReads => transport.requests
      .where((request) => request.path.endsWith('/play-info'))
      .length;

  VideoPlayerController createVideo(Uri source) {
    final video = _RecordedVideo(source);
    videos.add(video);
    return video;
  }

  void publish(String state, {String sessionID = 'live-1'}) {
    events.add({
      'key': 'groupFeaturesChanged',
      'groupID': 'group#1',
      'data': {
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 100,
          'live': {'sessionID': sessionID, 'status': state},
        },
      },
    });
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(
  WidgetTester tester,
  _WatchFixture fixture, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(390, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    fontSizeResolver: (fontSize, _) => fontSize.toDouble(),
    builder: (_, __) => MaterialApp(
      navigatorKey: fixture.navigator,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: Column(children: [
          GroupLiveWatchSurface(
            featureContext: fixture.context,
            session: liveSession(status: fixture.initialStatus),
            videoFactory: fixture.createVideo,
            onClose: () => fixture.closes++,
          ),
        ]),
      ),
    ),
  ));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.events.close();
  });
  await _frames(tester);
}

Future<void> _enterFullscreen(WidgetTester tester) async {
  await tester.tap(find.text('全屏观看').hitTestable());
  await _frames(tester);
  expect(find.text('退出全屏').hitTestable(), findsOneWidget);
}

Future<void> _exitFullscreen(WidgetTester tester) async {
  await tester.tap(find.text('退出全屏').hitTestable());
  await _frames(tester);
  // A popped Material route may retain its offstage subtree until its reverse
  // transition ends. Waiting spinners prevent using pumpAndSettle here.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(find.text('退出全屏', skipOffstage: false), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var casts = 0;
  setUp(() {
    Get.testMode = true;
    casts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_castChannel, (call) async {
      expect(call.method, 'openCastSettings');
      expect(call.arguments, isNull);
      casts++;
      return true;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_castChannel, null);
    Styles.isDark = false;
    Get.reset();
  });

  for (final dark in [false, true]) {
    testWidgets(
        'waiting controls fullscreen, mute and system casting work in ${dark ? 'dark' : 'light'} theme',
        (tester) async {
      final fixture = _WatchFixture();
      await _mount(tester, fixture, dark: dark);
      expect(find.text('直播准备中，请稍候…'), findsOneWidget);
      expect(find.byTooltip('静音').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('静音').hitTestable());
      await _frames(tester);
      expect(find.byTooltip('打开声音').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('投屏').hitTestable());
      await _frames(tester);
      expect(casts, 1);

      await _enterFullscreen(tester);
      expect(find.text('直播准备中，请稍候…').hitTestable(), findsOneWidget);
      expect(find.byTooltip('打开声音').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('投屏').hitTestable());
      await _frames(tester);
      expect(casts, 2);
      await _exitFullscreen(tester);
      expect(find.byTooltip('打开声音').hitTestable(), findsOneWidget);
      expect(fixture.detailReads, 1);
      expect(fixture.credentialReads, 0);
      expect(fixture.videos, isEmpty);
      expect(fixture.closes, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'one pending detail read survives entering and exiting fullscreen',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    addTearDown(() {
      if (!response.isCompleted) response.complete(liveDTO());
    });
    final fixture = _WatchFixture(detail: (_) => response.future);
    await _mount(tester, fixture);
    expect(fixture.detailReads, 1);
    await _enterFullscreen(tester);
    expect(fixture.detailReads, 1);
    await _exitFullscreen(tester);
    expect(fixture.detailReads, 1);
    await _enterFullscreen(tester);
    await tester.binding.handlePopRoute();
    await _frames(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('退出全屏', skipOffstage: false), findsNothing);
    expect(find.text('全屏观看').hitTestable(), findsOneWidget);
    expect(fixture.detailReads, 1,
        reason: 'System back must preserve the same pending request too');
    response.complete(liveDTO());
    await _frames(tester);
    expect(find.text('直播准备中，请稍候…'), findsOneWidget);
    expect(fixture.credentialReads, 0);
    expect(fixture.videos, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting mute is applied before the first play in fullscreen',
      (tester) async {
    final fixture = _WatchFixture();
    await _mount(tester, fixture);
    await tester.tap(find.byTooltip('静音').hitTestable());
    await _frames(tester);
    await _enterFullscreen(tester);

    fixture.status = 'LIVE';
    fixture.version = 2;
    await tester.tap(find.text('刷新状态').hitTestable());
    await _frames(tester);
    expect(fixture.videos, hasLength(1));
    expect(fixture.videos.single.volumesAtPlay, [0]);
    expect(fixture.videos.single.plays, 1);
    expect(fixture.videos.single.pauses, 0);
    expect(find.byTooltip('打开声音').hitTestable(), findsOneWidget);
    expect(find.byType(VideoPlayer), findsOneWidget);
    await _exitFullscreen(tester);
    expect(fixture.videos, hasLength(1));
    expect(fixture.videos.single.plays, 1);
    expect(fixture.videos.single.pauses, 0);
    expect(find.byTooltip('打开声音').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'live fullscreen and casting preserve one decoder and mute choice',
      (tester) async {
    final fixture = _WatchFixture(initialStatus: LiveStatus.live);
    await _mount(tester, fixture);
    expect(fixture.videos, hasLength(1));
    final video = fixture.videos.single;
    await _enterFullscreen(tester);
    await tester.tap(find.byTooltip('静音').hitTestable());
    await _frames(tester);
    expect(video.value.volume, 0);
    await tester.tap(find.byTooltip('投屏').hitTestable());
    await _frames(tester);
    expect(casts, 1);
    await _exitFullscreen(tester);
    expect(fixture.videos.single, same(video));
    expect(video.plays, 1);
    expect(video.pauses, 0);
    expect(video.closes, 0);
    expect(fixture.credentialReads, 1);
    expect(find.byTooltip('打开声音').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final state in ['ended', 'live']) {
    testWidgets(
        '${state == 'ended' ? 'ended waiting session' : 'replaced session'} removes only its covered fullscreen route',
        (tester) async {
      final fixture = _WatchFixture();
      await _mount(tester, fixture);
      await _enterFullscreen(tester);
      unawaited(fixture.navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('其它页面保持打开'))))));
      await _frames(tester);
      fixture.publish(state, sessionID: state == 'ended' ? 'live-1' : 'live-2');
      await _frames(tester);
      expect(find.text('其它页面保持打开').hitTestable(), findsOneWidget);
      expect(find.text('退出全屏', skipOffstage: false), findsNothing);
      fixture.navigator.currentState!.pop();
      await _frames(tester);
      expect(fixture.navigator.currentState!.canPop(), isFalse);
      expect(find.textContaining(state == 'ended' ? '直播已结束' : '场次已变化'),
          findsOneWidget);
      expect(fixture.detailReads, 1,
          reason: 'A definitive group summary must not reload the old scene');
      expect(fixture.credentialReads, 0);
      expect(fixture.videos, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('background discards pending live detail and resumes one read',
      (tester) async {
    final first = Completer<Map<String, dynamic>>();
    addTearDown(() {
      if (!first.isCompleted) first.complete(liveDTO());
    });
    final fixture = _WatchFixture(
      detail: (number) => number == 1 ? first.future : liveDTO(),
    );
    await _mount(tester, fixture);
    await _enterFullscreen(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _frames(tester);
    first.complete(liveDTO(status: 'LIVE', version: 2));
    await _frames(tester);
    expect(fixture.credentialReads, 0);
    expect(fixture.videos, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(fixture.detailReads, 2);
    expect(find.text('直播准备中，请稍候…').hitTestable(), findsOneWidget);
    expect(fixture.credentialReads, 0);
    expect(fixture.videos, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'waiting fullscreen follows rotation and returns to the inline view',
      (tester) async {
    final fixture = _WatchFixture();
    await _mount(tester, fixture);
    await _enterFullscreen(tester);
    tester.view.physicalSize = const Size(812, 390);
    await _frames(tester);
    expect(find.text('直播准备中，请稍候…').hitTestable(), findsOneWidget);
    expect(find.text('退出全屏').hitTestable(), findsOneWidget);
    expect(find.byTooltip('投屏').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 812);
    await _frames(tester);
    await _exitFullscreen(tester);
    expect(find.text('全屏观看').hitTestable(), findsOneWidget);
    expect(fixture.detailReads, 1);
    expect(fixture.videos, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('covering a waiting fullscreen cancels detail before autoplay',
      (tester) async {
    final first = Completer<Map<String, dynamic>>();
    addTearDown(() {
      if (!first.isCompleted) first.complete(liveDTO());
    });
    final fixture = _WatchFixture(
      detail: (number) => number == 1 ? first.future : liveDTO(),
    );
    await _mount(tester, fixture);
    await _enterFullscreen(tester);
    unawaited(fixture.navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('覆盖等待全屏'))))));
    await _frames(tester);
    first.complete(liveDTO(status: 'LIVE', version: 2));
    await _frames(tester);
    expect(find.text('覆盖等待全屏').hitTestable(), findsOneWidget);
    expect(fixture.credentialReads, 0);
    expect(fixture.videos, isEmpty);
    fixture.navigator.currentState!.pop();
    await _frames(tester);
    expect(fixture.detailReads, 2);
    expect(find.text('退出全屏').hitTestable(), findsOneWidget);
    expect(find.text('直播准备中，请稍候…').hitTestable(), findsOneWidget);
    expect(fixture.videos, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing fullscreen rejects a late detail response',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    addTearDown(() {
      if (!response.isCompleted) response.complete(liveDTO());
    });
    final fixture = _WatchFixture(detail: (_) => response.future);
    await _mount(tester, fixture);
    await _enterFullscreen(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    response.complete(liveDTO(status: 'LIVE', version: 2));
    await _frames(tester);
    expect(fixture.credentialReads, 0);
    expect(fixture.videos, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
