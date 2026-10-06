import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_live/src/signaling/call_ringtone.dart';

import 'support/waiting_tone_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WaitingTonePlayerProbe player;
  late CallRingtone ringtone;
  var creations = 0;

  setUp(() {
    creations = 0;
    player = WaitingTonePlayerProbe();
    ringtone = CallRingtone(createPlayer: () {
      creations++;
      return player;
    });
  });
  tearDown(() async => ringtone.dispose());

  test(
      'outgoing resource has an immediate 425 Hz tone and four seconds silence',
      () async {
    final data = await rootBundle
        .load('packages/openim_live/${CallWaitingTone.outgoing.asset}');
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(20, Endian.little), 1); // Linear PCM.
    expect(data.getUint16(22, Endian.little), 1); // Mono.
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint16(34, Endian.little), 16);
    expect(data.getUint32(40, Endian.little), 160000);
    final samples = List.generate(
        80000, (index) => data.getInt16(44 + index * 2, Endian.little));
    expect(samples.take(160).any((sample) => sample != 0), isTrue);
    expect(samples.skip(16000).every((sample) => sample == 0), isTrue);
    var upwardZeroCrossings = 0;
    for (var index = 1; index < 16000; index++) {
      if (samples[index - 1] <= 0 && samples[index] > 0) {
        upwardZeroCrossings++;
      }
    }
    expect(upwardZeroCrossings, closeTo(425, 1));
    expect(samples.every((sample) => sample.abs() <= 8192), isTrue);
  });

  test('incoming retains its own phone ring while outgoing loops the ringback',
      () async {
    await ringtone.play();
    expect(
        player.assets.single, ('assets/audio/live_ring.wav', 'openim_common'));
    await ringtone.stop();
    await ringtone.play(tone: CallWaitingTone.outgoing);
    expect(player.assets.last,
        ('assets/audio/ringtone/outgoing_ringback.wav', 'openim_live'));
    expect(
        player.prepared, [CallWaitingTone.incoming, CallWaitingTone.outgoing]);
    expect(player.loops, 2);
    expect(player.volumes, [1, 1]);
    expect(creations, 1);
  });

  test('duplicate waiting notifications do not reload or allocate a player',
      () async {
    final first = ringtone.play(tone: CallWaitingTone.outgoing);
    final duplicate = ringtone.play(tone: CallWaitingTone.outgoing);
    await Future.wait([first, duplicate]);
    await ringtone.play(tone: CallWaitingTone.outgoing);
    expect(player.assets, hasLength(1));
    expect(player.starts, 1);
    expect(creations, 1);
  });

  test('stop before setup never creates a native player', () async {
    final pending = ringtone.play(tone: CallWaitingTone.outgoing);
    await ringtone.stop();
    await pending;
    expect(creations, 0);
    expect(player.starts, 0);
  });

  for (final preparation in [true, false]) {
    test(
        'stop interrupts pending ${preparation ? 'session setup' : 'asset load'}',
        () async {
      final gate = Completer<void>();
      if (preparation) {
        player.prepareGate = gate;
      } else {
        player.loadGate = gate;
      }
      final pending = ringtone.play(tone: CallWaitingTone.outgoing);
      await flushWaitingToneTasks();
      expect(player.prepared, [CallWaitingTone.outgoing]);
      var stopped = false;
      final stopping = ringtone.stop().then((_) => stopped = true);
      await flushWaitingToneTasks();
      expect(stopped, isTrue, reason: 'Stop cannot wait behind native setup');
      expect(player.stops, 2);
      gate.complete();
      await Future.wait([pending, stopping]);
      expect(player.starts, 0);
      expect(player.loops, 0);
    });
  }

  test('an old load cannot play after a new call requests the same tone',
      () async {
    player.loadGate = Completer<void>();
    final first = ringtone.play(tone: CallWaitingTone.outgoing);
    await flushWaitingToneTasks();
    await ringtone.stop();
    final second = ringtone.play(tone: CallWaitingTone.outgoing);
    player.loadGate!.complete();
    await Future.wait([first, second]);
    expect(player.starts, 1);
    expect(player.assets, hasLength(2));
    expect(creations, 1);
  });

  test('switching incoming to outgoing cancels an old pending ringtone',
      () async {
    player.loadGate = Completer<void>();
    final incoming = ringtone.play();
    await flushWaitingToneTasks();
    final outgoing = ringtone.play(tone: CallWaitingTone.outgoing);
    player.loadGate!.complete();
    await Future.wait([incoming, outgoing]);
    expect(player.starts, 1);
    expect(player.assets.map((asset) => asset.$2),
        ['openim_common', 'openim_live']);
    expect(player.prepared.last, CallWaitingTone.outgoing);
  });

  test('playback completion is not held in the setup or stop queue', () async {
    await ringtone.play(tone: CallWaitingTone.outgoing);
    expect(player.playback.single.isCompleted, isFalse);
    await ringtone.stop();
    expect(player.playback.single.isCompleted, isTrue);
    await ringtone.play(tone: CallWaitingTone.outgoing);
    expect(player.starts, 2);
  });

  test('loading failure releases the wanted flag and permits the next attempt',
      () async {
    player.failLoadOnce = true;
    await expectLater(ringtone.play(tone: CallWaitingTone.outgoing),
        throwsA(isA<StateError>()));
    await ringtone.play(tone: CallWaitingTone.outgoing);
    expect(player.starts, 1);
    expect(player.assets, hasLength(2));
  });

  test('asynchronous playback failure permits a later attempt', () async {
    player.failPlayback = true;
    await ringtone.play(tone: CallWaitingTone.outgoing);
    await flushWaitingToneTasks();
    player.failPlayback = false;
    await ringtone.play(tone: CallWaitingTone.outgoing);
    expect(player.starts, 2);
    expect(player.assets, hasLength(2));
  });

  test('dispose interrupts preparation and cannot create another player',
      () async {
    player.loadGate = Completer<void>();
    final pending = ringtone.play(tone: CallWaitingTone.outgoing);
    await flushWaitingToneTasks();
    await ringtone.dispose();
    expect(player.disposals, 1);
    await ringtone.dispose();
    player.loadGate!.complete();
    await pending;
    await ringtone.play(tone: CallWaitingTone.outgoing);
    expect(player.starts, 0);
    expect(player.disposals, 1);
    expect(creations, 1);
  });
}
