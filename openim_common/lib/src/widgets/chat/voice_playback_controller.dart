import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:just_audio/just_audio.dart';

import '../../media/media_coordinator.dart';
import 'voice/voice_playback_log.dart';
import 'voice/voice_playback_source.dart';

/// Conversation-owned playback survives rebuilding or covering message widgets.
class VoicePlaybackController extends ChangeNotifier
    with WidgetsBindingObserver {
  VoicePlaybackController(
      {required this.messages,
      this.onPlayed,
      MediaCoordinator? coordinator,
      AudioPlayer Function()? playerFactory,
      Future<VoicePlaybackSource> Function(Message)? sourceLoader,
      this.prepareTimeout = const Duration(seconds: 20)})
      : coordinator = coordinator ?? MediaCoordinator.instance,
        _playerFactory = playerFactory ??
            (() => AudioPlayer(
                handleInterruptions: false,
                handleAudioSessionActivation: false,
                androidApplyAudioAttributes: false)),
        _sourceLoader = sourceLoader ?? VoicePlaybackSource.load {
    WidgetsBinding.instance.addObserver(this);
  }
  final Iterable<Message> Function() messages;
  final Future<void> Function(Message)? onPlayed;
  final MediaCoordinator coordinator;
  MediaLease? _lease;
  final AudioPlayer Function() _playerFactory;
  final Future<VoicePlaybackSource> Function(Message) _sourceLoader;
  final Duration prepareTimeout;
  AudioPlayer? _player;
  String? _loadedID;
  String? _resumeID;
  Duration _resumePosition = Duration.zero;
  Duration? _duration;
  Message? current;
  bool loading = false, playing = false, failed = false;
  bool _disposed = false;
  int _generation = 0;
  String _stage = 'idle';
  Stream<Duration>? get positionStream => _player?.positionStream;
  Duration durationFor(Message message) =>
      (current?.clientMsgID == message.clientMsgID ? _duration : null) ??
      Duration(seconds: message.soundElem?.duration ?? 0);

  Duration positionFor(Message message) {
    if (current?.clientMsgID != message.clientMsgID) return Duration.zero;
    return _player?.position ??
        (_resumeID == message.clientMsgID ? _resumePosition : Duration.zero);
  }

  Future<void> _seekChange = Future<void>.value();

  /// Seek the active player in place, or start this message at the chosen time.
  Future<void> seek(Message message, double fraction) async {
    if (_disposed || coordinator.recording || loading || !fraction.isFinite) {
      return;
    }
    final active = current?.clientMsgID == message.clientMsgID && playing;
    final player = active ? _player : null;
    final duration = durationFor(message);
    if (duration <= Duration.zero) return;
    final target = Duration(
        milliseconds:
            (duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round());
    if (player == null) {
      unawaited(_play(message, initialPosition: target));
      return;
    }
    final generation = _generation;
    final change = _seekChange.then((_) async {
      if (_disposed ||
          generation != _generation ||
          !identical(player, _player)) {
        return;
      }
      try {
        await player.seek(target);
      } catch (error) {
        VoicePlaybackLog.write('seek_failed',
            error: error, attempt: generation);
      }
      if (!_disposed && generation == _generation) notifyListeners();
    });
    _seekChange = change;
    await change;
  }

  bool get paused =>
      !playing &&
      !loading &&
      !failed &&
      current != null &&
      _resumeID == current!.clientMsgID;
  double _speed = 1.0;
  double get speed => _speed;
  Future<void> _speedChange = Future<void>.value();

  /// Change the existing player in place; never seek or reload the message.
  Future<void> cycleSpeed() {
    if (_disposed) return Future<void>.value();
    _speed = _speed == 1.0 ? 2.0 : 1.0;
    final requested = _speed;
    final player = _player;
    final lease = _lease;
    notifyListeners();
    final change = _speedChange.then((_) async {
      if (_disposed ||
          player == null ||
          !identical(player, _player) ||
          lease?.valid != true) {
        return;
      }
      try {
        await player.setSpeed(requested);
      } catch (error) {
        if (!_disposed && identical(player, _player) && _speed == requested) {
          _speed = player.speed;
          notifyListeners();
        }
        rethrow;
      }
    });
    _speedChange = change.catchError((Object _) {});
    return change;
  }

  static Message? nextMessage(Iterable<Message> messages, Message current) {
    final queue = messages.where((m) => m.soundElem != null).toList()
      ..sort((a, b) {
        final time = (a.sendTime ?? 0).compareTo(b.sendTime ?? 0);
        return time != 0 ? time : (a.seq ?? 0).compareTo(b.seq ?? 0);
      });
    final index = queue.indexWhere((m) => m.clientMsgID == current.clientMsgID);
    return index >= 0 && index + 1 < queue.length ? queue[index + 1] : null;
  }

  Future<void> toggle(Message message) async {
    if (coordinator.recording) return;
    if (current?.clientMsgID == message.clientMsgID && (playing || loading)) {
      try {
        await stop();
      } catch (error) {
        failed = true;
        VoicePlaybackLog.write('stop_failed', error: error);
        if (!_disposed) notifyListeners();
      }
    } else {
      await _play(message);
    }
  }

  Future<void> stop() async {
    _generation++;
    loading = playing = false;
    final lease = _lease;
    _lease = null;
    if (!_disposed) notifyListeners();
    if (lease != null) {
      await lease.release();
    } else {
      await _releasePlayer();
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _play(Message message, {Duration? initialPosition}) async {
    if (_disposed || coordinator.recording) return;
    final generation = ++_generation;
    if (current?.clientMsgID != message.clientMsgID) _duration = null;
    current = message;
    loading = true;
    playing = failed = false;
    notifyListeners();
    AudioPlayer? ownedPlayer;
    MediaLease? lease;
    try {
      lease = await coordinator.acquire(MediaKind.voice, () async {
        final retired = ownedPlayer;
        if (identical(_player, retired)) {
          if (retired != null &&
              retired.processingState != ProcessingState.completed) {
            _resumeID = message.clientMsgID;
            _resumePosition = retired.position;
          } else {
            _resumeID = null;
            _resumePosition = Duration.zero;
          }
          _player = null;
          _loadedID = null;
        }
        if (!_disposed && generation == _generation) {
          _generation++;
          loading = playing = false;
          notifyListeners();
        }
        await retired?.dispose();
      });
      if (lease == null || _disposed || generation != _generation) {
        await lease?.release();
        if (!_disposed && generation == _generation) {
          loading = playing = false;
          notifyListeners();
        }
        return;
      }
      _lease = lease;
      final player = ownedPlayer = _player = _playerFactory();
      await _prepare(player, message, generation,
              requestedPosition: initialPosition)
          .timeout(prepareTimeout);
      if (_disposed || generation != _generation || !lease.valid) return;
      _setStage('play', generation);
      Future<void>? playback;
      final started = await lease.run(() async {
        if (_speed != 1.0) await player.setSpeed(_speed);
        if (!lease!.valid) return;
        playback = player.play();
        // Attach an error handler before returning to the event loop.
        unawaited(playback!.catchError((Object _) {}));
      });
      if (!started) return;
      loading = false;
      playing = true;
      notifyListeners();
      if (onPlayed != null) {
        unawaited(onPlayed!(message).catchError((Object _) {}));
      }
      await playback;
      if (_disposed || generation != _generation || !lease.valid) return;
      if (player.processingState == ProcessingState.completed) {
        final next = nextMessage(messages(), message);
        if (next != null) {
          await _play(next);
          return;
        }
      }
      await stop();
    } catch (error) {
      if (!_disposed && generation == _generation) {
        VoicePlaybackLog.write('${_stage}_failed',
            error: error, attempt: generation);
        _generation++;
        loading = playing = false;
        failed = true;
        // Timeouts do not cancel Futures. Retire the player and invalidate all
        // late continuations before allowing a fresh retry.
        try {
          await lease?.release();
        } catch (cleanupError) {
          VoicePlaybackLog.write('dispose_failed', error: cleanupError);
        }
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> _prepare(AudioPlayer player, Message message, int generation,
      {Duration? requestedPosition}) async {
    if (Platform.isAndroid) {
      await player.setAndroidAudioAttributes(const AndroidAudioAttributes(
          usage: AndroidAudioUsage.voiceCommunication,
          contentType: AndroidAudioContentType.speech));
    }
    _setStage('player_stop', generation);
    await player.stop();
    if (_disposed || generation != _generation) return;
    if (_loadedID != message.clientMsgID || _loadedID == null) {
      _loadedID = null;
      final initialPosition = requestedPosition ??
          (_resumeID == message.clientMsgID ? _resumePosition : Duration.zero);
      _setStage('resolve_source', generation);
      final source = await _sourceLoader(message);
      if (_disposed || generation != _generation) return;
      _setStage(source.isFile ? 'load_file' : 'load_remote', generation);
      Duration? preparedDuration;
      if (source.isFile) {
        try {
          preparedDuration = await player.setFilePath(source.value,
              initialPosition: initialPosition);
        } catch (error) {
          if (_disposed || generation != _generation) return;
          final fallback = source.fallbackUrl;
          if (fallback == null) rethrow;
          VoicePlaybackLog.write('load_file_fallback',
              error: error, attempt: generation);
          _setStage('load_remote', generation);
          preparedDuration =
              await player.setUrl(fallback, initialPosition: initialPosition);
        }
      } else {
        preparedDuration =
            await player.setUrl(source.value, initialPosition: initialPosition);
      }
      if (_disposed || generation != _generation) return;
      _duration = preparedDuration;
      _loadedID = message.clientMsgID;
    } else if (player.processingState == ProcessingState.completed ||
        (player.duration != null && player.position >= player.duration!)) {
      _setStage('seek', generation);
      await player.seek(Duration.zero);
    }
  }

  void _setStage(String stage, int generation) {
    _stage = stage;
    VoicePlaybackLog.write(stage, attempt: generation);
  }

  Future<void> _releasePlayer() async {
    final player = _player;
    _player = null;
    _loadedID = null;
    await player?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(stop().catchError((Object error) {
        VoicePlaybackLog.write('stop_failed', error: error);
      }));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    loading = playing = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stop().catchError((Object error) {
      VoicePlaybackLog.write('stop_failed', error: error);
    }));
    super.dispose();
  }
}
