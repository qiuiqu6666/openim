import 'dart:async';

import 'package:openim_live/src/signaling/call_ringtone.dart';

class WaitingTonePlayerProbe implements CallRingtonePlayer {
  final assets = <(String, String)>[];
  final prepared = <CallWaitingTone>[];
  final volumes = <double>[];
  final playback = <Completer<void>>[];
  Completer<void>? prepareGate, loadGate;
  int starts = 0, stops = 0, disposals = 0, loops = 0;
  bool failLoadOnce = false, failPlayback = false;

  @override
  Future<void> prepare(CallWaitingTone tone) async {
    prepared.add(tone);
    await prepareGate?.future;
  }

  @override
  Future<void> setAsset(String asset, {required String package}) async {
    assets.add((asset, package));
    if (failLoadOnce) {
      failLoadOnce = false;
      throw StateError('Native asset preparation failed');
    }
    await loadGate?.future;
  }

  @override
  Future<void> setLooping() async => loops++;
  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> play() {
    starts++;
    if (failPlayback) return Future.error(StateError('Native playback failed'));
    final completion = Completer<void>();
    playback.add(completion);
    return completion.future;
  }

  void _finishPlayback() {
    for (final completion in playback) {
      if (!completion.isCompleted) completion.complete();
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    _finishPlayback();
  }

  @override
  Future<void> dispose() async {
    disposals++;
    _finishPlayback();
  }
}

Future<void> flushWaitingToneTasks() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
