import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/playback/live_playback_controller.dart';
import 'package:openim/pages/group_features/live/playback/live_source_policy.dart';
import 'live_test_support.dart';

const info = LivePlayInfo(
    id: 'live',
    roomName: '',
    protocol: 'hls',
    playURL: 'https://video.test/live.m3u8?signature=hls',
    flvURL: 'https://video.test/live.flv?signature=flv');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only native iOS live playback opts into the local buffer policy', () {
    expect(livePlaybackHeaders(platform: TargetPlatform.iOS, web: false),
        {'X-99Chat-Local-Live-Playback': '1'});
    for (final platform in TargetPlatform.values) {
      expect(livePlaybackHeaders(platform: platform, web: true), isEmpty);
      if (platform != TargetPlatform.iOS) {
        expect(livePlaybackHeaders(platform: platform, web: false), isEmpty);
      }
    }
  });
  test('Android prefers signed FLV and retains HLS fallback', () {
    expect(
        livePlaybackSources(info, platform: TargetPlatform.android, web: false)
            .map((uri) => uri.toString()),
        [info.flvURL, info.playURL]);
  });
  test('iOS and browser retain backend order', () {
    for (final platform in TargetPlatform.values) {
      expect(livePlaybackSources(info, platform: platform, web: true),
          info.supportedSources);
      if (platform != TargetPlatform.android) {
        expect(livePlaybackSources(info, platform: platform, web: false),
            info.supportedSources);
      }
    }
  });
  test('HLS only remains playable and duplicate FLV is tried once', () {
    const hls = LivePlayInfo(
        id: 'h',
        roomName: '',
        protocol: 'hls',
        playURL: 'https://video.test/live.m3u8');
    expect(
        livePlaybackSources(hls, platform: TargetPlatform.android, web: false),
        hls.supportedSources);
    const duplicate = LivePlayInfo(
        id: 'f',
        roomName: '',
        protocol: 'flv',
        playURL: 'https://video.test/live.flv',
        flvURL: 'https://video.test/live.flv');
    expect(
        livePlaybackSources(duplicate,
            platform: TargetPlatform.android, web: false),
        hasLength(1));
  });
  test('native FLV failure falls back to HLS with a single active player',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final videos = <TestLiveVideo>[];
    final controller = LivePlaybackController(info,
        sessionCurrent: () => true,
        factory: (uri) {
          final video = TestLiveVideo(uri);
          videos.add(video);
          return video;
        });
    addTearDown(controller.dispose);
    await controller.open();
    expect(videos.single.dataSource, info.flvURL);
    videos.first.value =
        videos.first.value.copyWith(errorDescription: 'failed');
    await Future<void>.delayed(Duration.zero);
    expect(videos, hasLength(2));
    expect(videos.first.closes, 1);
    expect(videos.last.dataSource, info.playURL);
    expect(controller.ready, isTrue);
  });
}
