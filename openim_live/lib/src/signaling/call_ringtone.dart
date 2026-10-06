import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart' show Logger;

/// Incoming phone ringing and the caller's waiting sound use separate assets.
enum CallWaitingTone {
  incoming('assets/audio/live_ring.wav', 'openim_common'),
  outgoing('assets/audio/ringtone/outgoing_ringback.wav', 'openim_live');

  const CallWaitingTone(this.asset, this.package);
  final String asset, package;
}

/// A playback boundary for cancellation tests without opening native audio.
abstract interface class CallRingtonePlayer {
  Future<void> prepare(CallWaitingTone tone);
  Future<void> setAsset(String asset, {required String package});
  Future<void> setLooping();
  Future<void> setVolume(double volume);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

class _NativeCallRingtonePlayer implements CallRingtonePlayer {
  final _player = AudioPlayer(
    handleInterruptions: false,
    // AudioSession's default music fallback must not replace RTC voiceChat.
    handleAudioSessionActivation: false,
    androidApplyAudioAttributes: false,
  );

  @override
  Future<void> prepare(CallWaitingTone tone) async {
    if (Platform.isAndroid) {
      // This affects only this player. RTC still owns focus and speaker route;
      // the OS selects the volume stream for communication signalling usage.
      await _player.setAndroidAudioAttributes(AndroidAudioAttributes(
        contentType: AndroidAudioContentType.sonification,
        usage: tone == CallWaitingTone.outgoing
            ? AndroidAudioUsage.voiceCommunicationSignalling
            : AndroidAudioUsage.notificationRingtone,
      ));
    } else if (Platform.isIOS) {
      // Activate without configuring category/mode or deactivating on stop.
      // The room keeps ownership of its microphone, receiver and Bluetooth.
      if (!await AVAudioSession().setActive(true)) {
        throw StateError('Call audio session activation denied');
      }
    }
  }

  @override
  Future<void> setAsset(String asset, {required String package}) async {
    await _player.setAsset(asset, package: package);
  }

  @override
  Future<void> setLooping() => _player.setLoopMode(LoopMode.one);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

/// Owns waiting sounds separately from the media room. Stop/dispose immediately
/// invalidate and interrupt a pending load: late native completion cannot
/// restart a cancelled call or hold call cleanup behind asset preparation.
class CallRingtone {
  CallRingtone({CallRingtonePlayer Function()? createPlayer})
      : _createPlayer = createPlayer ?? _NativeCallRingtonePlayer.new;

  final CallRingtonePlayer Function() _createPlayer;
  CallRingtonePlayer? _player;
  Future<void> _operation = Future<void>.value();
  Future<void> _stopping = Future<void>.value();
  Future<void>? _disposing;
  int _generation = 0;
  bool _disposed = false;
  CallWaitingTone? _wanted;

  Future<void> play({CallWaitingTone tone = CallWaitingTone.incoming}) {
    if (_disposed || _wanted == tone) return _operation;
    _wanted = tone;
    final generation = ++_generation;
    return _enqueue(() async {
      try {
        await _stopping;
        if (!_current(generation)) return;
        final player = _player ??= _createPlayer();
        await player.stop();
        if (!_current(generation)) return;
        await player.prepare(tone);
        if (!_current(generation)) return;
        await player.setAsset(tone.asset, package: tone.package);
        if (!_current(generation)) return;
        await player.setLooping();
        if (!_current(generation)) return;
        await player.setVolume(1);
        if (!_current(generation)) return;
        // just_audio play completes at stop/end, never block setup on it.
        unawaited(player.play().catchError((Object error) {
          if (_current(generation)) {
            _wanted = null;
            Logger.print(
                'Call waiting playback unavailable (${tone.name}): ${error.runtimeType}');
          }
        }));
      } catch (_) {
        if (_current(generation)) _wanted = null;
        rethrow;
      }
    });
  }

  Future<void> stop() {
    _wanted = null;
    _generation++;
    // Native stop interrupts preparation; queuing behind setAsset can otherwise
    // leave cleanup waiting indefinitely on a native load that needs stop.
    final stopping = Future<void>.sync(() => _player?.stop());
    _stopping = stopping.catchError((Object _) {});
    return stopping;
  }

  Future<void> dispose() {
    final disposing = _disposing;
    if (disposing != null) return disposing;
    _disposed = true;
    _wanted = null;
    _generation++;
    final player = _player;
    _player = null;
    return _disposing = Future<void>.sync(() => player?.dispose());
  }

  bool _current(int generation) =>
      !_disposed && _wanted != null && generation == _generation;

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operation.then((_) => operation());
    _operation = next.catchError((Object _) {});
    return next;
  }
}
