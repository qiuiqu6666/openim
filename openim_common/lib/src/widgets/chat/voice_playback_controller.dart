import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:just_audio/just_audio.dart';

/// Conversation-owned playback survives rebuilding or covering message widgets.
class VoicePlaybackController extends ChangeNotifier
    with WidgetsBindingObserver {
  VoicePlaybackController(
      {required this.messages,
      this.onPlayed,
      AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new {
    WidgetsBinding.instance.addObserver(this);
  }
  final Iterable<Message> Function() messages;
  final Future<void> Function(Message)? onPlayed;
  static VoicePlaybackController? _active;
  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;
  String? _loadedID;
  Message? current;
  bool loading = false, playing = false, failed = false;
  bool _disposed = false;
  int _generation = 0;
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
    _generation++;
    loading = playing = false;
    unawaited(_player?.pause());
    if (_active == this) _active = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _play(Message message) async {
    if (_disposed) return;
    if (_active != this) _active?.stop();
    _active = this;
    final generation = ++_generation;
    current = message;
    loading = true;
    playing = failed = false;
    notifyListeners();
    try {
      final player = _player ??= _playerFactory();
      await player.stop();
      if (_disposed || generation != _generation) return;
      if (_loadedID != message.clientMsgID || _loadedID == null) {
        final sound = message.soundElem!;
        final path = sound.soundPath;
        final local =
            path != null && path.isNotEmpty && await File(path).exists();
        if (_disposed || generation != _generation) return;
        _loadedID = null;
        if (local) {
          await player.setFilePath(path);
        } else {
          final url = sound.sourceUrl;
          if (url == null || url.isEmpty) throw StateError('Missing audio URL');
          await player.setUrl(url);
        }
        if (_disposed || generation != _generation) return;
        _loadedID = message.clientMsgID;
      } else if (player.processingState == ProcessingState.completed ||
          (player.duration != null && player.position >= player.duration!)) {
        await player.seek(Duration.zero);
      }
      if (_disposed || generation != _generation) return;
      loading = false;
      playing = true;
      notifyListeners();
      final playback = player.play();
      if (onPlayed != null)
        unawaited(onPlayed!(message).catchError((Object _) {}));
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
    } catch (_) {
      if (!_disposed && generation == _generation) {
        stop();
        failed = true;
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_active == this) _active = null;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_player?.dispose());
    super.dispose();
  }
}
