import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/playback/live_playback_controller.dart';
import 'live_test_support.dart';

const _info = LivePlayInfo(
    id: 'live-1',
    roomName: '直播间',
    protocol: 'hls',
    playURL: 'https://video.test/1.m3u8');

class _VolumeVideo extends TestLiveVideo {
  _VolumeVideo(super.uri, {super.initialized});
  final volumes = <double>[];
  final playVolumes = <double>[];
  Future<void> Function(double)? writeVolume;
  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    await writeVolume?.call(volume);
    await super.setVolume(volume);
  }

  @override
  Future<void> play() async {
    playVolumes.add(value.volume);
    await super.play();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initial mute choice is applied before the first audible frame',
      () async {
    final video = _VolumeVideo(_info.supportedSources.first);
    final state = LivePlaybackController(_info,
        muted: true, sessionCurrent: () => true, factory: (_) => video);
    addTearDown(state.dispose);
    await state.open();
    expect(state.muted, isTrue);
    expect(video.playVolumes, [0]);
    expect(state.muteError, isNull);
  });

  test('mute before a player exists survives delayed initialization', () async {
    final initialized = Completer<void>();
    final video =
        _VolumeVideo(_info.supportedSources.first, initialized: initialized);
    final state = LivePlaybackController(_info,
        sessionCurrent: () => true, factory: (_) => video);
    addTearDown(state.dispose);
    await state.setMuted(true);
    final opening = state.open();
    await Future<void>.delayed(Duration.zero);
    expect(video.volumes, isEmpty);
    await state.setMuted(false);
    await state.setMuted(true);
    initialized.complete();
    await opening;
    expect(video.volumes, [0]);
    expect(video.playVolumes, [0]);
  });

  test('rapid mute taps serialize native writes and keep the latest choice',
      () async {
    final firstWrite = Completer<void>();
    final video = _VolumeVideo(_info.supportedSources.first);
    final state = LivePlaybackController(_info,
        sessionCurrent: () => true, factory: (_) => video);
    addTearDown(state.dispose);
    await state.open();
    video.writeVolume =
        (volume) => volume == 0 ? firstWrite.future : Future<void>.value();
    final muting = state.toggleMute();
    expect(state.muted, isTrue);
    final unmuting = state.toggleMute();
    expect(state.muted, isFalse);
    expect(video.volumes, [1, 0]);
    firstWrite.complete();
    await Future.wait([muting, unmuting]);
    expect(video.volumes, [1, 0, 1]);
    expect(video.value.volume, 1);
    expect(state.muteError, isNull);
  });

  test('native mute failure reports an error and the same choice can retry',
      () async {
    final video = _VolumeVideo(_info.supportedSources.first);
    final state = LivePlaybackController(_info,
        sessionCurrent: () => true, factory: (_) => video);
    addTearDown(state.dispose);
    await state.open();
    video.writeVolume = (_) => Future.error(StateError('native volume failed'));
    await state.setMuted(true);
    expect(state.muted, isTrue);
    expect(state.muteError.toString(), contains('声音设置失败'));
    expect(state.error, isNull);
    expect(video.plays, 1);
    video.writeVolume = null;
    await state.setMuted(true);
    expect(state.muteError, isNull);
    expect(video.value.volume, 0);
  });

  test(
      'an obsolete write failure does not replace the latest successful choice',
      () async {
    final firstWrite = Completer<void>();
    final video = _VolumeVideo(_info.supportedSources.first);
    final state = LivePlaybackController(_info,
        sessionCurrent: () => true, factory: (_) => video);
    addTearDown(state.dispose);
    await state.open();
    video.writeVolume =
        (volume) => volume == 0 ? firstWrite.future : Future<void>.value();
    final muting = state.setMuted(true);
    final unmuting = state.setMuted(false);
    firstWrite.completeError(StateError('old failure'));
    await Future.wait([muting, unmuting]);
    expect(state.muteError, isNull);
    expect(state.muted, isFalse);
    expect(video.value.volume, 1);
  });

  test('credential replacement retains mute and ignores the old decoder reply',
      () async {
    final oldWrite = Completer<void>();
    final videos = <_VolumeVideo>[];
    final state = LivePlaybackController(_info,
        sessionCurrent: () => true,
        factory: (source) {
          final video = _VolumeVideo(source);
          videos.add(video);
          return video;
        });
    addTearDown(state.dispose);
    await state.open();
    videos.first.writeVolume = (_) => oldWrite.future;
    final muting = state.setMuted(true);
    await state.updateCredentials(const LivePlayInfo(
        id: 'live-1',
        roomName: '直播间',
        protocol: 'hls',
        playURL: 'https://video.test/renewed.m3u8'));
    expect(videos.length, 2);
    expect(videos.last.playVolumes, [0]);
    oldWrite.completeError(StateError('closed native player'));
    await muting;
    expect(state.muteError, isNull);
    expect(state.muted, isTrue);
    expect(state.player, same(videos.last));
  });

  test('a switched account ignores an in-flight mute reply and new clicks',
      () async {
    var current = true;
    final reply = Completer<void>();
    final video = _VolumeVideo(_info.supportedSources.first);
    final state = LivePlaybackController(_info,
        sessionCurrent: () => current, factory: (_) => video);
    addTearDown(state.dispose);
    await state.open();
    var changes = 0;
    state.addListener(() => changes++);
    video.writeVolume = (_) => reply.future;
    final muting = state.setMuted(true);
    final beforeReply = changes;
    current = false;
    reply.completeError(StateError('old account'));
    await muting;
    await state.setMuted(false);
    expect(changes, beforeReply);
    expect(state.muteError, isNull);
    expect(video.volumes, [1, 0]);
  });

  test('fullscreen lease keeps the shared mute setting and the native player',
      () async {
    final videos = <_VolumeVideo>[];
    _VolumeVideo create(Uri source) {
      final video = _VolumeVideo(source);
      videos.add(video);
      return video;
    }

    final inline = LivePlaybackOwner.acquire('self', _info, () => true,
        muted: true, factory: create);
    addTearDown(() => LivePlaybackOwner.release(inline));
    await Future<void>.delayed(Duration.zero);
    final fullscreen =
        LivePlaybackOwner.acquire('self', _info, () => true, factory: create);
    addTearDown(() => LivePlaybackOwner.release(fullscreen));
    expect(fullscreen, same(inline));
    expect(fullscreen.muted, isTrue);
    expect(videos.single.playVolumes, [0]);
    await fullscreen.setMuted(false);
    expect(inline.muted, isFalse);
    expect(videos.single.value.volume, 1);
  });

  test('an initial mute failure never starts audible playback', () async {
    final video = _VolumeVideo(_info.supportedSources.first)
      ..writeVolume = (_) => Future.error(StateError('mute unavailable'));
    final state = LivePlaybackController(_info,
        muted: true, sessionCurrent: () => true, factory: (_) => video);
    addTearDown(state.dispose);
    await state.open();
    expect(video.plays, 0);
    expect(state.muteError, isNotNull);
    expect(state.error.toString(), contains('声音设置失败'));
  });
}
