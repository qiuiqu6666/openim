import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

import 'message_notification_sound.dart';

/// The native playback boundary keeps cancellation tests off the audio device.
abstract interface class ForegroundMessageAlertPlayer {
  factory ForegroundMessageAlertPlayer.native() =
      _NativeForegroundMessageAlertPlayer;
  Future<void> prepare();
  Future<void> pause();
  Future<void> setAsset(String asset, {required String package});
  Future<void> seekToStart();
  Future<void> setVolume(double volume);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class ForegroundMessageAlertVibrator {
  Future<bool> hasVibrator();
  Future<void> vibrate();
  Future<void> cancel();
}

class _NativeForegroundMessageAlertPlayer
    implements ForegroundMessageAlertPlayer {
  bool _androidAttributesPrepared = false;
  final _player = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
    androidApplyAudioAttributes: false,
  );

  @override
  Future<void> prepare() async {
    if (Platform.isAndroid && !_androidAttributesPrepared) {
      // Only this player changes; RTC retains its focus, category and routing.
      await _player.setAndroidAudioAttributes(const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.sonification,
        usage: AndroidAudioUsage.notification,
      ));
      _androidAttributesPrepared = true;
    } else if (Platform.isIOS) {
      // Calls and media can deactivate the shared session between messages.
      // Activate on every accepted playback, even when its asset is cached.
      if (!await AVAudioSession().setActive(true)) {
        throw StateError('Message audio activation denied');
      }
    }
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> setAsset(String asset, {required String package}) async {
    await _player.setAsset(asset, package: package);
  }

  @override
  Future<void> seekToStart() => _player.seek(Duration.zero);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

class _NativeForegroundMessageAlertVibrator
    implements ForegroundMessageAlertVibrator {
  @override
  Future<bool> hasVibrator() => Vibration.hasVibrator();
  @override
  Future<void> vibrate() => Vibration.vibrate(duration: 200);
  @override
  Future<void> cancel() => Vibration.cancel();
}

/// One reusable foreground sound lane, independent of banner presentation.
/// The caller owns message policy and invalidates [isCurrent] on account,
/// preference, lifecycle or call changes, then calls [stop] to interrupt audio.
class ForegroundMessageAlert {
  ForegroundMessageAlert({
    ForegroundMessageAlertPlayer Function()? createPlayer,
    ForegroundMessageAlertVibrator? vibrator,
    int Function()? nowMs,
  })  : _createPlayer = createPlayer ?? _NativeForegroundMessageAlertPlayer.new,
        _vibrator = vibrator ?? _NativeForegroundMessageAlertVibrator(),
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const throttleMilliseconds = 500;
  final ForegroundMessageAlertPlayer Function() _createPlayer;
  final ForegroundMessageAlertVibrator _vibrator;
  final int Function() _nowMs;
  ForegroundMessageAlertPlayer? _player;
  String? _loadedAsset;
  int? _lastRequestedAt;
  int _generation = 0;
  int _soundSetups = 0;
  bool _vibrationStarted = false;
  bool _disposed = false;
  Future<void> _soundOperation = Future<void>.value();
  Future<void> _stopping = Future<void>.value();
  Future<void> _vibrationStopping = Future<void>.value();
  Future<void>? _disposing;

  /// Completes after setup, without waiting for native playback to finish.
  /// Bursts are discarded immediately and never become delayed notifications.
  Future<void> play({
    required String soundID,
    required bool sound,
    required bool vibration,
    required bool Function() isCurrent,
  }) {
    if (_disposed || !isCurrent() || (!sound && !vibration)) {
      return Future<void>.value();
    }
    final now = _nowMs();
    final previous = _lastRequestedAt;
    if (previous != null && now - previous < throttleMilliseconds) {
      return Future<void>.value();
    }
    _lastRequestedAt = now;
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation && isCurrent();

    if (_soundSetups > 0 || !sound) {
      // An old native load may need stop before it can complete. Do not put
      // this interruption behind that load in the serialized setup lane.
      unawaited(_interruptSound());
    }
    final operations = <Future<void>>[];
    if (sound) {
      _soundSetups++;
      final next = _soundOperation.then((_) =>
          _startSound(MessageNotificationSoundIds.assetPath(soundID), current));
      _soundOperation = next.catchError((Object _) {});
      operations.add(next.whenComplete(() => _soundSetups--));
    }
    if (vibration) operations.add(_startVibration(current));
    return Future.wait(operations).then((_) {});
  }

  Future<void> _startSound(String asset, bool Function() isCurrent) async {
    try {
      await _stopping;
      if (!isCurrent()) return;
      final player = _player ??= _createPlayer();
      await player.prepare();
      if (!isCurrent()) return;
      await player.pause();
      if (!isCurrent()) return;
      if (_loadedAsset != asset) {
        // A cancelled load can still change the native decoder before its
        // completion arrives. Do not retain the previous asset's cache key.
        _loadedAsset = null;
        await player.setAsset(asset, package: 'openim_common');
        if (!isCurrent()) return;
        _loadedAsset = asset;
      }
      await player.seekToStart();
      if (!isCurrent()) return;
      await player.setVolume(1);
      if (!isCurrent()) return;
      // just_audio's play future resolves at stop/end. Holding it here would
      // make the next load and cleanup wait for the entire notification sound.
      unawaited(Future<void>.sync(player.play).catchError((Object error) {
        if (!isCurrent()) return;
        _loadedAsset = null;
        _report(error);
      }));
    } catch (error) {
      if (!isCurrent()) return;
      _loadedAsset = null;
      _report(error);
    }
  }

  Future<void> _startVibration(bool Function() isCurrent) async {
    try {
      await _vibrationStopping;
      if (!isCurrent()) return;
      final supported = await _vibrator.hasVibrator();
      if (!isCurrent() || !supported) return;
      _vibrationStarted = true;
      await _vibrator.vibrate();
      if (!isCurrent()) return;
    } catch (error) {
      if (isCurrent()) _report(error);
    }
  }

  /// Immediately invalidates setup and stops native effects. Does not wait
  /// behind loading, and never deactivates the audio session shared with RTC.
  Future<void> stop() {
    _generation++;
    _lastRequestedAt = null;
    return Future.wait([_interruptSound(), _cancelVibration()]).then((_) {});
  }

  Future<void> _interruptSound() {
    _loadedAsset = null;
    final previous = _stopping;
    final stopping = Future<void>.sync(() => _player?.stop())
        .catchError((Object error) => _report(error));
    return _stopping = Future.wait([previous, stopping]).then((_) {});
  }

  Future<void> _cancelVibration() {
    if (!_vibrationStarted) return _vibrationStopping;
    _vibrationStarted = false;
    final previous = _vibrationStopping;
    final stopping = Future<void>.sync(_vibrator.cancel)
        .catchError((Object error) => _report(error));
    // A late native cancellation must finish before a replacement vibration.
    return _vibrationStopping = Future.wait([previous, stopping]).then((_) {});
  }

  Future<void> dispose() {
    final disposing = _disposing;
    if (disposing != null) return disposing;
    _disposed = true;
    _generation++;
    final player = _player;
    _player = null;
    _loadedAsset = null;
    return _disposing = Future.wait([
      Future<void>.sync(() => player?.dispose())
          .catchError((Object error) => _report(error)),
      _cancelVibration(),
    ]).then((_) {});
  }

  static void _report(Object error) {
    debugPrint('Foreground message alert unavailable: ${error.runtimeType}');
  }
}
