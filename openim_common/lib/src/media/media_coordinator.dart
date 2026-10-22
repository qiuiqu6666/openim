import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MediaKind { voice, video, recording, alert }

enum VoiceOutput { speaker, earpiece }

/// One application-wide arbiter. Images never acquire a lease.
/// A lease is invalidated synchronously; native stop/start operations are queued.
class MediaCoordinator {
  MediaCoordinator({
    Future<String?> Function()? readMode,
    Future<void> Function(String)? writeMode,
    Future<void> Function(MediaKind?, VoiceOutput)? configure,
  })  : _readMode = readMode ?? _readPreference,
        _writeMode = writeMode ?? _writePreference,
        _configure = configure ?? _configureNative;

  static final instance = MediaCoordinator().._listenToNative();
  static const channel = MethodChannel('openim/media_audio');
  static const preferenceKey = 'voice_output_mode';
  final Future<String?> Function() _readMode;
  final Future<void> Function(String) _writeMode;
  final Future<void> Function(MediaKind?, VoiceOutput) _configure;
  final output = ValueNotifier(VoiceOutput.speaker);
  Future<void>? _tail;
  Future<void>? _initialized;
  bool _ready = false;
  MediaLease? _active;
  MediaLease? _recording;
  int _intent = 0;

  bool get recording => _recording != null;
  MediaKind? get activeKind => _active?.kind;

  static Future<String?> _readPreference() async {
    try {
      return (await SharedPreferences.getInstance()).getString(preferenceKey);
    } on MissingPluginException {
      // Desktop/headless tests have no mobile route bridge.
      if (Platform.isAndroid || Platform.isIOS) rethrow;
      return null;
    }
  }

  static Future<void> _writePreference(String value) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(preferenceKey, value)) {
      throw StateError('Unable to save voice output mode');
    }
  }

  static Future<void> _configureNative(
      MediaKind? kind, VoiceOutput output) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await channel.invokeMethod<void>('configure', {
      'kind': kind?.name,
      'output': output.name,
    });
  }

  void _listenToNative() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'interrupted' && !recording) {
        try {
          await stop();
        } catch (error) {
          debugPrint('Media interruption cleanup failed: ${error.runtimeType}');
        }
      }
    });
  }

  Future<void> initialize() =>
      _ready ? Future<void>.value() : (_initialized ??= _loadMode());
  Future<void> _loadMode() async {
    output.value = await _readMode() == 'earpiece'
        ? VoiceOutput.earpiece
        : VoiceOutput.speaker;
    _ready = true;
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final pending = _tail;
    final result = pending == null
        ? Future<T>.sync(action)
        : pending.then((_) => action());
    final settled =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return result;
  }

  Future<void> setOutput(VoiceOutput value) => _serial(() async {
        await initialize();
        // Persistence and routing share the queue, so the last requested mode wins.
        await _writeMode(value.name);
        output.value = value;
        if (_active?.kind == MediaKind.voice && _active!.valid) {
          await _configure(MediaKind.voice, value);
        }
      });

  Future<MediaLease?> acquire(MediaKind kind, Future<void> Function() stop) {
    if (_recording != null ||
        (kind == MediaKind.alert && (_active != null || _tail != null))) {
      return Future.value(null);
    }
    final lease = MediaLease._(this, kind, stop);
    if (kind == MediaKind.recording) _recording = lease;
    final intent = ++_intent;
    _active?._preempted = true;
    _active?._valid = false;
    return _serial(() async {
      try {
        await initialize();
        await _stopActive();
        if (intent != _intent) {
          if (identical(_recording, lease)) _recording = null;
          return null;
        }
        _active = lease;
        await _configure(kind, output.value);
        if (intent != _intent) {
          lease._valid = false;
          await _stopActive();
          return null;
        }
        return lease;
      } catch (_) {
        lease._valid = false;
        if (identical(_recording, lease)) _recording = null;
        if (identical(_active, lease)) await _stopActive();
        rethrow;
      }
    });
  }

  Future<void> _stopActive({bool stopped = false}) async {
    final old = _active;
    if (old == null) return;
    old._valid = false;
    // Keep ownership on failure: never start another player over a failed stop.
    if (!stopped) await old._stop();
    await _configure(null, output.value);
    if (identical(_active, old)) _active = null;
    if (identical(_recording, old)) _recording = null;
  }

  Future<void> stop() {
    ++_intent;
    _active?._preempted = true;
    _active?._valid = false;
    return _serial(() => _stopActive());
  }
}

class MediaLease {
  MediaLease._(this._coordinator, this.kind, this._stop);
  final MediaCoordinator _coordinator;
  final MediaKind kind;
  final Future<void> Function() _stop;
  bool _valid = true;
  bool _preempted = false;
  bool get wasPreempted => _preempted;
  bool get valid => _valid && identical(_coordinator._active, this);

  /// Short native commands only. Never enqueue an entire playback Future.
  Future<bool> run(Future<void> Function() operation) =>
      _coordinator._serial(() async {
        if (!valid) return false;
        await _coordinator._configure(kind, _coordinator.output.value);
        if (!valid) return false;
        await operation();
        return valid;
      });

  Future<void> release({bool stopped = false}) {
    _valid = false;
    return _coordinator._serial(() async {
      if (identical(_coordinator._active, this)) {
        await _coordinator._stopActive(stopped: stopped);
      }
    });
  }
}
