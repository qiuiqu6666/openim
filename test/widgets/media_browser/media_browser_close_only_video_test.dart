import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/native_media_video.dart';
import 'package:openim_common/src/widgets/media_browser/media_thumbnail_hero.dart';
import 'package:openim_common/src/widgets/media_browser/media_video_hero.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  final volumes = <double>[];
  final looping = <bool>[];
  bool played = false;
  bool disposed = false;
  int created = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      ++created;

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

  for (final exit in ['back', 'drag', 'interrupted']) {
    testWidgets(
        'video return never squeezes controls into the thumbnail / $exit',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final slideKey = GlobalKey<ExtendedImageSlidePageState>();
      late BuildContext routeContext;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              brightness: exit == 'drag' ? Brightness.dark : Brightness.light),
          home: Scaffold(body: Builder(builder: (context) {
            routeContext = context;
            return Align(
                alignment: Alignment.topLeft,
                child: MediaThumbnailHero(
                  tag: 'video',
                  child: SizedBox(
                      width: exit == 'drag' ? 80 : 120,
                      height: 240,
                      child: const ColoredBox(color: Color(0xff80ffdb))),
                ));
          }))));
      Navigator.of(routeContext).push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        opaque: false,
        pageBuilder: (_, __, ___) => Scaffold(
            body: ExtendedImageSlidePage(
                key: slideKey,
                slideType: SlideType.wholePage,
                child: MediaVideoHero(
                  tag: 'video',
                  child: Material(
                      child: NativeMediaVideo(
                    file: File(
                        'openim_common/assets/images/ic_archive_99chat.png'),
                    autoPlay: true,
                    muted: false,
                  )),
                ))),
      ));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      await tester.pump();
      final player = find.byType(NativeMediaVideo, skipOffstage: false);
      final originalPlayer = tester.state(player);
      for (var frame = 0; frame < (exit == 'interrupted' ? 6 : 21); frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull,
            reason: 'No overflow on opening frame $frame');
        expect(tester.state(player), same(originalPlayer));
      }
      if (exit != 'interrupted') expect(find.byType(Slider), findsOneWidget);
      final createdBeforeReturn = platform.created;
      expect(createdBeforeReturn, 1,
          reason: 'Opening only initializes one player');
      if (exit == 'drag') {
        final slide = slideKey.currentState!;
        slide.slide(Offset(0, slide.pageSize.height / 2));
        await tester.pump();
        slide.endSlide(ScaleEndDetails());
      } else {
        Navigator.of(routeContext).pop();
      }
      await tester.pump();
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      for (var frame = 0; frame < 21; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull,
            reason: 'No overflow on return frame $frame');
        expect(find.byType(Slider), findsNothing,
            reason: 'Player controls stay out of the flight');
        if (player.evaluate().isNotEmpty) {
          expect(tester.state(player), same(originalPlayer));
        }
      }
      expect(platform.created, createdBeforeReturn,
          reason: 'A flight must not create another player');
      expect(find.byType(NativeMediaVideo), findsNothing);
      expect(find.byType(Slider), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

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
