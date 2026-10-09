import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/moments/moments_media_preview.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../support/performance/render_test_fakes.dart';

class _Video extends VideoPlayerPlatform {
  DataSource? source;
  int plays = 0;
  bool released = false;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) => Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 2),
      size: const Size(160, 240)));
  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setVolume(int id, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> play(int id) async {
    plays++;
  }

  @override
  Future<void> pause(int id) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox(key: ValueKey('protected-moment-video'));
  @override
  Future<void> dispose(int id) async {
    released = true;
  }
}

class _Api extends RenderTestApi {
  @override
  Map<String, String> get mediaHeaders => {'token': 'synthetic-moment-token'};
  @override
  String mediaUrl(String path) => 'http://129.226.192.93:10008$path';
}

const _post =
    MomentPost(momentId: 'video-post', author: renderTestUser, mediaList: [
  MomentMedia(
      mediaId: 'video-media',
      type: 'VIDEO',
      contentPath: '/moments/media/video-media/content')
]);

void main() {
  tearDown(Get.reset);
  for (final revoke in ['session', 'post', 'background']) {
    testWidgets('legacy video streams with owner token and stops on $revoke',
        (tester) async {
      final previous = VideoPlayerPlatform.instance;
      final video = _Video();
      VideoPlayerPlatform.instance = video;
      addTearDown(() => VideoPlayerPlatform.instance = previous);
      final api = _Api();
      final repository = renderTestRepository(api)..applyPost(_post);
      addTearDown(repository.dispose);
      await tester.pumpWidget(renderTestHost(MomentsMediaPreview(
          repository: repository, post: _post, initialIndex: 0)));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('protected-moment-video')), findsOneWidget);
      expect(video.source!.sourceType, DataSourceType.network);
      expect(video.source!.httpHeaders, {'token': 'synthetic-moment-token'});
      expect(video.source!.uri,
          'http://129.226.192.93:10008/moments/media/video-media/content');
      expect(video.plays, 0);
      expect(api.mediaCalls, isEmpty,
          reason: 'Video must not download into shared image or disk caches');
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(video.plays, 1);
      switch (revoke) {
        case 'session':
          repository.resetSession();
        case 'post':
          repository.applyPost(const MomentPost(
              momentId: 'video-post', author: renderTestUser, version: 2));
        case 'background':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      expect(
          find.byKey(const ValueKey('protected-moment-video')), findsNothing);
      expect(video.released, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(tester.takeException(), isNull);
    });
  }
}
