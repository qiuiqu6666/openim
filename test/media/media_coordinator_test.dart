import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/media/media_coordinator.dart';

void main() {
  late MediaCoordinator coordinator;
  late List<String> events;
  String? stored;
  setUp(() {
    events = [];
    stored = null;
    coordinator = MediaCoordinator(
      readMode: () async => stored,
      writeMode: (value) async {
        stored = value;
      },
      configure: (kind, mode) async => events.add('${kind?.name}:${mode.name}'),
    );
  });
  test('mode defaults to speaker, survives sessions and restores on restart',
      () async {
    await coordinator.initialize();
    expect(coordinator.output.value, VoiceOutput.speaker);
    await coordinator.setOutput(VoiceOutput.earpiece);
    final voice = await coordinator.acquire(MediaKind.voice, () async {});
    expect(events.last, 'voice:earpiece');
    await voice!.release();
    await coordinator.acquire(MediaKind.voice, () async {});
    expect(events.last, 'voice:earpiece');
    final restored = MediaCoordinator(
        readMode: () async => stored,
        writeMode: (_) async {},
        configure: (_, __) async {});
    await restored.initialize();
    expect(restored.output.value, VoiceOutput.earpiece);
  });
  test('live mode changes neither stop nor replace the current lease',
      () async {
    var stops = 0;
    final voice = await coordinator.acquire(MediaKind.voice, () async {
      stops++;
    });
    await Future.wait([
      coordinator.setOutput(VoiceOutput.earpiece),
      coordinator.setOutput(VoiceOutput.speaker)
    ]);
    expect(stops, 0);
    expect(voice!.valid, isTrue);
    expect(coordinator.output.value, VoiceOutput.speaker);
    expect(stored, 'speaker');
    expect(events.last, 'voice:speaker');
  });
  test('video waits for voice release; voice replaces video without resuming',
      () async {
    final stopped = Completer<void>();
    final voice =
        await coordinator.acquire(MediaKind.voice, () => stopped.future);
    var gotVideo = false;
    final request = coordinator.acquire(MediaKind.video, () async {
      events.add('videoStopped');
    })
      ..then((_) {
        gotVideo = true;
      });
    await Future<void>.delayed(Duration.zero);
    expect(voice!.valid, isFalse);
    expect(gotVideo, isFalse);
    stopped.complete();
    final video = await request;
    final next = await coordinator.acquire(MediaKind.voice, () async {});
    expect(video!.valid, isFalse);
    expect(next!.valid, isTrue);
    expect(events.indexOf('videoStopped'),
        lessThan(events.lastIndexOf('voice:speaker')));
    await next.release();
    expect(coordinator.activeKind, isNull);
  });
  test('recording reserves ownership immediately, including while voice stops',
      () async {
    final stopped = Completer<void>();
    await coordinator.acquire(MediaKind.voice, () => stopped.future);
    final recording = coordinator.acquire(MediaKind.recording, () async {});
    expect(coordinator.recording, isTrue);
    expect(await coordinator.acquire(MediaKind.voice, () async {}), isNull);
    expect(await coordinator.acquire(MediaKind.video, () async {}), isNull);
    stopped.complete();
    final lease = await recording;
    await coordinator.setOutput(VoiceOutput.earpiece);
    expect(events.last, 'recording:speaker');
    await lease!.release(stopped: true);
    expect(coordinator.recording, isFalse);
    expect(coordinator.activeKind, isNull);
  });
  test('latest rapid playback request wins and stale native start is rejected',
      () async {
    final stop = Completer<void>();
    final first = await coordinator.acquire(MediaKind.voice, () => stop.future);
    final second = coordinator.acquire(MediaKind.video, () async {});
    final third = coordinator.acquire(MediaKind.voice, () async {});
    var staleStarted = false;
    final stale = first!.run(() async {
      staleStarted = true;
    });
    stop.complete();
    expect(await second, isNull);
    expect((await third)!.valid, isTrue);
    expect(await stale, isFalse);
    expect(staleStarted, isFalse);
  });
  test('failed stop blocks another native player; queue can retry cleanup',
      () async {
    var fail = true;
    await coordinator.acquire(MediaKind.voice, () async {
      if (fail) throw StateError('stop failed');
    });
    await expectLater(
        coordinator.acquire(MediaKind.video, () async {}), throwsStateError);
    expect(events, ['voice:speaker']);
    fail = false;
    expect((await coordinator.acquire(MediaKind.video, () async {}))!.valid,
        isTrue);
  });
  test('old owner release cannot stop a newer media', () async {
    final old = await coordinator.acquire(MediaKind.voice, () async {});
    final next = await coordinator.acquire(MediaKind.video, () async {});
    await old!.release();
    expect(next!.valid, isTrue);
  });
  test('pending recording cancelled by stop does not leave a recording lock',
      () async {
    final stopped = Completer<void>();
    await coordinator.acquire(MediaKind.voice, () => stopped.future);
    final recording = coordinator.acquire(MediaKind.recording, () async {});
    final cancelled = coordinator.stop();
    stopped.complete();
    expect(await recording, isNull);
    await cancelled;
    expect(coordinator.recording, isFalse);
    expect((await coordinator.acquire(MediaKind.voice, () async {}))!.valid,
        isTrue);
  });
  test('notification sounds cannot interrupt voice or recording', () async {
    final voice = await coordinator.acquire(MediaKind.voice, () async {});
    expect(await coordinator.acquire(MediaKind.alert, () async {}), isNull);
    expect(voice!.valid, isTrue);
    await voice.release();
    final recording =
        await coordinator.acquire(MediaKind.recording, () async {});
    expect(await coordinator.acquire(MediaKind.alert, () async {}), isNull);
    expect(recording!.valid, isTrue);
    await recording.release(stopped: true);
  });
}
