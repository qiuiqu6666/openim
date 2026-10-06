import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/chat/stickers/sticker_video_bubble.dart';
import 'package:openim/pages/chat/stickers/sticker_video_message.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _Player {
  _Player(this.source);
  final DataSource source;
  final events = StreamController<VideoEvent>.broadcast();
  final playVolumes = <double>[];
  final playLoops = <bool>[];
  bool playing = false;
  bool disposed = false;
  bool looping = false;
  double volume = 1;
  int pauses = 0;
}

class _VideoPlatform extends VideoPlayerPlatform {
  final players = <int, _Player>{};
  bool holdInitialization = false;
  bool failInitialization = false;
  Size initializedSize = const Size(160, 160);

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = players.length + 1;
    players[id] = _Player(options.dataSource);
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (!holdInitialization) {
      scheduleMicrotask(() {
        if (failInitialization) {
          players[playerId]!.events.addError(
              PlatformException(code: 'video-failed', message: 'Unavailable'));
        } else {
          initialize(playerId);
        }
      });
    }
    return players[playerId]!.events.stream;
  }

  void initialize(int playerId) => players[playerId]!.events.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 2),
      size: initializedSize));

  @override
  Future<void> setLooping(int playerId, bool value) async =>
      players[playerId]!.looping = value;

  @override
  Future<void> setVolume(int playerId, double value) async =>
      players[playerId]!.volume = value;

  @override
  Future<void> play(int playerId) async {
    final player = players[playerId]!;
    player.playing = true;
    player.playVolumes.add(player.volume);
    player.playLoops.add(player.looping);
  }

  @override
  Future<void> pause(int playerId) async {
    final player = players[playerId]!;
    player.playing = false;
    player.pauses++;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
      key: ValueKey('video-view-${options.playerId}'),
      color: Colors.blue,
      child: const SizedBox.expand());

  @override
  Future<void> dispose(int playerId) async {
    final player = players[playerId]!;
    player.playing = false;
    player.disposed = true;
    await player.events.close();
  }
}

Message _message(String id, {Size size = const Size(160, 160)}) {
  final message = Message.fromJson({
    'clientMsgID': id,
    'contentType': MessageType.video,
    'sendID': 'peer',
    'recvID': 'me',
    'sessionType': ConversationType.single,
    'sendTime': 1700000000000,
    'isRead': true,
    'status': MessageStatus.succeeded,
    'videoElem': {
      'videoUrl': 'https://stickers.test/$id.mp4',
      'snapshotWidth': size.width.toInt(),
      'snapshotHeight': size.height.toInt(),
      'duration': 2,
    },
  });
  markStickerVideoMessage(message);
  return message;
}

class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

Future<void> _mount(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light,
    NavigatorObserver? observer}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      navigatorObservers: [if (observer != null) observer],
      home: Scaffold(body: child),
    ),
  ));
  await _flush(tester);
}

Future<void> _flush(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
}

Widget _clippedBubble(ValueNotifier<double> visibleHeight, Message message) =>
    Align(
      alignment: Alignment.topLeft,
      child: ValueListenableBuilder<double>(
        valueListenable: visibleHeight,
        child: StickerVideoBubble(message: message),
        builder: (_, height, child) => SizedBox(
          width: 160,
          height: height,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 160,
              maxWidth: 160,
              minHeight: 160,
              maxHeight: 160,
              child: child,
            ),
          ),
        ),
      ),
    );

void _expectNoPlaybackButtons() {
  expect(find.byIcon(Icons.play_circle_fill), findsNothing);
  expect(find.byIcon(Icons.play_arrow), findsNothing);
  expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  expect(find.byType(IconButton), findsNothing);
}

void _expectSilentlyLooping(_Player player) {
  expect(player.playing, isTrue);
  expect(player.disposed, isFalse);
  expect(player.playVolumes, isNotEmpty);
  expect(player.playVolumes, everyElement(0));
  expect(player.playLoops, everyElement(isTrue));
  expect(player.volume, 0);
  expect(player.looping, isTrue);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flush(tester);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VideoPlayerPlatform previous;
  late _VideoPlatform platform;
  late Duration previousVisibilityInterval;
  setUp(() {
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
    previous = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    previousVisibilityInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    VideoPlayerPlatform.instance = previous;
    VisibilityDetectorController.instance.updateInterval =
        previousVisibilityInterval;
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'video stickers use 99chat image frames and radius in $brightness',
        (tester) async {
      const shapes = <(Size, Size, BoxFit)>[
        (Size(320, 160), Size(144, 72), BoxFit.contain),
        (Size(160, 320), Size(92, 160), BoxFit.cover),
        (Size(300, 300), Size(144, 144), BoxFit.contain),
      ];
      for (final shape in shapes) {
        platform.initializedSize = shape.$1;
        await _mount(
            tester,
            Align(
                alignment: Alignment.topLeft,
                child: StickerVideoBubble(
                    message: _message('frame-${shape.$1}', size: shape.$1))),
            brightness: brightness);
        final clip = find.descendant(
            of: find.byType(StickerVideoBubble),
            matching: find.byType(ClipRRect));
        expect(tester.getSize(clip), shape.$2);
        expect(tester.widget<ClipRRect>(clip).borderRadius,
            BorderRadius.circular(6));
        expect(tester.widget<FittedBox>(find.byType(FittedBox)).fit, shape.$3);
        _expectSilentlyLooping(platform.players.values.last);
        _expectNoPlaybackButtons();
        await _dispose(tester);
      }
    });

    testWidgets('all visible video stickers autoplay silently in $brightness',
        (tester) async {
      await _mount(
          tester,
          Column(children: [
            StickerVideoBubble(message: _message('one')),
            StickerVideoBubble(message: _message('two')),
            StickerVideoBubble(message: _message('three')),
          ]),
          brightness: brightness);
      expect(platform.players, hasLength(3));
      expect(find.byType(VideoPlayer), findsNWidgets(3));
      _expectNoPlaybackButtons();
      for (final player in platform.players.values) {
        _expectSilentlyLooping(player);
      }
      await _dispose(tester);
      expect(platform.players.values.map((player) => player.disposed),
          everyElement(isTrue));
    });
  }

  testWidgets(
      'sent and received video stickers overlay time and preserve preview taps',
      (tester) async {
    final observer = _RouteObserver();
    final sent = _message('sent-row', size: const Size(320, 160))
      ..sendID = 'me';
    final received = _message('received-row', size: const Size(320, 160));
    await _mount(
        tester,
        Column(children: [
          for (final message in [sent, received])
            ChatItemView(
              message: message,
              isStickerMedia: true,
              showLeftNickname: false,
              onTapUserProfile: (_) {},
              mediaItemBuilder: (_, message) =>
                  StickerVideoBubble(message: message),
            ),
        ]),
        observer: observer);
    for (final message in [sent, received]) {
      final row = find.byWidgetPredicate((widget) =>
          widget is ChatItemView && identical(widget.message, message));
      final containerFinder =
          find.descendant(of: row, matching: find.byType(ChatItemContainer));
      final container = tester.widget<ChatItemContainer>(containerFinder);
      expect(container.stickerMedia, isTrue);
      expect(container.bareMedia, isTrue);
      expect(container.mediaOverlay, isTrue);
      final bubble =
          find.descendant(of: row, matching: find.byType(StickerVideoBubble));
      final frame =
          find.descendant(of: bubble, matching: find.byType(ClipRRect));
      expect(tester.getSize(frame), const Size(144, 72));
      final metadata = find.descendant(
          of: row,
          matching: find.byWidgetPredicate((widget) =>
              widget is Row &&
              widget.mainAxisSize == MainAxisSize.min &&
              widget.children.any((child) => child is Text)));
      final metadataRect = tester.getRect(metadata);
      final frameRect = tester.getRect(frame);
      expect(metadataRect.left, greaterThanOrEqualTo(frameRect.left));
      expect(metadataRect.top, greaterThanOrEqualTo(frameRect.top));
      expect(metadataRect.right, lessThanOrEqualTo(frameRect.right));
      expect(metadataRect.bottom, lessThanOrEqualTo(frameRect.bottom));
      final time = tester.widget<Text>(
          find.descendant(of: metadata, matching: find.byType(Text)));
      expect(time.style?.color, Colors.white);
      final containerRect = tester.getRect(containerFinder);
      expect(containerRect.left, 16);
      expect(containerRect.right, 359);
      expect(
          tester.getRect(row).bottom - containerRect.bottom, closeTo(12, 0.01));
    }
    expect(find.byType(ChatReadReceiptIcon), findsOneWidget);
    for (final player in platform.players.values) {
      _expectSilentlyLooping(player);
    }
    final receipt = find.byType(ChatReadReceiptIcon);
    expect(tester.widget<ChatReadReceiptIcon>(receipt).color, Colors.white);
    await tester.tapAt(tester.getRect(receipt).center);
    expect(observer.routes, hasLength(2));
    final preview = observer.routes.last as PageRouteBuilder<void>;
    final context = tester.element(find.byType(StickerVideoBubble).first);
    final browser = preview.pageBuilder(
        context,
        const AlwaysStoppedAnimation(1.0),
        const AlwaysStoppedAnimation(1.0)) as MediaBrowser;
    expect(browser.closeOnly, isTrue);
    expect(browser.sources.single.isVideo, isTrue);
    expect(browser.sources.single.url, sent.videoElem!.videoUrl);
    // Check the actual route before building the Windows MediaKit backend;
    // the fake video platform represents the mobile inline player.
    Navigator.of(context, rootNavigator: true).pop();
    await _flush(tester);
    expect(platform.players[1]!.disposed, isTrue);
    for (final player
        in platform.players.values.where((player) => !player.disposed)) {
      _expectSilentlyLooping(player);
    }
    await _dispose(tester);
  });

  testWidgets('initializing and failed stickers never show a play button',
      (tester) async {
    platform.holdInitialization = true;
    await _mount(tester, StickerVideoBubble(message: _message('loading')));
    expect(platform.players, hasLength(1));
    expect(platform.players[1]!.playing, isFalse);
    expect(find.byType(VideoPlayer), findsNothing);
    _expectNoPlaybackButtons();
    platform.players[1]!.events.addError(
        PlatformException(code: 'video-failed', message: 'Unavailable'));
    await _flush(tester);
    expect(platform.players[1]!.disposed, isTrue);
    expect(find.byType(VideoPlayer), findsNothing);
    _expectNoPlaybackButtons();
    await _dispose(tester);
  });

  testWidgets('one percent visibility starts and zero releases then restarts',
      (tester) async {
    final height = ValueNotifier<double>(1.6);
    addTearDown(height.dispose);
    await _mount(tester, _clippedBubble(height, _message('partial')));
    expect(platform.players, hasLength(1));
    _expectSilentlyLooping(platform.players[1]!);
    height.value = 0;
    await _flush(tester);
    expect(platform.players[1]!.disposed, isTrue);
    expect(platform.players[1]!.playing, isFalse);
    height.value = 1.6;
    await _flush(tester);
    expect(platform.players, hasLength(2));
    _expectSilentlyLooping(platform.players[2]!);
    _expectNoPlaybackButtons();
    await _dispose(tester);
    expect(platform.players[2]!.disposed, isTrue);
  });

  testWidgets('background pauses all visible stickers and foreground resumes',
      (tester) async {
    await _mount(
        tester,
        Column(children: [
          StickerVideoBubble(message: _message('one')),
          StickerVideoBubble(message: _message('two')),
        ]));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _flush(tester);
    for (final player in platform.players.values) {
      expect(player.playing, isFalse);
      expect(player.pauses, greaterThan(0));
      expect(player.disposed, isFalse);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(platform.players, hasLength(2));
    for (final player in platform.players.values) {
      _expectSilentlyLooping(player);
    }
    await _dispose(tester);
  });

  testWidgets('late initialization after scrolling away is released unplayed',
      (tester) async {
    platform.holdInitialization = true;
    final height = ValueNotifier<double>(160);
    addTearDown(height.dispose);
    await _mount(tester, _clippedBubble(height, _message('late')));
    expect(platform.players, hasLength(1));
    height.value = 0;
    await _flush(tester);
    platform.initialize(1);
    await _flush(tester);
    expect(platform.players[1]!.disposed, isTrue);
    expect(platform.players[1]!.playVolumes, isEmpty);
    platform.holdInitialization = false;
    height.value = 160;
    await _flush(tester);
    expect(platform.players, hasLength(2));
    _expectSilentlyLooping(platform.players[2]!);
    await _dispose(tester);
  });

  testWidgets('initialization while backgrounded resumes with a fresh player',
      (tester) async {
    platform.holdInitialization = true;
    await _mount(tester, StickerVideoBubble(message: _message('background')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _flush(tester);
    platform.initialize(1);
    await _flush(tester);
    expect(platform.players[1]!.disposed, isTrue);
    expect(platform.players[1]!.playVolumes, isEmpty);
    platform.holdInitialization = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(platform.players, hasLength(2));
    _expectSilentlyLooping(platform.players[2]!);
    await _dispose(tester);
  });

  testWidgets('a transparent route cover stops all stickers until returning',
      (tester) async {
    await _mount(
        tester,
        Column(children: [
          StickerVideoBubble(message: _message('covered-one')),
          StickerVideoBubble(message: _message('covered-two')),
        ]));
    final navigator =
        Navigator.of(tester.element(find.byType(StickerVideoBubble).first));
    unawaited(navigator.push<void>(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => const SizedBox.shrink())));
    await _flush(tester);
    expect(platform.players, hasLength(2));
    for (final player in platform.players.values) {
      expect(player.disposed, isTrue);
      expect(player.playing, isFalse);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(platform.players, hasLength(2),
        reason: 'Foregrounding must not restart a covered chat route.');
    navigator.pop();
    await _flush(tester);
    expect(platform.players, hasLength(4));
    _expectSilentlyLooping(platform.players[3]!);
    _expectSilentlyLooping(platform.players[4]!);
    await _dispose(tester);
  });

  testWidgets(
      'an in-place URL update on the same message retries a failed video',
      (tester) async {
    platform.failInitialization = true;
    final message = _message('same-id');
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    await _mount(
        tester,
        ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (_, __, ___) => StickerVideoBubble(message: message)));
    expect(platform.players, hasLength(1));
    expect(platform.players[1]!.disposed, isTrue);
    expect(platform.players[1]!.playVolumes, isEmpty);
    _expectNoPlaybackButtons();
    platform.failInitialization = false;
    const replacementUrl = 'https://stickers.test/reuploaded.mp4';
    message.videoElem!.videoUrl = replacementUrl;
    revision.value++;
    await _flush(tester);
    expect(message.clientMsgID, 'same-id');
    expect(platform.players, hasLength(2));
    expect(platform.players[2]!.source.uri, replacementUrl);
    _expectSilentlyLooping(platform.players[2]!);
    _expectNoPlaybackButtons();
    await _dispose(tester);
  });
}
