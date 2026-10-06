import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/native_media_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  final volumes = <double>[];
  final looping = <bool>[];
  bool played = false;
  bool disposed = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 2),
      size: const Size(160, 240)));

  @override
  Future<void> setLooping(int playerId, bool value) async => looping.add(value);

  @override
  Future<void> setVolume(int playerId, double value) async =>
      volumes.add(value);

  @override
  Future<void> play(int playerId) async => played = true;

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox(key: ValueKey('fake-video-view'));

  @override
  Future<void> dispose(int playerId) async => disposed = true;
}

Future<void> _mount(WidgetTester tester, {required bool closeOnly}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NativeMediaVideo(
        file: File('openim_common/assets/images/ic_archive_99chat.png'),
        autoPlay: true,
        muted: closeOnly,
        showControls: !closeOnly,
        looping: closeOnly,
      ),
    ),
  ));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
}

void main() {
  late VideoPlayerPlatform previous;
  late _VideoPlatform platform;
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = previous);

  testWidgets('sticker video loops silently with no player controls',
      (tester) async {
    await _mount(tester, closeOnly: true);
    expect(find.byKey(const ValueKey('fake-video-view')), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(platform.played, isTrue);
    expect(platform.volumes.last, 0);
    expect(platform.looping.last, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(platform.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('regular video retains sound and player controls',
      (tester) async {
    await _mount(tester, closeOnly: false);
    expect(find.byKey(const ValueKey('fake-video-view')), findsOneWidget);
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(platform.volumes.last, 1);
    expect(platform.looping.last, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
