import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:just_audio/just_audio.dart';

import 'voice/voice_playback_log.dart';
import 'voice/voice_playback_source.dart';

/// Conversation-owned playback survives rebuilding or covering message widgets.
class VoicePlaybackController extends ChangeNotifier
    with WidgetsBindingObserver {
  VoicePlaybackController(
      {required this.messages,
      this.onPlayed,
      AudioPlayer Function()? playerFactory,
      Future<VoicePlaybackSource> Function(Message)? sourceLoader,
      this.prepareTimeout = const Duration(seconds: 20)})
      : _playerFactory = playerFactory ?? AudioPlayer.new,
        _sourceLoader = sourceLoader ?? VoicePlaybackSource.load {
    WidgetsBinding.instance.addObserver(this);
  }
  final Iterable<Message> Function() messages;
  final Future<void> Function(Message)? onPlayed;
  static VoicePlaybackController? _active;
  final AudioPlayer Function() _playerFactory;
  final Future<VoicePlaybackSource> Function(Message) _sourceLoader;
  final Duration prepareTimeout;
  AudioPlayer? _player;
  String? _loadedID;
  Message? current;
  bool loading = false, playing = false, failed = false;
  bool _disposed = false;
  int _generation = 0;
  String _stage = 'idle';
  Stream<Duration>? get positionStream => _player?.positionStream;

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
    if (current?.clientMsgID == message.clientMsgID && (playing || loading)) {
      stop();
    } else {
      await _play(message);
    }
  }

  void stop() {
    final wasLoading = loading;
    _generation++;
    loading = playing = false;
    if (wasLoading) {
      // pause() does not abort source preparation. A new tap must not reuse a
      // native player still loading an old URL.
      _releasePlayer();
    } else {
      unawaited(_player?.pause().catchError((Object error) {
        VoicePlaybackLog.write('pause_failed', error: error);
      }));
    }
    if (_active == this) _active = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _play(Message message) async {
    if (_disposed) return;
    if (loading) stop();
    if (_active != this) _active?.stop();
    _active = this;
    final generation = ++_generation;
    current = message;
    loading = true;
    playing = failed = false;
    notifyListeners();
    try {
      final player = _player ??= _playerFactory();
      await _prepare(player, message, generation).timeout(prepareTimeout);
      if (_disposed || generation != _generation) return;
      _setStage('play', generation);
      loading = false;
      playing = true;
      notifyListeners();
      final playback = player.play();
      if (onPlayed != null) {
        unawaited(onPlayed!(message).catchError((Object _) {}));
      }
      await playback;
      if (_disposed || generation != _generation) return;
      if (player.processingState == ProcessingState.completed) {
        final next = nextMessage(messages(), message);
        if (next != null) {
          await _play(next);
          return;
        }
      }
      stop();
    } catch (error) {
      if (!_disposed && generation == _generation) {
        VoicePlaybackLog.write('${_stage}_failed',
            error: error, attempt: generation);
        _generation++;
        loading = playing = false;
        failed = true;
        // Timeouts do not cancel Futures. Retire the player and invalidate all
        // late continuations before allowing a fresh retry.
        _releasePlayer();
        if (_active == this) _active = null;
        notifyListeners();
      }
    }
  }

  Future<void> _prepare(
      AudioPlayer player, Message message, int generation) async {
    _setStage('player_stop', generation);
    await player.stop();
    if (_disposed || generation != _generation) return;
    if (_loadedID != message.clientMsgID || _loadedID == null) {
      _loadedID = null;
      _setStage('resolve_source', generation);
      final source = await _sourceLoader(message);
      if (_disposed || generation != _generation) return;
      _setStage(source.isFile ? 'load_file' : 'load_remote', generation);
      if (source.isFile) {
        try {
          await player.setFilePath(source.value);
        } catch (error) {
          if (_disposed || generation != _generation) return;
          final fallback = source.fallbackUrl;
          if (fallback == null) rethrow;
          VoicePlaybackLog.write('load_file_fallback',
              error: error, attempt: generation);
          _setStage('load_remote', generation);
          await player.setUrl(fallback);
        }
      } else {
        await player.setUrl(source.value);
      }
      if (_disposed || generation != _generation) return;
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

  void _releasePlayer() {
    final player = _player;
    _player = null;
    _loadedID = null;
    unawaited(player?.dispose().catchError((Object error) {
      VoicePlaybackLog.write('dispose_failed', error: error);
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    loading = playing = false;
    if (_active == this) _active = null;
    WidgetsBinding.instance.removeObserver(this);
    _releasePlayer();
    super.dispose();
  }
}
