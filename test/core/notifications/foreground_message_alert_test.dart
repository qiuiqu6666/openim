import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/foreground_message_alert.dart';

void main() {
  late _Player player;
  late _Vibrator vibrator;
  late ForegroundMessageAlert alert;
  var now = 1000;
  var creations = 0;

  setUp(() {
    now = 1000;
    creations = 0;
    player = _Player();
    vibrator = _Vibrator();
    alert = ForegroundMessageAlert(
      createPlayer: () {
        creations++;
        return player;
      },
      vibrator: vibrator,
      nowMs: () => now,
    );
  });
  tearDown(() => alert.dispose());

  Future<void> play({
    String soundID = 'crisp',
    bool sound = true,
    bool vibration = true,
    bool Function()? isCurrent,
  }) =>
      alert.play(
        soundID: soundID,
        sound: sound,
        vibration: vibration,
        isCurrent: isCurrent ?? () => true,
      );

  test('reuses one player and the loaded asset, rewinding each alert',
      () async {
    await play();
    now += 500;
    await play();
    expect(creations, 1);
    expect(player.assets, [('assets/audio/99chat/crisp.wav', 'openim_common')]);
    expect(player.starts, 2);
    expect(player.events.where((event) => event == 'seek'), hasLength(2));
    expect(player.volumes, [1, 1]);
    expect(vibrator.starts, 2);
  });

  test('cached audio prepares the session again for a later message', () async {
    await play(vibration: false);
    now += 1000;
    await play(vibration: false);
    expect(player.events.where((event) => event == 'prepare'), hasLength(2));
    expect(player.assets, hasLength(1));
    expect(player.starts, 2);
    expect(creations, 1);
  });

  test('uses the shared catalog for changed and unknown sound identifiers',
      () async {
    await play(soundID: 'soft', vibration: false);
    now += 500;
    await play(soundID: 'unknown', vibration: false);
    expect(player.assets, [
      ('assets/audio/99chat/soft.wav', 'openim_common'),
      ('assets/audio/99chat/preview000.wav', 'openim_common'),
    ]);
  });

  test('vibration works with sound off without allocating a player', () async {
    await play(sound: false);
    expect(creations, 0);
    expect(vibrator.starts, 1);
  });

  test('sound works with vibration off without querying the vibrator',
      () async {
    await play(vibration: false);
    expect(player.starts, 1);
    expect(vibrator.queries, 0);
  });

  test('disabled or stale requests do not acquire native resources', () async {
    await play(sound: false, vibration: false);
    await play(isCurrent: () => false);
    expect(creations, 0);
    expect(vibrator.queries, 0);
  });

  test('bursts within 500 ms are dropped, including while loading', () async {
    final gate = Completer<void>();
    player.gates['load'] = gate;
    final first = play();
    await _flush();
    now += 499;
    await play(soundID: 'soft');
    expect(player.assets, hasLength(1));
    expect(vibrator.starts, 1);
    gate.complete();
    await first;
    expect(player.starts, 1);
    await _flush();
    expect(player.assets, hasLength(1), reason: 'No delayed burst is queued');
  });

  test('playback completion does not block the next setup or stop', () async {
    await play(vibration: false);
    expect(player.playback.single.isCompleted, isFalse);
    now += 500;
    await play(vibration: false);
    expect(player.starts, 2);
    await alert.stop();
    expect(player.playback.every((entry) => entry.isCompleted), isTrue);
  });

  test('failed audio preparation does not suppress vibration or later audio',
      () async {
    player.failStageOnce = 'prepare';
    await play();
    expect(player.starts, 0);
    expect(vibrator.starts, 1);
    now += 500;
    await play();
    expect(player.starts, 1);
    expect(creations, 1);
  });

  test('a failed vibrator does not suppress audio', () async {
    vibrator.failQuery = true;
    await play();
    expect(player.starts, 1);
    expect(vibrator.starts, 0);
  });

  test('a device without a vibrator still plays audio', () async {
    vibrator.supported = false;
    await play();
    expect(player.starts, 1);
    expect(vibrator.starts, 0);
  });

  for (final stage in ['prepare', 'pause', 'load', 'seek', 'volume']) {
    test('a stale account or setting after $stage cannot start audio',
        () async {
      var current = true;
      final gate = Completer<void>();
      player.gates[stage] = gate;
      final pending = play(vibration: false, isCurrent: () => current);
      await _flush();
      expect(player.events.last, stage);
      current = false;
      gate.complete();
      await pending;
      expect(player.starts, 0);
      expect(player.events.last, stage,
          reason: 'No later preparation step may run');
    });
  }

  test('a stale vibrator query cannot trigger a late vibration', () async {
    var current = true;
    final gate = Completer<void>();
    vibrator.queryGate = gate;
    final pending = play(sound: false, isCurrent: () => current);
    await _flush();
    current = false;
    gate.complete();
    await pending;
    expect(vibrator.starts, 0);
  });

  test('a new account interrupts an old load and serializes the replacement',
      () async {
    final gate = Completer<void>();
    player.gates['load'] = gate;
    var oldAccount = true;
    final first = play(vibration: false, isCurrent: () => oldAccount);
    await _flush();
    oldAccount = false;
    now += 500;
    final replacement = play(soundID: 'soft', vibration: false);
    await _flush();
    expect(player.stops, 1, reason: 'Stop must interrupt the unresolved load');
    expect(player.assets, hasLength(1), reason: 'Loads must be serialized');
    gate.complete();
    await Future.wait([first, replacement]);
    expect(player.starts, 1);
    expect(player.assets.last.$1, 'assets/audio/99chat/soft.wav');
    expect(player.maxConcurrentLoads, 1);
    expect(creations, 1);
  });

  test('stop completes before an unresolved load and prevents its late play',
      () async {
    final gate = Completer<void>();
    player.gates['load'] = gate;
    final pending = play(vibration: false);
    await _flush();
    await alert.stop();
    expect(player.stops, 1);
    gate.complete();
    await pending;
    expect(player.starts, 0);
    await play(vibration: false);
    expect(player.starts, 1);
    expect(player.assets, hasLength(2));
  });

  test('stop before queued setup does not create a player', () async {
    final pending = play(vibration: false);
    await alert.stop();
    await pending;
    expect(creations, 0);
  });

  test('a cancelled asset replacement cannot reuse the previous cache key',
      () async {
    await play(vibration: false);
    final gate = Completer<void>();
    player.gates['load'] = gate;
    var current = true;
    now += 500;
    final pending =
        play(soundID: 'soft', vibration: false, isCurrent: () => current);
    await _flush();
    current = false;
    gate.complete();
    await pending;
    now += 500;
    await play(vibration: false);
    expect(player.assets.map((asset) => asset.$1), [
      'assets/audio/99chat/crisp.wav',
      'assets/audio/99chat/soft.wav',
      'assets/audio/99chat/crisp.wav',
    ]);
    expect(player.starts, 2);
  });

  test('stop invalidates a vibrator query without waiting for it', () async {
    final gate = Completer<void>();
    vibrator.queryGate = gate;
    final pending = play(sound: false);
    await _flush();
    await alert.stop();
    gate.complete();
    await pending;
    expect(vibrator.starts, 0);
  });

  test('stop cancels an already started native vibration', () async {
    final gate = Completer<void>();
    vibrator.playGate = gate;
    final pending = play(sound: false);
    await _flush();
    expect(vibrator.starts, 1);
    await alert.stop();
    expect(vibrator.cancels, 1);
    gate.complete();
    await pending;
  });

  test('a late native cancel cannot stop a replacement vibration', () async {
    await play(sound: false);
    final gate = Completer<void>();
    vibrator.cancelGate = gate;
    final stopping = alert.stop();
    final replacement = play(sound: false);
    await _flush();
    expect(vibrator.starts, 1);
    gate.complete();
    await Future.wait([stopping, replacement]);
    expect(vibrator.starts, 2);
    expect(vibrator.cancels, 1);
  });

  test('dispose interrupts loading once and never creates another player',
      () async {
    final gate = Completer<void>();
    player.gates['load'] = gate;
    final pending = play(vibration: false);
    await _flush();
    await alert.dispose();
    await alert.dispose();
    gate.complete();
    await pending;
    now += 500;
    await play();
    expect(player.starts, 0);
    expect(player.disposals, 1);
    expect(creations, 1);
    expect(vibrator.queries, 0);
  });

  test('asynchronous playback failure permits a later reloaded attempt',
      () async {
    player.failPlayback = true;
    await play(vibration: false);
    await _flush();
    player.failPlayback = false;
    now += 500;
    await play(vibration: false);
    expect(player.starts, 2);
    expect(player.assets, hasLength(2));
  });
}

class _Player implements ForegroundMessageAlertPlayer {
  final events = <String>[];
  final assets = <(String, String)>[];
  final volumes = <double>[];
  final playback = <Completer<void>>[];
  final gates = <String, Completer<void>>{};
  int starts = 0, stops = 0, disposals = 0;
  int concurrentLoads = 0, maxConcurrentLoads = 0;
  String? failStageOnce;
  bool failPlayback = false;

  Future<void> _stage(String name) async {
    events.add(name);
    if (failStageOnce == name) {
      failStageOnce = null;
      throw StateError('Native $name failed');
    }
    await gates[name]?.future;
  }

  @override
  Future<void> prepare() => _stage('prepare');
  @override
  Future<void> pause() async {
    _finishPlayback();
    await _stage('pause');
  }

  @override
  Future<void> setAsset(String asset, {required String package}) async {
    assets.add((asset, package));
    concurrentLoads++;
    if (concurrentLoads > maxConcurrentLoads) {
      maxConcurrentLoads = concurrentLoads;
    }
    try {
      await _stage('load');
    } finally {
      concurrentLoads--;
    }
  }

  @override
  Future<void> seekToStart() => _stage('seek');
  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    await _stage('volume');
  }

  @override
  Future<void> play() {
    starts++;
    if (failPlayback) return Future.error(StateError('Playback failed'));
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

class _Vibrator implements ForegroundMessageAlertVibrator {
  Completer<void>? queryGate, playGate, cancelGate;
  bool supported = true, failQuery = false;
  int queries = 0, starts = 0, cancels = 0;

  @override
  Future<bool> hasVibrator() async {
    queries++;
    if (failQuery) throw StateError('Vibrator query failed');
    await queryGate?.future;
    return supported;
  }

  @override
  Future<void> vibrate() async {
    starts++;
    await playGate?.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await cancelGate?.future;
  }
}

Future<void> _flush() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
