import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as media;
import 'package:media_kit_video/media_kit_video.dart' as media;
import 'package:video_player/video_player.dart';

/// The live-only engine boundary lets lifecycle tests run without native media.
abstract class LiveFlvEngine extends ValueNotifier<VideoPlayerValue> {
  LiveFlvEngine() : super(const VideoPlayerValue(duration: Duration.zero));
  media.VideoController? get videoController;
  Future<void> open(Uri source);
  Future<void> play();
  Future<void> pause();
  Future<void> setVolume(double volume);
  Future<void> close();
}

class MediaKitLiveFlvEngine extends LiveFlvEngine {
  MediaKitLiveFlvEngine() {
    media.MediaKit.ensureInitialized();
    _player = media.Player(
        configuration: const media.PlayerConfiguration(muted: true));
    videoController = media.VideoController(_player);
    // VideoController attaches native output after a frame, before media opens.
    WidgetsBinding.instance.ensureVisualUpdate();
    final stream = _player.stream;
    _subscriptions.addAll([
      stream.videoParams.listen((params) {
        final width = params.dw ?? params.w ?? 0;
        final height = params.dh ?? params.h ?? 0;
        if (width > 0 && height > 0) {
          _update(value.copyWith(
              isInitialized: true,
              size: Size(width.toDouble(), height.toDouble())));
        }
      }),
      stream.position
          .listen((position) => _update(value.copyWith(position: position))),
      stream.playing
          .listen((playing) => _update(value.copyWith(isPlaying: playing))),
      stream.buffering.listen(
          (buffering) => _update(value.copyWith(isBuffering: buffering))),
      stream.buffer.listen((end) => _update(value.copyWith(buffered: [
            if (end >= value.position) DurationRange(value.position, end),
          ]))),
      // Do not forward native errors: they can contain signed playback URLs.
      stream.error.listen((_) =>
          _update(value.copyWith(errorDescription: 'FLV playback failed'))),
      stream.completed.listen((completed) {
        if (completed) {
          _update(value.copyWith(errorDescription: 'Live stream ended'));
        }
      }),
    ]);
  }

  late final media.Player _player;
  @override
  late final media.VideoController videoController;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _closed = false;

  void _update(VideoPlayerValue next) {
    if (!_closed) value = next;
  }

  @override
  Future<void> open(Uri source) async {
    await _player.setVolume(0);
    if (_closed) return;
    // The owner applies the requested mute state before explicitly playing.
    await _player.open(media.Media(source.toString()), play: false);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0, 1) * 100);
    _update(value.copyWith(volume: volume.clamp(0, 1)));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await _player.dispose();
    } finally {
      super.dispose();
    }
  }
}
