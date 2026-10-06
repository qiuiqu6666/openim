import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/models/live_summary_events.dart';
import 'package:openim/pages/group_features/live/playback/live_playback_controller.dart';
import 'package:openim/pages/group_features/live/playback/live_watch_state.dart';
import 'live_test_support.dart';

const _info = LivePlayInfo(
    id: 'live-1',
    roomName: '直播间',
    protocol: 'hls',
    playURL: 'https://video.test/1.m3u8',
    hlsURL: 'https://video.test/backup.m3u8');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'one native player lease is shared by inline and room, replacing another session',
      () async {
    final videos = <TestLiveVideo>[];
    TestLiveVideo create(Uri uri) {
      final video = TestLiveVideo(uri);
      videos.add(video);
      return video;
    }

    final first =
        LivePlaybackOwner.acquire('self', _info, () => true, factory: create);
    final fullscreen =
        LivePlaybackOwner.acquire('self', _info, () => true, factory: create);
    expect(identical(first, fullscreen), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(videos.length, 1);
    expect(first.ready, isTrue);
    await first.toggleMute();
    expect(videos.single.value.volume, 0);
    LivePlaybackOwner.release(fullscreen);
    expect(first.current, isTrue);
    final replacement = LivePlaybackOwner.acquire(
        'self',
        const LivePlayInfo(
            id: 'live-2',
            roomName: '',
            protocol: 'hls',
            playURL: 'https://video.test/2.m3u8'),
        () => true,
        factory: create);
    await Future<void>.delayed(Duration.zero);
    expect(first.current, isFalse);
    expect(videos.first.closes, 1);
    LivePlaybackOwner.release(first); // Old release cannot close the new lease.
    expect(replacement.current, isTrue);
    LivePlaybackOwner.release(replacement);
    expect(videos.last.closes, 1);
  });
  test('covered route suspends an initializing player before it can autoplay',
      () async {
    final gate = Completer<void>();
    final video =
        TestLiveVideo(_info.supportedSources.first, initialized: gate);
    final state = LivePlaybackController(_info,
        sessionCurrent: () => true, factory: (_) => video);
    final opening = state.open();
    await Future<void>.delayed(Duration.zero);
    await state.suspend();
    gate.complete();
    await opening;
    expect(video.plays, 0);
    expect(state.paused, isTrue);
    state.dispose();
  });
  test('late native initialization does not play in another account', () async {
    var current = true;
    final gate = Completer<void>();
    final video =
        TestLiveVideo(_info.supportedSources.first, initialized: gate);
    final state = LivePlaybackController(_info,
        sessionCurrent: () => current, factory: (_) => video);
    final opening = state.open();
    await Future<void>.delayed(Duration.zero);
    current = false;
    gate.complete();
    await opening;
    expect(video.plays, 0);
    state.dispose();
  });
  test(
      'waiting fetch merges requests, retries a failed detail, and does not request play credentials',
      () async {
    final reply = Completer<Map<String, dynamic>>();
    final entered = Completer<void>();
    var fail = true;
    final transport = LiveTransport((_) {
      if (!entered.isCompleted) entered.complete();
      return fail ? reply.future : liveDTO();
    });
    final state = LiveWatchState(liveContext(transport.api()), liveSession());
    final first = state.load(), second = state.load();
    expect(identical(first, second), isTrue);
    await entered.future;
    reply.completeError(StateError('network'));
    await first;
    expect(state.error, isNotNull);
    expect(state.loading, isFalse);
    fail = false;
    await state.load();
    expect(state.error, isNull);
    expect(state.playback, isNull);
    expect(transport.requests.length, 2);
    expect(
        transport.requests.every((r) => !r.path.contains('play-info')), isTrue);
    state.dispose();
  });
  test(
      'ended DTO closes immediately and stale LIVE cannot resurrect the session',
      () async {
    var version = 1;
    final videos = <TestLiveVideo>[];
    final transport = LiveTransport((r) => r.path.endsWith('play-info')
        ? {
            'liveSessionId': 'live-1',
            'roomName': '直播间',
            'protocol': 'hls',
            'playUrl': 'https://video.test/1.m3u8'
          }
        : liveDTO(status: 'LIVE', version: version));
    final state = LiveWatchState(
        liveContext(transport.api()), liveSession(status: LiveStatus.live),
        videoFactory: (uri) {
      final video = TestLiveVideo(uri);
      videos.add(video);
      return video;
    });
    await state.load();
    await Future<void>.delayed(Duration.zero);
    expect(videos.single.plays, 1);
    state.acceptSession(liveSession(status: LiveStatus.ended, version: 2));
    expect(state.playback, isNull);
    expect(videos.single.closes, 1);
    await state.load();
    expect(state.session.status, LiveStatus.ended);
    expect(state.playback, isNull);
    expect(transport.requests.where((r) => r.path.contains('play-info')).length,
        1);
    version = 2;
    await state.load();
    expect(state.session.status, LiveStatus.ended);
    state.dispose();
  });
  test(
      'late account detail stops before requesting play credentials and releases loading',
      () async {
    var current = true;
    final reply = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((_) => reply.future);
    final state = LiveWatchState(
        liveContext(transport.api(), current: () => current), liveSession());
    final loading = state.load();
    await Future<void>.delayed(Duration.zero);
    current = false;
    reply.complete(liveDTO(status: 'LIVE'));
    await loading;
    expect(state.loading, isFalse);
    expect(state.playback, isNull);
    expect(state.error, isNull);
    expect(transport.requests.length, 1);
    state.dispose();
  });
  for (final switched in [false, true]) {
    test(
        'SDK-only ${switched ? 'session change' : 'end'} stops playback without forging DTO version',
        () async {
      final videos = <TestLiveVideo>[];
      final transport =
          LiveTransport((request) => request.path.endsWith('/play-info')
              ? {
                  'liveSessionId': 'live-1',
                  'protocol': 'hls',
                  'playUrl': 'https://video.test/1.m3u8'
                }
              : liveDTO(status: 'LIVE', version: 1));
      final context = liveContext(transport.api());
      final state =
          LiveWatchState(context, liveSession(status: LiveStatus.live),
              videoFactory: (source) {
        final video = TestLiveVideo(source);
        videos.add(video);
        return video;
      });
      await state.load();
      await Future<void>.delayed(Duration.zero);
      final summaries = LiveSummaryEvents(context.features);
      final event = <String, dynamic>{
        'key': 'groupFeaturesChanged',
        'groupID': 'group#1',
        'data': {
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 100,
            'live': {
              'sessionID': switched ? 'live-2' : 'live-1',
              'status': switched ? 'live' : 'ended'
            }
          }
        }
      };
      state.acceptSummary(summaries.accept(event, 'group#1')!);
      expect(state.playback, isNull);
      expect(videos.single.closes, 1);
      expect(state.session.version, 1);
      // A stale HTTP detail still claiming LIVE cannot restore old credentials.
      await state.load();
      expect(state.playback, isNull);
      expect(state.error.toString(), contains(switched ? '场次已变化' : '直播已结束'));
      expect(state.session.version, 1);
      expect(
          transport.requests.where((r) => r.path.endsWith('/play-info')).length,
          1);
      expect(summaries.accept(event, 'group#1'), isNull);
      expect(
          summaries.accept({...event, 'groupID': 'other'}, 'group#1'), isNull);
      state.dispose();
    });
  }
}
